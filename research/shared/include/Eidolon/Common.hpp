// Shared host-side helpers for Eidolon research render passes.
//
// Everything here is deliberately small and dependency-free so that it can be
// included from any pass without dragging in extra compile time. Shader-side
// conventions live in research/shared/shaders/ (see the README there).
#pragma once

#include "Falcor.h"

namespace Eidolon
{

// -----------------------------------------------------------------------------
// Frame contract
//
// Passes that cooperate (a path tracer feeding a denoiser, an upscaler reading
// velocity, an accumulation pass) agree on a small set of names in the render
// graph's InternalDictionary instead of hard-coding strings at every call site.
//
//   color    RGBA16F   HDR radiance
//   depth    D32F      view-space / device depth, producer-defined but documented
//   motion   RG16F     screen-space motion vectors in pixels
//   frameIndex         uint32, monotonically increasing per graph execution
//   spp                uint32, samples accumulated so far
//
// Keep additions here rare and documented in docs/01-architecture.md.
// -----------------------------------------------------------------------------

constexpr const char* kFrameIndexKey = "eidolon/frameIndex";
constexpr const char* kSppKey = "eidolon/spp";

/// Read a uint32 from the internal dictionary, returning `fallback` when absent.
inline uint32_t getUint(const Dictionary& dict, const char* key, uint32_t fallback = 0u)
{
    return dict.keyExists(key) ? static_cast<uint32_t>(dict[key]) : fallback;
}

/// Read a float from the internal dictionary, returning `fallback` when absent.
inline float getFloat(const Dictionary& dict, const char* key, float fallback = 0.f)
{
    return dict.keyExists(key) ? static_cast<float>(dict[key]) : fallback;
}

inline uint32_t getFrameIndex(const Dictionary& dict)
{
    return getUint(dict, kFrameIndexKey, 0u);
}

inline void setFrameIndex(Dictionary& dict, uint32_t frameIndex)
{
    dict[kFrameIndexKey] = frameIndex;
}

// -----------------------------------------------------------------------------
// Small helpers used by most research passes.
// -----------------------------------------------------------------------------

/// Dispatch dimensions for a full-screen compute pass over `dims` pixels.
inline uint3 dispatchDims(const uint2& dims)
{
    return uint3(dims.x, dims.y, 1u);
}

/// True when the scene reports a change that invalidates per-frame history
/// (camera cut, topology change, ...). Passes that accumulate history must
/// reset on this.
inline bool sceneInvalidatesHistory(const ref<IScene>& pScene)
{
    if (!pScene) return true;
    const auto updates = pScene->getUpdates();
    return is_set(updates, IScene::UpdateFlags::RecompileNeeded) || is_set(updates, IScene::UpdateFlags::GeometryChanged) ||
        is_set(updates, IScene::UpdateFlags::SceneChanged);
}

} // namespace Eidolon
