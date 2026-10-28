# Shared Slang headers

目前这个目录**只放说明**，还没有被任何 pass 使用。

## 现状

`target_copy_shaders(target, output_dir)` 用目标自身的 `SOURCE_DIR` 推算输出路径，
所以 Falcor 没有现成机制把"树外共享的 `.slangh`"部署到 `<bin>/shaders/`。
在这个机制落地之前，每个 pass 的着色器请自包含（把需要的类型与常量直接写在自己的
`.slang` 文件里），这也是上游 `RenderPassTemplate` 的做法。

## 需要共享时的做法（尚未实现，留给第一个真正需要它的课题）

1. 在 `research/shared/CMakeLists.txt` 里定义一个部署函数：

   ```cmake
   function(eidolon_deploy_shared_shaders target)
       file(GLOB shared_headers CONFIGURE_DEPENDS
            ${CMAKE_CURRENT_SOURCE_DIR}/shaders/Eidolon/*.slangh)
       foreach(hdr ${shared_headers})
           get_filename_component(name ${hdr} NAME)
           set(dst ${FALCOR_SHADER_OUTPUT_DIRECTORY}/Eidolon/${name})
           add_custom_command(TARGET ${target} POST_BUILD
               COMMAND ${CMAKE_COMMAND} -E copy_if_different ${hdr} ${dst})
       endforeach()
   endfunction()
   ```

2. 在 pass 的 `CMakeLists.txt` 里调用它，并把共享头以 `#include "Eidolon/<Name>.slangh"`
   引入。

3. 先在 Slang 里验证 include 搜索路径确实包含 `<bin>/shaders`（用最小的 pass 试一次，
   确认 `F5` 热重载也能正确解析），再把这条规则写进本文档当成既定事实。

在做到以上步骤之前，不要凭空假设 include 路径可用——Slang 的 include 解析顺序
属于需要实测的行为，不是可以靠推测写下的约定。
