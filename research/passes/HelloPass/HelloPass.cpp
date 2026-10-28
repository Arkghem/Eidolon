// HelloPass -- procedural HDR test pattern. See HelloPass.h for the rationale.
#include "HelloPass.h"

#include "RenderGraph/RenderPassStandardFlags.h"

#include "Eidolon/Common.hpp"

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, HelloPass>();
}

namespace
{
// Relative to the shader output directory (target_copy_shaders() deploys
// shaders/HelloPass.cs.slang to <bin>/shaders/RenderPasses/HelloPass/).
const char kComputeShader[] = "RenderPasses/HelloPass/HelloPass.cs.slang";

const char kFrequency[] = "frequency";
const char kSpeed[] = "speed";
const char kShowGrid[] = "showGrid";
} // namespace

HelloPass::HelloPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    parseProperties(props);
    createComputePass();
}

void HelloPass::createComputePass()
{
    mpComputePass = ComputePass::create(mpDevice, kComputeShader, "main");
}

void HelloPass::parseProperties(const Properties& props)
{
    for (const auto& [key, value] : props)
    {
        if (key == kFrequency)
            mFrequency = value;
        else if (key == kSpeed)
            mSpeed = value;
        else if (key == kShowGrid)
            mShowGrid = static_cast<bool>(value);
        else
            logWarning("Unknown property '{}' in HelloPass properties.", key);
    }
}

void HelloPass::setProperties(const Properties& props)
{
    parseProperties(props);
    mOptionsChanged = true;
}

Properties HelloPass::getProperties() const
{
    Properties props;
    props[kFrequency] = mFrequency;
    props[kSpeed] = mSpeed;
    props[kShowGrid] = mShowGrid;
    return props;
}

RenderPassReflection HelloPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;
    reflector.addOutput("color", "HDR color output")
        .format(ResourceFormat::RGBA16Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess | ResourceBindFlags::ShaderResource);
    return reflector;
}

void HelloPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    auto& dict = renderData.getDictionary();
    if (mOptionsChanged)
    {
        auto flags = dict.getValue(kRenderPassRefreshFlags, RenderPassRefreshFlags::None);
        dict[kRenderPassRefreshFlags] = flags | RenderPassRefreshFlags::RenderOptionsChanged;
        mOptionsChanged = false;
    }

    const auto& pOutput = renderData.getTexture("color");
    if (!pOutput) return;

    const uint2 dims = renderData.getDefaultTextureDims();
    FALCOR_ASSERT(dims.x > 0 && dims.y > 0);

    auto var = mpComputePass->getRootVar();
    var["CB"]["gResolution"] = dims;
    var["CB"]["gFrameIndex"] = mFrameIndex;
    var["CB"]["gFrequency"] = mFrequency;
    var["CB"]["gSpeed"] = mSpeed;
    var["CB"]["gShowGrid"] = mShowGrid ? 1u : 0u;
    var["gOutput"] = pOutput;

    mpComputePass->execute(pRenderContext, dims.x, dims.y, 1u);

    Eidolon::setFrameIndex(dict, mFrameIndex);
    mFrameIndex++;
}

void HelloPass::renderUI(Gui::Widgets& widget)
{
    bool dirty = false;
    dirty |= widget.var("Frequency", mFrequency, 0.1f, 32.f);
    dirty |= widget.var("Speed", mSpeed, 0.f, 5.f);
    dirty |= widget.checkbox("Show grid", mShowGrid);

    if (widget.button("Restart animation"))
    {
        mFrameIndex = 0u;
        dirty = true;
    }

    if (dirty) mOptionsChanged = true;
}
