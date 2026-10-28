# pass 模板

`tools\new-pass.ps1 <Name>` 会把这个目录复制成 `research\passes\<Name>\`，并对**文件名和内容**
统一替换占位符 `__PASS_NAME__`，最后把 `<Name>` 追加进 `research\passes.txt`。

## 生成之后要做的三件事

1. 改描述：`<Name>.h` 里 `FALCOR_PLUGIN_CLASS` 的第三个参数是 Mogwai pass 列表里显示的
   一句话说明；类注释写清这个 pass 在研究里扮演什么角色。
2. 定接口：`reflect()` 里声明输入输出。输出要写清 `format()` 与 `bindFlags()`——
   compute 写纹理必须带 `UnorderedAccess`，否则 `getTexture()` 拿到的资源不能当 UAV 绑定。
3. 参数序列化：任何影响画面的参数都要同时出现在 `renderUI()`（手动调）
   与 `getProperties()`（`Save Config` 复现）里，两者缺一不可。

## 模板刻意做成的东西

| 选择 | 原因 |
|---|---|
| compute pass 而非 RT pass | 最小 RT pass 需要 `ProgramDesc` + `RtBindingTable` + 命中组 + 数百行 `.rt.slang`（见上游 `MinimalPathTracer`）。脚手架越薄，"环境坏了"和"我的 RT 写错了"越不容易混在一起 |
| 单个自包含 `.slang` | 共享 `.slangh` 目前没有自动部署机制，见 `research/shared/shaders/Eidolon/README.md` |
| `mOptionsChanged` + `kRenderPassRefreshFlags` | 让下游时域 pass 知道该丢历史；这是接 TAA/降噪时最先用到的一行 |
| `Eidolon/Common.hpp` | 帧契约（`frameIndex`/`spp`）的键名集中管理，别各自发明字符串 |

## 不要做的事

- 不要在 pass 里缓存 render graph 分配的纹理（会破坏分配器与历史追踪）。
- 不要绕过 `target_copy_shaders` 自己拷着色器——路径约定会被打乱。
- 不要把实验参数写死在 `.slang` 里：改成 `CB` 成员，从 UI/`Properties` 进来，
  否则没法做参数扫描，也没法复现。
