// __PASS_NAME__ compute shader.
//
// Self-contained on purpose: Falcor has no built-in deployment rule for shared
// .slangh headers, so a new pass starts with everything it needs in one file.
// See research/shared/shaders/Eidolon/README.md before introducing includes.

RWTexture2D<float4> gOutput;

cbuffer CB
{
    uint2 gResolution;
    uint gFrameIndex;
    uint gSpp;
};

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    uint2 coord = dispatchThreadId.xy;
    if (any(coord >= gResolution))
        return;

    float2 uv = (float2(coord) + 0.5) / float2(gResolution);

    // TODO: replace with the actual effect.
    gOutput[coord] = float4(uv.x, uv.y, 0.5, 1.0);
}
