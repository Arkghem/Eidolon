# HelloPass -- the pipeline smoke test.
#
# Same shape as research/passes/_template/CMakeLists.txt; keep the two in sync
# when you change the build conventions.

add_plugin(HelloPass)

target_sources(HelloPass PRIVATE
    HelloPass.cpp
    HelloPass.h
    shaders/HelloPass.cs.slang
)

target_copy_shaders(HelloPass RenderPasses/HelloPass)

target_source_group(HelloPass "Eidolon/ResearchPasses")

target_link_libraries(HelloPass PRIVATE EidolonShared)
