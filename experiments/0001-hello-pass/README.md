# 0001-hello-pass — 验证研究管线端到端可用

## 0. 这轮实验的性质

**这不是一个渲染技术实验**，而是一次环境/管线验收：确认
`research/passes/HelloPass` 能被构建成插件、被 Mogwai 发现、被渲染图消费、
被 RenderDoc 抓帧。它跑通之后，后面任何真正的研究实验都只需要换 pass。

## 1. 问题

从"干净仓库"到"能在 RenderDoc 里看到自己写的 pass 的 dispatch"，中间有没有断点？

## 2. 假设

如果注入清单、CMake 插件目标、着色器部署、`plugins.json`、运行时加载这五环都正确，
那么 `HelloPass` 的 HDR 图案会出现在 Mogwai 里，且能抓到一帧 `.rdc`。

## 3. 方法

- 改动点：无（使用模板生成的 `HelloPass`）
- 对照基线：Mogwai 自带的 `ToneMapper` 默认参数
- 采集设置：1920×1080，窗口模式（抓帧需要 Present），单帧

## 4. 参数

见 `configs/default.json`；`HelloPass` 自身参数：`frequency=4.0`、`speed=1.0`、`showGrid=true`。

## 5. 运行

```powershell
# 1) 环境与构建
pwsh -File tools\verify.ps1
pwsh -File tools\build.ps1 -Configure            # 首次：约 40-90 分钟
pwsh -File tools\build.ps1 -Target HelloPass     # 之后只重编插件

# 2) 构建产物自检
pwsh -File tools\check-build.ps1
#    它逐项验证：Mogwai.exe / Falcor.dll / plugins\HelloPass.dll /
#    plugins.json 里是否有 HelloPass / shaders\RenderPasses\HelloPass\ 是否有着色器

# 3) 跑图
pwsh -File tools\run-experiment.ps1 -Experiment 0001-hello-pass

# 4) 抓帧
pwsh -File tools\run-experiment.ps1 -Experiment 0001-hello-pass -Capture
```

## 6. 观察

### 视觉

Mogwai 窗口里应看到：同心波纹 + 网格 + 中心过曝的高光（HDR 值 > 1，
所以能顺带验证 ToneMapper 在工作）。图案逐帧变化 → 图在持续推进。

### RenderDoc 抓帧看点

`out\captures\0001-hello-pass\*.rdc`：

1. Event Browser 里应有一个 compute dispatch，着色器名为 `HelloPass.cs.slang`
2. 该 dispatch 的 UAV 是 `RGBA16F` 的 `color` 输出
3. 常量缓冲 `CB` 里能看到 `gFrequency=4.0`、`gFrameIndex` 递增
4. 若高光区域数值 > 1.0，说明确实走了 HDR 路径而非 LDR

### 数值

`analysis\metrics.py` 目前对此实验无意义（无参考图）；跳过。

## 7. 结论

（构建/抓帧完成后填写：哪一步曾经失败、怎么修的——这是最值钱的部分）

## 8. 后续

- 换掉 `HelloPass`，按 `MinimalPathTracer` 的结构写第一个 RT pass
- 接入 `TAA` / `AccumulatePass` 观察时域通道契约
