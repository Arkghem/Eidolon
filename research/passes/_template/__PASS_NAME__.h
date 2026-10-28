// __PASS_NAME__ -- <one-line description of what this pass does>.
//
// API shape follows Falcor's RenderPassTemplate sample (BSD-3-Clause, NVIDIA):
// the static create() is what the plugin manager calls, reflect() declares the
// channels, execute() does the work.
#pragma once

#include "Falcor.h"
#include "Core/Pass/ComputePass.h"
#include "RenderGraph/RenderPass.h"

using namespace Falcor;

class __PASS_NAME__ : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(__PASS_NAME__, "__PASS_NAME__", "<one-line description shown in the Mogwai pass list>.");

    static ref<__PASS_NAME__> create(ref<Device> pDevice, const Properties& props)
    {
        return make_ref<__PASS_NAME__>(pDevice, props);
    }

    __PASS_NAME__(ref<Device> pDevice, const Properties& props);

    virtual void setProperties(const Properties& props) override;
    virtual Properties getProperties() const override;
    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;

private:
    void parseProperties(const Properties& props);

    ref<ComputePass> mpComputePass;

    // Parameters exposed in the UI and serialized through getProperties(), so a
    // Mogwai "Save Config" reproduces the exact experiment settings.
    uint32_t mSpp = 1u;
    bool mOptionsChanged = false;

    uint32_t mFrameIndex = 0u;
};
