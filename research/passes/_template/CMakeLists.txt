# Template for a new Eidolon research render-pass library.
#
# tools/new-pass.ps1 copies this directory to research/passes/<Name>/, replaces
# every occurrence of __PASS_NAME__ (including file names), and appends <Name>
# to research/passes.txt.
#
# Conventions inherited from Falcor's own passes:
#   * the library name == directory name == CMake target == plugin DLL name,
#   * shaders are deployed under shaders/RenderPasses/<Name>/ and loaded with
#     "RenderPasses/<Name>/<file>.slang",
#   * target_copy_shaders() must be called *after* target_sources().

add_plugin(__PASS_NAME__)

target_sources(__PASS_NAME__ PRIVATE
    __PASS_NAME__.cpp
    __PASS_NAME__.h
    shaders/__PASS_NAME__.cs.slang
)

target_copy_shaders(__PASS_NAME__ RenderPasses/__PASS_NAME__)

target_source_group(__PASS_NAME__ "Eidolon/ResearchPasses")

# Header-only helpers shared between passes (research/shared).
target_link_libraries(__PASS_NAME__ PRIVATE EidolonShared)
