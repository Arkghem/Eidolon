# ADR 0001 — Falcor 以只读子模块形式引入

- **状态**：已采纳（2026-10-28）
- **上下文**：需要在 Falcor 之上做实时渲染研究，同时要能跟进上游新版本。
- **选项**：
  1. 直接把仓库变成 Falcor fork（研究代码加到 `Source/RenderPasses/`）；
  2. Falcor 作为 `vendor/falcor` 子模块，锁定 release tag，研究代码留在 `research/`；
  3. 完全不 vendor，用自建 CMake 复刻 `add_plugin()` 做 out-of-tree 插件。
- **决定**：选 2。
- **理由**：
  - 方案 1 让上游历史与本仓库历史纠缠，升级 = 合并冲突；研究代码与框架代码在同一命名空间里
    也很难说清"哪些是我们的"。
  - 方案 3 要复刻 include 目录、编译宏、输出目录、`plugins.json` 生成——上游一动就碎，
    且 Falcor 官方并不提供 install/export 目标。
  - 方案 2 保持一条硬边界（子模块只读），升级是移动指针；代价是需要一层注入机制，
    见 ADR 0002。
- **后果**：
  - 首次拉取需要网络（Falcor + 6 个子模块 + packman 依赖）。
  - 必须维护注入脚本，且升级前要先清覆盖层。
  - 研究代码不能直接改 Falcor 内部实现；真需要时走 `patches/`（有登记、有代价）。
