# patches/

默认情况下**我们从不修改 `vendor/falcor` 的源码**。升级路径是"移 submodule 指针"，不是"打补丁后合并"。

这个目录是逃生舱：只有当某个上游问题**必须**改 Falcor 源码才能推进研究时才使用。

## 使用规则

1. 只做最小改动，一条关注点一个补丁。
2. 文件名：`NNNN-short-slug.patch`，用 `git -C vendor/falcor diff > ..\patches\NNNN-....patch` 生成。
3. 每个补丁配一段说明，写进本文件的表格（见下），包含：为什么上游做不到、影响范围、何时可以删。
4. 升级 Falcor 前必须先 `git -C vendor/falcor checkout -- .` 清干净，再换 tag，再 `git apply` 重打；打不上就说明该补丁该退役了。
5. 补丁**存在**期间，`tools\verify.ps1` 会警告"子模块非干净状态"，这是预期的——但要确认 dirty 列表与下表一致。

## 已知会碰上游的候选（目前都没打）

| 场景 | 可能的补丁 | 备注 |
|---|---|---|
| RenderDoc 抓不到帧，且怀疑与 D3D12 Agility SDK 相关 | 临时去掉 `FALCOR_EXPORT_D3D12_AGILITY_SDK`（`Source/Mogwai/Mogwai.cpp`） | 只用于定位问题，不要长期保留 |
| 需要 `GBufferRT` 多输出一个通道 | 改上游 pass 的 `reflect()` | 优先考虑在自己的 pass 里重建，避免污染上游 |

## 当前补丁列表

（空）
