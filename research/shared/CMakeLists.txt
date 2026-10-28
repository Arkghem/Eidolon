# Header-only helpers shared by the Eidolon research passes.
#
# Injected into Falcor's build tree by tools/sync-passes.ps1 *before* the pass
# libraries, so every pass can link against it:
#
#     target_link_libraries(<Pass> PRIVATE EidolonShared)
#
# Keep this target INTERFACE-only: a compiled static library would have to be
# built with the exact same MSVC toolset/config as each plugin, which buys
# nothing for a handful of small headers.

add_library(EidolonShared INTERFACE)

target_include_directories(EidolonShared INTERFACE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# Host-side helpers only. Slang headers are NOT distributed through this target
# yet: target_copy_shaders() derives output paths from a target's own source
# directory, so shared .slangh files need a dedicated copy rule. See
# shaders/Eidolon/README.md for the current status and intended mechanism.
