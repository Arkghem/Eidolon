// HelloPass -- procedural HDR test pattern.
//
// Writes RGBA16F so downstream passes (ToneMapper) exercise the real HDR path.
// The pattern moves with gFrameIndex, which makes a stalled graph obvious at a
// glance and gives RenderDoc a changing frame to capture.

RWTexture2D<float4> gOutput;

cbuffer CB
{
    uint2 gResolution;
    uint gFrameIndex;
    float gFrequency;
    float gSpeed;
    uint gShowGrid;
};

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    uint2 coord = dispatchThreadId.xy;
    if (any(coord >= gResolution))
        return;

    float2 uv = (float2(coord) + 0.5) / float2(gResolution);
    float2 p = uv * 2.0 - 1.0;

    float t = float(gFrameIndex) * gSpeed;
    float r = length(p);

    // Concentric waves plus an animated color swirl.
    float wave = 0.5 + 0.5 * sin(gFrequency * 6.2831853 * r - t);
    float3 color;
    color.r = wave;
    color.g = 0.5 + 0.5 * sin(uv.x * 6.0 - t * 0.7);
    color.b = 0.5 + 0.5 * cos(uv.y * 6.0 - t * 0.5);

    // HDR highlight in the middle (values well above 1.0 so tone mapping matters).
    color *= 1.0 + 6.0 * exp(-6.0 * r);

    if (gShowGrid != 0u)
    {
        float2 g = frac(uv * 16.0);
        float line = min(g.x, g.y);
        color = lerp(color * 0.15, color, smoothstep(0.0, 0.03, line));
    }

    gOutput[coord] = float4(color, 1.0);
}
