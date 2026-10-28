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
