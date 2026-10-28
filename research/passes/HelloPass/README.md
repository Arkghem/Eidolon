# HelloPass

程序化 HDR 测试图案的渲染 pass，用途是**验证整条研究管线**，而不是做真正的渲染。

## 它验证了什么

| 环节 | 验证方式 |
|---|---|
| 注入清单 | `research/passes.txt` 里的 `HelloPass` 进入生成块 |
| 插件构建 | 产出 `<build>\bin\<Config>\plugins\HelloPass.dll` |
| 插件注册 | 名字出现在 `plugins\plugins.json` |
| 着色器部署 | `shaders\RenderPasses\HelloPass\HelloPass.cs.slang` 存在 |
| 运行时发现 | Mogwai 的 pass 列表里能选到 `HelloPass` |
| 图连通性 | `experiments\0001-hello-pass` 能把输出接到 ToneMapper |
| 抓帧 | RenderDoc 里能定位到该 compute dispatch |

## 参数

| 名称 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `frequency` | float | 4.0 | 同心波纹频率 |
| `speed` | float | 1.0 | 动画速度 |
| `showGrid` | bool | true | 叠加 16×16 网格 |

全部经 `getProperties()` 序列化，所以 Mogwai 的 `File → Save Config` 能生成可复现脚本。

## 为什么不是路径追踪

一个最小可用的 RT pass 需要 `ProgramDesc` + `RtBindingTable` + 命中组 +
`Scene` 类型适配 + 数百行 `.rt.slang`（见上游 `MinimalPathTracer`）。
把它当脚手架会让"环境是否正常"和"RT 代码是否正确"两个问题纠缠在一起。
写第一个真正的课题 pass 时，直接以上游 `MinimalPathTracer` 为模板抄结构，
把 `HelloPass` 留在这里当回归用的对照组。

## 相关实验

`experiments\0001-hello-pass\`

## API 依据（逐条核对自 Falcor 9.0 源码）

本机没有 MSVC，所以这份代码在首次构建前**没有编译过**。为了把首次构建的返工降到最低，
下面每条用法都对过真实头文件（2026-10-28，`@9.0`）：

| 用法 | 依据 |
|---|---|
| `#include "Core/Pass/ComputePass.h"` | `Falcor.h` 与 `RenderGraph/RenderPass.h` **都不包含**它；用 `ref<ComputePass>` 当成员必须自己 include |
| `ComputePass::create(device, path, "main")` | `ComputePass.h`：`create(ref<Device>, const std::filesystem::path&, const std::string& csEntry = "main", ...)` |
| `mpComputePass->execute(pRenderContext, w, h, 1)` | `execute(ComputeContext*, uint32_t, uint32_t, uint32_t = 1)`；`RenderContext : public ComputeContext`（`RenderContext.h`） |
| `var["CB"]["x"] = ...` / `var["gOutput"] = pOutput` | `ShaderVar::operator=`/`set()` 是模板分派；上游 `MinimalPathTracer` 同样写法 |
| `.format(...).bindFlags(UnorderedAccess \| ShaderResource)` | `RenderPassReflection::Field&` 提供这两个链式方法；`ResourceBindFlags` 支持 `\|`（上游 `SimplePostFX` 用三元或） |
| `dict[kRenderPassRefreshFlags] = flags \| RenderPassRefreshFlags::RenderOptionsChanged` | `RenderPassStandardFlags.h`：常量名 `"_refreshFlags"`，枚举含 `RenderOptionsChanged`，且有 `FALCOR_ENUM_CLASS_OPERATORS` |
| `uint32_t v = dict[key]` | `Dictionary::Value` 有模板 `operator T()`，`operator[]` 返回 `Value&` |
| `widget.var("f", mFloat, 0.1f, 32.f)` / `button` / `checkbox` / `tooltip` | `Gui.h`：`var(const char[], T&, T min, T max, ...)`、`bool button(const char[], bool)`、`checkbox(const char[], T&, bool)`、`tooltip(const std::string&, bool)` |

**升级 Falcor 后**：只需重核上表。表里第 1 行（include）和第 6 行（标志位名字）是最容易随版本漂移的两处。

