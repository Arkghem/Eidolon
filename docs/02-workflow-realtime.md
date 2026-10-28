# 02 · 实时迭代工作流

> 目标：从"改一行着色器"到"在 RenderDoc 里看到这一行的效果"，路径固定、步骤可数。

## 1. 三种改动，三条路径

| 改了什么 | 需要重建？ | 怎么生效 | 典型耗时 |
|---|---|---|---|
| `.slang` 着色器 | 否 | Mogwai 里按 **F5** 热重载 | 1–3 s |
| `.py` 渲染图 | 否 | 重新 `Ctrl+O` 载入脚本，或控制台重跑 | 1 s |
| `.cpp/.h`、CMakeLists | 是（只编插件） | 重建 → **重启 Mogwai** | 5–30 s |

关键事实：**插件 DLL 只在进程启动时加载**，改了 C++ 就必须重启 Mogwai。
Falcor 不提供运行期卸载/重载插件。

## 2. 日常循环

```powershell
# 0) 一次性：确认环境
pwsh -File tools\verify.ps1

# 1) 首次或改了 CMakeLists / passes.txt
pwsh -File tools\sync-passes.ps1
pwsh -File tools\build.ps1 -Configure

# 2) 日常：只重编我们的插件
pwsh -File tools\build.ps1 -Target HelloPass

# 3) 跑图（窗口模式，方便按 F5 / F12）
pwsh -File tools\run-experiment.ps1 -Experiment 0001-hello-pass

# 4) 抓帧
pwsh -File tools\run-experiment.ps1 -Experiment 0001-hello-pass -Capture
```

`run-experiment.ps1` 读 `experiments/<exp>/configs/default.json`，你不用手写命令行。
临时改分辨率：

```powershell
pwsh -File tools\run-mogwai.ps1 -Graph experiments\0001-hello-pass\graphs\hello_pass.py `
     -Width 1280 -Height 720 -Tag scratch
```

## 3. Mogwai 里常用的键

| 键 | 作用 |
|---|---|
| `F5` | 重载着色器（改 `.slang` 之后按它） |
| `F12` | 截图（落运行目录，`run-mogwai.ps1` 会收集到 `out/frames/<tag>/`） |
| `P` | 开/关 profiler（GPU 时间，先看这个再看 RenderDoc） |
| `F2` | 隐藏 GUI（截图/录屏用） |
| `Ctrl+O` | 载入渲染图脚本 |
| `Ctrl+Shift+O` | 载入场景 |
| `` ` `` | 脚本控制台（可以直接改图、调参数） |
| `Ctrl+空格` | 暂停渲染（配合 F5 观察单帧变化） |

场景：`media\Arcade\Arcade.pyscene` 是 packman 自带的最小场景，用来做冒烟测试。

## 4. 调试 C++

1. `pwsh -File tools\build.ps1` 已经产出自带符号的 `RelWithDebInfo`；
2. 用 VS 打开 `vendor\falcor\build\windows-vs2022\Falcor.sln`，或直接
   **附加到进程**：VS → 调试 → 附加到进程 → `Mogwai.exe`；
3. 在 `research/passes/<Name>/*.cpp` 里下断点；
4. 需要 D3D12 调试层时，用 Debug 配置跑（慢、且**不要**拿它做性能结论）。

## 5. 一次典型的"改动 → 结论"闭环

1. 在实验目录写清问题与假设（`experiments/<exp>/README.md`）；
2. 改 pass 或着色器；
3. `build.ps1 -Target <Pass>`（仅 C++ 改动时）；
4. `run-experiment.ps1 -Experiment <exp> -Capture`，在 RenderDoc 里确认改动的载体真的执行了；
5. 把关键帧/数值记进 `results/`，用 `analysis/metrics.py` 出数；
6. 结论写回 README 的「观察 / 结论」两节。

第 4 步是分水岭：**没在抓帧里确认过的改动，不算跑过**。很多"没效果"其实是
新代码没进图、或者被上游 pass 覆盖了。

## 6. 常见卡点速查

| 现象 | 先看哪里 |
|---|---|
| 窗口全黑 | `out/logs/mogwai-*.log`；图里输出是否 `markOutput` |
| pass 列表里没有自己的 pass | `plugins/plugins.json` 是否含名字；是否重新 configure |
| 改了没反应 | 是不是只改了 C++（要重启）／只改了着色器（要 F5） |
| `F5` 报着色器错误 | 日志里有 Slang 编译错误的行号；注意路径是 `RenderPasses/<Name>/...` |
| 构建报找不到 SDK | 见 `docs/00-environment.md` 第 2 节 |
