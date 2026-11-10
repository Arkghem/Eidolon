// Optional in-process RenderDoc capture trigger.
//
// Why this exists: Falcor 9.0 exposes no RenderDoc integration, and RenderDoc
// 1.46's `renderdoccmd capture` has no "capture frame N" flag. The only reliable
// way to script a capture is to trigger it from inside the process, through the
// public API in renderdoc_app.h (vendored in
// research/shared/third_party/renderdoc).
//
// Behaviour:
//   * If the process was not launched by RenderDoc, renderdoc.dll is absent and
//     every function here is a no-op (cheap, no exceptions).
//   * Set EIDOLON_RDOC_CAPTURE_FRAME=<n> to trigger a capture when frame n is
//     executed; set EIDOLON_RDOC_CAPTURE_TEMPLATE=<path> to control where the
//     .rdc lands (RenderDoc appends the frame number).
//
// Note: TriggerCapture() requests a capture of the *next* frame boundary, which
// is what makes this work with an app that is already rendering.
#pragma once

#if defined(_WIN32)

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <cstdint>
#include <cstdlib>
#include <string>

// Falcor's logger: all users of this header are render passes, so the dependency
// is free and it makes capture problems visible in the Mogwai log instead of
// failing silently.
#include "Utils/Logger.h"

#include "renderdoc_app.h"

namespace Eidolon
{
namespace detail
{
inline RENDERDOC_API_1_6_0*& renderDocApi()
{
    static RENDERDOC_API_1_6_0* api = nullptr;
    return api;
}

inline bool& renderDocTried()
{
    static bool tried = false;
    return tried;
}
} // namespace detail

/// Returns true when the process is under RenderDoc and its API is usable.
inline bool renderDocLoad()
{
    if (detail::renderDocTried()) return detail::renderDocApi() != nullptr;
    detail::renderDocTried() = true;

    // When launched by RenderDoc the DLL is already injected; loading by name
    // would find nothing outside that case.
    HMODULE module = GetModuleHandleA("renderdoc.dll");
    if (!module) return false;

    auto getApi = reinterpret_cast<pRENDERDOC_GetAPI>(GetProcAddress(module, "RENDERDOC_GetAPI"));
    if (!getApi) return false;

    RENDERDOC_API_1_6_0* api = nullptr;
    if (getApi(eRENDERDOC_API_Version_1_6_0, reinterpret_cast<void**>(&api)) != 1) return false;

    detail::renderDocApi() = api;
    return true;
}
inline void renderDocSetCaptureTemplate(const char* path)
{
    if (!renderDocLoad() || !path) return;
    detail::renderDocApi()->SetCaptureFilePathTemplate(path);
}

inline void renderDocTriggerCapture()
{
    if (!renderDocLoad()) return;
    detail::renderDocApi()->TriggerCapture();
}

/// Env-driven one-shot capture. Call once per frame with the frame index.
inline void maybeCaptureAtFrame(uint32_t frameIndex)
{
    static bool initialized = false;
    static int captureFrame = -1;
    static bool done = false;

    if (!initialized)
    {
        initialized = true;
        if (const char* frameEnv = std::getenv("EIDOLON_RDOC_CAPTURE_FRAME"))
        {
            captureFrame = std::atoi(frameEnv);
            logInfo("Eidolon: RenderDoc capture requested at frame {}", captureFrame);
        }
        if (const char* templateEnv = std::getenv("EIDOLON_RDOC_CAPTURE_TEMPLATE"))
            renderDocSetCaptureTemplate(templateEnv);
    }

    if (done || captureFrame < 0) return;
    if (static_cast<int>(frameIndex) != captureFrame) return;

    done = true;
    if (!renderDocLoad())
    {
        logWarning("Eidolon: capture frame {} reached, but renderdoc.dll is not loaded (not launched under RenderDoc).", frameIndex);
        return;
    }
    renderDocTriggerCapture();
    logInfo("Eidolon: triggered RenderDoc capture at frame {}", frameIndex);
}

} // namespace Eidolon

#endif // _WIN32
