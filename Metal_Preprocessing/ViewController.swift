import UIKit
import AVFoundation
import Vision

final class ViewController: UIViewController {
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer!
    private var captureSession: AVCaptureSession!
    fileprivate var final: CIImage? = nil
    fileprivate var transformedImages: [CIImage] = []
    fileprivate var reference: CVPixelBuffer? = nil

    fileprivate let warpKernel: CIWarpKernel = {
        let url = Bundle.main.url(forResource: "default", withExtension: ".metallib")!
        let data = try! Data.init(contentsOf: url)
        return try! CIWarpKernel(functionName: "warpHomography", fromMetalLibraryData: data)
    }()

    fileprivate let medianReductionKernel: CIColorKernel = {
        let url = Bundle.main.url(forResource: "default", withExtension: ".metallib")!
        let data = try! Data.init(contentsOf: url)
        return try! CIColorKernel(functionName: "medianReduction5", fromMetalLibraryData: data)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        captureSession = AVCaptureSession()
        captureSession.startRunning()

        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        videoPreviewLayer.frame = view.layer.bounds
        view.layer.addSublayer(videoPreviewLayer!)

        if let captureDevice = AVCaptureDevice.default(for: AVMediaType.video),
            let captureDeviceInput = try? AVCaptureDeviceInput(device: captureDevice),
            captureSession.canAddInput(captureDeviceInput) {
            captureSession.addInput(captureDeviceInput)
        }

        let captureVideoOutput = AVCaptureVideoDataOutput()
        captureVideoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .userInitiated))
        if captureSession.canAddOutput(captureVideoOutput) {
            captureSession.addOutput(captureVideoOutput)
        }
    }

    func homographicTransform(from image: CVPixelBuffer, to reference: CVPixelBuffer) -> matrix_float3x3? {
        let request = VNHomographicImageRegistrationRequest(targetedCVPixelBuffer: image, options: [:])
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: reference, options: [:])

        try? requestHandler.perform([request])

        guard let results = request.results,
            let observation = results.first as? VNImageHomographicAlignmentObservation else {
                return nil
        }
        return observation.warpTransform
    }

    func handleBarcodeRequest(request: VNRequest, error: Error?) {
        guard let payloads = request.results?.flatMap({ ($0 as! VNBarcodeObservation).payloadStringValue }),
         !payloads.isEmpty else {
            return
        }
        print(payloads)
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        guard let reference = reference else {
            self.reference = pixelBuffer
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let extent = CGRect(x: 0, y: 0, width: width, height: height)

        if case 0..<5 = transformedImages.count {
            let transform = homographicTransform(from: reference, to: pixelBuffer)!
            let ref = CIImage(cvPixelBuffer: pixelBuffer)
            let transformedBuffer = warpKernel.apply(extent: extent, roiCallback: { _,_ in return CGRect.null }, image: ref, arguments: [transform])!
            transformedImages.append(transformedBuffer)
        } else {
            guard let final = medianReductionKernel.apply(extent: extent, roiCallback: { _,_ in return CGRect.null} , arguments: transformedImages + [reference]) else {
                return
            }

            var requestOptions: [VNImageOption: Any] = [:]

            if let cameraIntrinsics = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
                requestOptions = [.cameraIntrinsics: cameraIntrinsics]
            }

            let imageRequestHandler = VNImageRequestHandler(ciImage: final, options: requestOptions)
            let detectBarcodeRequest = VNDetectBarcodesRequest(completionHandler: handleBarcodeRequest)
            detectBarcodeRequest.symbologies = [.code39, .code128]
            try? imageRequestHandler.perform([detectBarcodeRequest])

            self.reference = nil
            transformedImages = []
        }
    }
}
