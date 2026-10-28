# ADR 0002 — 用"生成式注入"把研究 pass 接进 Falcor 构建

- **状态**：已采纳（2026-10-28）
- **上下文**：Falcor 必须是顶层 CMake 工程（内部大量使用 `${CMAKE_SOURCE_DIR}`），
  而它发现插件库的唯一入口是 `Source/RenderPasses/CMakeLists.txt` 里的
  `add_subdirectory()`。我们的 pass 又不该住在子模块里。
- **选项**：
  1. 手工编辑该文件（每次升级都冲突，且状态不可复现）；
  2. 用 junction/symlink 把 `research/passes` 挂进 Falcor 树（Windows 需要额外权限，
     仍然要改那行 CMake）；
  3. 脚本从 `git show HEAD:` 取纯净内容，追加带标记的生成块，写回。
- **决定**：选 3，实现在 `tools/sync-passes.ps1`，撤销在 `tools/clean-passes.ps1`。
- **理由**：
  - 上游自带的 `tools/make_new_render_pass.py` 干的也是"重写这个文件"，说明它是可生成的。
  - 用 `git show HEAD:` 打底，保证结果只取决于"上游 commit + 我们的清单"，
    与工作区历史无关，因此幂等、可审计、可一键还原。
  - 绝对源路径 + 显式二进制目录是 CMake 合法用法，省掉链接与权限问题。
- **后果**：
  - `vendor/falcor` 工作区会常驻一个"已修改"文件（预期状态，`verify.ps1` 认可它）。
  - 仓库搬家必须重跑注入。
  - 升级顺序被强制为：清覆盖层 → checkout → 重新注入 → reconfigure。
