#include <metal_stdlib>
using namespace metal;

#include <CoreImage/CoreImage.h>

extern "C" { namespace coreimage {

float2 warpHomography(float3x3 h, destination dest)
{
    float3 homogeneousDestCoord = float3(dest.coord(), 1.0);
    float3 homogeneousSrcCoord = h * homogeneousDestCoord;
    float2 srcCoord = homogeneousSrcCoord.xy / max(homogeneousSrcCoord.z, 0.000001);
    return srcCoord;
}

inline void swap(thread float4 &a, thread float4 &b)
{
    float4 tmp = a; a = min(a,b); b = max(tmp, b); // swap sort of two elements
}

float4 medianReduction5(sample_t v0, sample_t v1, sample_t v2, sample_t v3, sample_t v4)
{
    // using a Bose-Nelson sorting network
    swap(v0, v1); swap(v3, v4); swap(v2, v4); swap(v2, v3); swap(v0, v3); swap(v0, v2); swap(v1, v4); swap(v1, v3); swap(v1, v2);
    return v2;
}

}}
