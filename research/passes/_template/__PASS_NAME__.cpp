// __PASS_NAME__ -- <one-line description of what this pass does>.
#include "__PASS_NAME__.h"

#include "RenderGraph/RenderPassStandardFlags.h"

#include "Eidolon/Common.hpp"

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, __PASS_NAME__>();
}

namespace
{
// Path is relative to the shader output directory: target_copy_shaders() in
// CMakeLists.txt deploys shaders/ to shaders/RenderPasses/__PASS_NAME__/.
const char kComputeShader[] = "RenderPasses/__PASS_NAME__/__PASS_NAME__.cs.slang";

const char kSpp[] = "spp";
} // namespace

__PASS_NAME__::__PASS_NAME__(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    parseProperties(props);
    mpComputePass = ComputePass::create(mpDevice, kComputeShader, "main");
}

void __PASS_NAME__::parseProperties(const Properties& props)
{
    for (const auto& [key, value] : props)
    {
        if (key == kSpp)
            mSpp = value;
        else
            logWarning("Unknown property '{}' in __PASS_NAME__ properties.", key);
    }
}

void __PASS_NAME__::setProperties(const Properties& props)
{
    parseProperties(props);
    mOptionsChanged = true;
}

Properties __PASS_NAME__::getProperties() const
{
    Properties props;
    props[kSpp] = mSpp;
    return props;
}

RenderPassReflection __PASS_NAME__::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;
    reflector.addOutput("color", "HDR color output")
        .format(ResourceFormat::RGBA16Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess | ResourceBindFlags::ShaderResource);
    return reflector;
}

void __PASS_NAME__::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    // Tell downstream passes that temporal history is invalid.
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
    var["CB"]["gSpp"] = mSpp;
    var["gOutput"] = pOutput;

    mpComputePass->execute(pRenderContext, dims.x, dims.y, 1u);

    Eidolon::setFrameIndex(dict, mFrameIndex);
    mFrameIndex++;
}

void __PASS_NAME__::renderUI(Gui::Widgets& widget)
{
    bool dirty = false;
    dirty |= widget.var("Samples per pixel", mSpp, 1u, 64u);
    widget.tooltip("Number of samples accumulated per pixel each frame.", true);

    if (dirty) mOptionsChanged = true;
}
