// Shared host-side helpers for Eidolon research render passes.
//
// Everything here is deliberately small and dependency-free so it can be
// included from any pass without dragging in extra compile time.
//
// NOTE ON STYLE: this header is included from *plugin* code, not from inside
// Falcor, so names from the framework must be qualified (Falcor::...). Do not
// rely on a `using namespace Falcor;` from the including translation unit.
#pragma once

#include <cstdint>

#include "Falcor.h"

namespace Eidolon
{

// -----------------------------------------------------------------------------
// Frame contract
//
// Passes that cooperate (a path tracer feeding a denoiser, an upscaler reading
// motion vectors, an accumulation pass) agree on a small set of names in the
// render graph's internal dictionary instead of hard-coding strings at every
// call site. Keep this list short and document every addition in
// docs/01-architecture.md.
//
//   color    RGBA16F   HDR radiance
//   depth    D32F      depth (the producer documents whether it is device or
//                      linear view depth)
//   motion   RG16F     screen-space motion vectors, in pixels
//   frameIndex         uint32, monotonically increasing per graph execution
//   spp                uint32, samples accumulated per pixel so far
// -----------------------------------------------------------------------------

constexpr const char* kFrameIndexKey = "eidolon/frameIndex";
constexpr const char* kSppKey = "eidolon/spp";

/// Read a uint32 from the internal dictionary, returning `fallback` when absent.
inline uint32_t getUint(Falcor::Dictionary& dict, const char* key, uint32_t fallback = 0u)
{
    if (!dict.keyExists(key)) return fallback;
    uint32_t value = dict[key];
    return value;
}

/// Read a float from the internal dictionary, returning `fallback` when absent.
inline float getFloat(Falcor::Dictionary& dict, const char* key, float fallback = 0.f)
{
    if (!dict.keyExists(key)) return fallback;
    float value = dict[key];
    return value;
}

inline uint32_t getFrameIndex(Falcor::Dictionary& dict)
{
    return getUint(dict, kFrameIndexKey, 0u);
}

inline void setFrameIndex(Falcor::Dictionary& dict, uint32_t frameIndex)
{
    dict[kFrameIndexKey] = frameIndex;
}

inline void setSpp(Falcor::Dictionary& dict, uint32_t spp)
{
    dict[kSppKey] = spp;
}

} // namespace Eidolon
