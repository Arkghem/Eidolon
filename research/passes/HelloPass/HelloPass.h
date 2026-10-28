// HelloPass -- procedural HDR test pattern.
//
// Purpose: prove the whole research pipeline end to end (plugin build, shader
// deployment, plugin.json registration, Mogwai discovery, RenderDoc capture)
// with something that cannot fail for scene-related reasons.
//
// It is intentionally *not* a path tracer: a minimal ray tracing pass needs the
// full Scene/Slang plumbing (see Falcor's MinimalPathTracer, ~600 lines plus a
// 700-line .rt.slang). Copy that pattern when you write your first real pass;
// this one exists so a broken setup is diagnosed in one frame instead of one
// afternoon.
#pragma once

#include "Falcor.h"
#include "RenderGraph/RenderPass.h"

using namespace Falcor;

class HelloPass : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(
        HelloPass,
        "HelloPass",
        "Procedural HDR test pattern. Smoke test for the Eidolon research pipeline."
    );

    static ref<HelloPass> create(ref<Device> pDevice, const Properties& props)
    {
        return make_ref<HelloPass>(pDevice, props);
    }

    HelloPass(ref<Device> pDevice, const Properties& props);

    virtual void setProperties(const Properties& props) override;
    virtual Properties getProperties() const override;
    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;

private:
    void parseProperties(const Properties& props);
    void createComputePass();

    ref<ComputePass> mpComputePass;

    // UI parameters, serialized so that Mogwai's "Save Config" reproduces an
    // experiment exactly.
    float mFrequency = 4.f;
    float mSpeed = 1.f;
    bool mShowGrid = true;

    bool mOptionsChanged = false;
    uint32_t mFrameIndex = 0u;
};
