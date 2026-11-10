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

## 6. 观察（已实测）

### 视觉

960×540 下三帧落盘（第 5/10/20 帧），图案与设计一致：同心波纹 + 16×16 网格 +
中心过曝高光（HDR 值 > 1，经 ToneMapper 后仍明显更亮）。图案逐帧变化。

命令：

```powershell
pwsh -File tools\run-mogwai.ps1 -Graph experiments\0001-hello-pass\graphs\hello_pass.py `
     -Headless -CaptureDir out\frames\0001-hello-pass -Width 960 -Height 540 -TimeoutSeconds 20
```

### RenderDoc 抓帧

```powershell
pwsh -File tools\capture.ps1 -Experiment 0001-hello-pass `
     -Graph experiments\0001-hello-pass\graphs\hello_pass.py `
     -Mode cmd -Frame 10 -TimeoutSeconds 30 -Width 960 -Height 540
```

产出 20.37 MB `.rdc` + `manifest.json`；`renderdoccmd thumb --out=<png> <rdc>` 能回放出画面
（缩略图里能看到 Mogwai UI、Graph 面板列出 `HelloPass` / `ToneMapper.dst`，右上角
144.8 FPS ≈ 6.9 ms/帧）。抓的是第 11 帧——`TriggerCapture()` 在下一个 Present 生效。

### 数值

`analysis\metrics.py` 对此实验无意义（无参考图）；跳过。

## 7. 结论（实测记录）

这一轮从"空白仓库"走到"能抓帧"，中间真实踩到的坑按出现顺序：

| # | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | `configure` 报 SDK 找不到 | 预设钉 `CMAKE_SYSTEM_VERSION=10.0.19041.0`，机器只有 26100 | 装上 19041 SDK 组件（`Microsoft.VisualStudio.Component.Windows10SDK.19041`） |
| 2 | winget 装 RenderDoc 卡死 | winget 的 msstore 关联查询超时，且提权进程无法从普通 shell 杀掉 | 给 `Invoke-Winget` 加 `WaitForExit(timeout)`；失败退回官方 MSI（**实际就是 MSI 装成功的**） |
| 3 | 着色器运行期找不到 | 我把 `.slang` 放在 `pass/shaders/` 子目录，`target_copy_shaders` 会保留相对路径，实际部署成 `RenderPasses/HelloPass/shaders/...` | 把着色器移到 pass 根目录（上游惯例），部署路径 = 代码里的 `"RenderPasses/HelloPass/HelloPass.cs.slang"` |
| 4 | `Failed to create device`（指定/任意 GPU 都失败） | **Windows 开发者模式未开**：gfx 带 D3D12 实验特性建设备，`D3D12EnableExperimentalFeatures` 失败后建设备也失败 | 开启开发者模式（`AllowDevelopmentWithoutDevLicense=1`）后设备创建成功：`NVIDIA GeForce RTX 5060 / D3D12 / SM6.8` |
| 5 | headless 下 `TriggerCapture()` 无产出 | RenderDoc 在 **Present** 处结束一帧；headless 没有 Present | 抓帧改用窗口模式（`capture.ps1` 现在会对此警告） |

另外两个"工具自身的 bug"也是在这次实跑中暴露并修掉的：
`check-build.ps1` 用 `Get-ChildItem -Include` 没加 `-Recurse` 导致误报；
`build.ps1` 用系统 CMake 4.4.5 驱动 3.24.1 生成的构建树会缓存不匹配（已改为优先用 packman 的 CMake）。

## 8. 后续

- 换掉 `HelloPass`，按 `MinimalPathTracer` 的结构写第一个 RT pass
- 接入 `TAA` / `AccumulatePass` 观察时域通道契约
- 把"抓第 N 帧"的钩子抽到更多 pass（现在只有 `HelloPass` 调用）
