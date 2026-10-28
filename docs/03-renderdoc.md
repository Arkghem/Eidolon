# 03 · RenderDoc 抓帧

## 1. 先接受一个事实

**Falcor 9.0 没有进程内 RenderDoc 集成**。`RenderContext`（以及整个 `Core/API`）
里没有任何 capture 接口——早期版本里的那套 API 已经不存在了。
所以抓帧永远是**进程外**行为：RenderDoc 通过它的 hook 注入 `Mogwai.exe`，在 Present 时截帧。

这不是缺陷，对研究来说反而是好事：抓帧不依赖引擎代码，跟任何 D3D12 程序一样处理。

## 2. 两种模式

```powershell
# A) 交互（推荐日常用）：拉起 qrenderdoc，并把参数给你打印好
pwsh -File tools\capture.ps1 -Experiment 0001-hello-pass `
     -Graph experiments\0001-hello-pass\graphs\hello_pass.py `
     -Scene media\Arcade\Arcade.pyscene

# B) 脚本化：renderdoccmd 直接抓，产物落 out\captures\
pwsh -File tools\capture.ps1 -Mode cmd -Experiment smoke `
     -Graph experiments\0001-hello-pass\graphs\hello_pass.py `
     -Frame 30 -TimeoutSeconds 90 -ExtraArgs '--headless'
```

**A 模式**打印的三个值不能错：

| 项 | 值 | 为什么 |
|---|---|---|
| Executable | `<build>\bin\<Config>\Mogwai.exe` | Falcor 从可执行文件目录找 `plugins/`、`shaders/`、`data/` |
| Working Dir | 同上（bin 目录） | 相对路径解析的根 |
| Arguments | `-s "<abs graph.py>" [-S "<scene>"]` | 图脚本必须绝对路径 |

进 qrenderdoc 后 `File → Launch Application`，按上面填，然后 `F12` 抓帧、
`File → Save Capture As` 存到 `out\captures\<experiment>\`。

**B 模式**注意：`--wait-for-exit` 语义要求程序自己退出，所以自动化抓帧要配
`--headless`（或无窗口运行）。`capture.ps1` 会先跑 `renderdoccmd capture --help`
探测 `--capture-frame` / `--wait-for-exit` / `--working-dir` 是否存在——不同版本 flag 有差异，
不要盲抄命令行。

## 3. 配置建议

- **用 RelWithDebInfo 抓帧**：有符号（能看 shader 调试、源码级上下文），性能接近 Release。
  Debug 构建的时序完全不代表真实性能，别拿它下结论。
- RenderDoc **≥ 1.35**：Falcor 走 Microsoft D3D12 Agility SDK，旧版 RenderDoc 可能
  认不出随程序分发的 `D3D12Core.dll`，表现为抓不到帧或直接崩。
- qrenderdoc 设置里打开 **Enable Global Hook**（这样 F12 在任何启动方式下都有效），
  关闭 **Allow VSync**（抓帧时序更干净）。
- 需要 Slang 源码级调试时，Mogwai 加 `--debug-shaders` 重新运行。

## 4. 每次抓帧都要有 manifest

`capture.ps1` 在 `.rdc` 旁边写 `manifest.json`：

```json
{
  "capturedAt": "2026-10-28T22:10:03.1234567+08:00",
  "experiment": "0001-hello-pass",
  "captureFile": "0001-hello-pass-20261028-221003.rdc",
  "frame": 30,
  "graph": "D:\\Eidolon\\experiments\\0001-hello-pass\\graphs\\hello_pass.py",
  "scene": null,
  "resolution": "1920 x 1080",
  "config": "RelWithDebInfo",
  "repoCommit": "abc1234",
  "falcorVersion": "9.0",
  "nvidiaDriver": "610.88",
  "renderdocVersion": "1.46",
  "appArgs": "-s ... --width 1920 --height 1080"
}
```

没有 manifest 的 `.rdc` 两周后就是废文件：你不再知道它对应哪个 commit、哪个参数。
**`.rdc` 永不入库**（单帧可达数百 MB），manifest 跟着它一起留在 `out\` 里。

## 5. 抓完看什么

以 `HelloPass` 为例（换成你的 pass 时对照着找）：

1. **Event Browser**：找到名为 `HelloPass.cs.slang` 的 compute dispatch。
   找不到 → 说明图没连上或 pass 没被调用，先解决"是否执行"，别急着看内容。
2. **Pipeline State**：确认 UAV 是 `RGBA16F`（我们声明的是 HDR 输出）。
3. **Constant Buffer**：`gFrequency`、`gSpeed`、`gFrameIndex` 的值应与 UI/配置一致。
   `gFrameIndex` 不涨 → 图没有逐帧执行。
4. **Texture Viewer**：看输出图。中心高光区域的数值应 > 1.0——这是"确实走了 HDR 而不
   是被 clamp 成 LDR"的证据。
5. **Mesh/API Inspector**：只在图形 pass 里有意义（我们这个 pass 是纯 compute）。

对时域类课题（TAA / 降噪 / 超分），重点看：历史缓冲的读写时序、
是否有同一个资源在同一帧里既读又写（会导致隐式 barrier 或竞态）、
motion vector 的采样点与控制台输出的位移是否一致。

## 6. 8 GB 显存的现实约束

- 抓帧本身会在显存里驻留整帧资源。1080p + 精简 pass 通常 2–4 GB；
- RTXDI/NRD/DLSS 同时开、4K 分辨率、复杂场景 → 很容易顶到上限，
  表现是 RenderDoc 崩溃或抓出空帧；
- 抓帧前先降分辨率（`-Width 1280 -Height 720`）确认能抓，再升回去定位问题。

## 7. 替代与补充工具

| 工具 | 什么时候用 |
|---|---|
| Falcor 内建 profiler（`P` 键） | 快速看各 pass 的 GPU 时间，比抓帧轻 |
| NVIDIA Nsight Graphics | 需要 GPU 计数器、warp 级 stall 分析时 |
| PIX | D3D12 专精，能看 barrier、资源生命周期；Agility SDK 场景需较新版本 |

抓帧记录（看到什么、结论是什么）写进对应 `experiments/<exp>/README.md` 的
「观察 → RenderDoc 抓帧看点」，而不是只口头说说。

## 8. 抓不到帧时的排查顺序

1. 能从 qrenderdoc 启动 `Mogwai.exe` 吗（不进图，只看能否 Present）？
2. RenderDoc 版本 ≥ 1.35？→ 升级
3. 是不是 Debug + 调试层叠加导致的异常？→ 换 RelWithDebInfo
4. 是不是 Agility SDK 冲突？→ 唯一的逃生舱：改 `Source/Mogwai/Mogwai.cpp` 去掉
   `FALCOR_EXPORT_D3D12_AGILITY_SDK`，但**这属于改上游**，必须记进 `patches/README.md`
5. 显存是否爆了？→ 降分辨率/换小场景
6. 看 `out\logs\mogwai-*.log` 末尾有没有 D3D12 设备丢失
