# 05 · 排错

> 按"症状 → 先查什么 → 怎么修"组织。每条都对应仓库里真实存在的东西，
> 不是泛泛的建议。

## 环境 / 安装

### `verify.ps1` 报 Visual Studio 2022 不通过
- 查：`C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe` 是否存在。
- 修：装 VS2022 BuildTools，且**必须**勾 "使用 C++ 的桌面开发"（VCTools 工作负载）。
  只装 IDE 不勾工作负载一样不行。

### CMake 报 `Windows SDK 10.0.19041.0 not found`
- 因：Falcor 的 `windows-base` 预设把 `CMAKE_SYSTEM_VERSION` 写死为 10.0.19041.0。
- 修（二选一）：
  1. 装组件 `Microsoft.VisualStudio.Component.Windows10SDK.19041`；
  2. `cmake --preset windows-vs2022 -DCMAKE_SYSTEM_VERSION=10.0.26100.0`（用已装版本）。

### `install-toolchain.ps1` 跑完什么都没装
- 查：`out\logs\p0-install.log`，以及 `%LOCALAPPDATA%\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir\WinGet-*.log`。
- 典型原因：网络。winget 会先去 msstore 源做关联查询，那个域名不通时会报
  `WinHttpSendRequest: 12002`。见 `docs/00-environment.md` 第 4 节的实测数据——
  这种网络下请走代理或离线安装包。

### UAC 弹窗没出现 / 提权后窗口一闪而过
- 脚本用 `Start-Process -Verb RunAs` 提权；被组策略禁止时会静默失败。
- 修：用管理员 PowerShell 手动跑
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\install-toolchain.ps1 -Elevated`。

## Falcor 源码 / 子模块

### `vendor/falcor` 是空的
- `git submodule update --init --recursive` 没跑，或网络断了。
- 修：`pwsh -File tools\bootstrap.ps1`（会自动加子模块并 checkout `9.0`）。
  离线环境请手动把 Falcor 9.0 的源码放到 `vendor\falcor`（保留 `.git` 最好）。

### `verify.ps1` 说 "falcor worktree 有覆盖层以外的改动"
- 说明有人在 `vendor/falcor` 里手改过东西。
- 修：`git -C vendor/falcor status --short` 看清楚；要么 `checkout --` 丢掉，
  要么写成 `patches/` 里的补丁并登记到 `patches/README.md`。

### `sync-passes.ps1` 报 "passes.txt lists X but ... does not exist"
- 清单与目录不一致（删了目录没删清单，或反之）。
- 修：让 `research/passes.txt` 与 `research/passes/` 一致；`_template` 不要写进清单。

### 仓库搬家之后 build 报路径错误
- 生成块里是绝对路径。
- 修：`pwsh -File tools\sync-passes.ps1` 再 `-Configure`。

## 构建

### `add_subdirectory` 报找不到目录 / 空 target
- 改了 `passes.txt` 或新增 pass 目录之后**没有重新 configure**。
- 修：`pwsh -File tools\build.ps1 -Configure`。

### 链接错误：找不到 `EidolonShared`
- `research/shared/CMakeLists.txt` 没被注入（生成块里应排在第一行）。
- 修：`tools\sync-passes.ps1` 后重新 configure；检查生成块里有没有
  `add_subdirectory(.../research/shared ...)`。

### CMake 找不到 `cl` / 生成器失败
- 走的是 `windows-ninja-msvc` 预设但没有 VS 环境变量。
- 修：用 `windows-vs2022`（默认，不需要 vcvars），或先
  `pwsh -File tools\dev-shell.ps1` 再构建。MinGW 的 gcc 不能用于 Falcor。

### 首次构建卡在 "Updating packman dependencies"
- 正常，在下载 2–4 GB。看 `vendor\falcor\tools\.packman` 是否在变大。
- 网络差就断开，等有通道时重跑 `tools\build.ps1`（packman 支持断点续传，会复用已下包）。

## 运行时

### Mogwai 里看不到自己的 pass
先跑 `pwsh -File tools\check-build.ps1`——它把下面 1–4 步自动化了。
按顺序查：
1. `<build>\bin\<Config>\plugins\<Name>.dll` 存在吗？
2. `<build>\bin\<Config>\plugins\plugins.json` 里有名字吗？
3. 改过 CMakeLists 后重新 configure 了吗？
4. DLL 与 Mogwai 是同一配置吗（Debug 的 DLL 进 Release 的 bin 会加载失败）？
5. `out\logs\mogwai-*.log` 里有没有 `Failed to load plugin` / `registerPlugin` 相关错误？

### 窗口黑屏
1. 图里有没有 `g.markOutput(...)`（没有输出就不会显示）；
2. `ToneMapper` 的输入是否为全 0（HDR 全 0 经 tonemap 还是黑）；
3. 日志里 Slang 编译错误（`F5` 之后尤其容易）；
4. 我们的 pass 是否真的被调度：抓一帧看 Event Browser。

### 着色器热重载（F5）后仍是旧行为
- 热重载只重编译着色器，不改 C++ 逻辑；如果改的是 `.cpp`，重启 Mogwai。
- 若 `F5` 报错但窗口继续跑旧着色器，看日志里的编译错误行号。

### `Mogwai exited with code N`
- `tools\run-mogwai.ps1` 会把日志末尾 15 行打出来；先看那几行。
- 常见：图脚本 Python 异常（`createPass` 名字拼错、端口名写错）、场景文件路径不存在。

## 抓帧

### RenderDoc 抓不到 / 抓出空帧
1. RenderDoc ≥ 1.35（Agility SDK）；
2. 构建用 RelWithDebInfo；
3. 工作目录必须是 bin 目录；
4. 显存是否爆了（降分辨率再试）；
5. 最后手段：`patches/` 记录去掉 `FALCOR_EXPORT_D3D12_AGILITY_SDK` 的临时补丁。

### `renderdoccmd capture` 报未知参数
- 不同版本 flag 不同。`tools\capture.ps1` 会探测 `--capture-frame` /
  `--wait-for-exit` / `--working-dir`；先看它打印的 `renderdoccmd: capture-frame=...`
  一行，再决定手写命令。

### `.rdc` 巨大
- 8 GB 显存下 1080p 复杂场景单帧 200–500 MB 正常。抓完就归档/删除，
  只保留 manifest 与结论。**永远不要提交 `.rdc`**。

## 度量

### `metrics.py` 报 Size mismatch
- 两次渲染分辨率不同。改 `configs/*.json` 的 `width/height` 后再渲染，别靠缩放凑。

### SSIM 和别人的数字对不上
- 用的是内置均匀窗口实现（没有 `scikit-image` 时）。它不是 MATLAB 参考实现，
  只可用于**同一套脚本内**的横向比较。

## 其他

### 用 PowerShell 看中文文档是乱码
- 因：Windows PowerShell 5.1 的 `Get-Content` 默认按系统 ANSI（GBK）解码，
  而仓库文件是 **UTF-8 无 BOM**（`.gitattributes` + `Write-Utf8NoBom` 保证的）。
- 修：`Get-Content foo.md -Encoding UTF8`，或用 PowerShell 7 / VS Code 打开。
  这不是文件损坏——`[System.IO.File]::ReadAllText()` 与 git 都能正常显示。

### JSON 配置/指标读不出来，或报告里标题是空的
- 因：文件被存成了 **UTF-8 with BOM**（Windows 记事本、PS 5.1 的
  `Set-Content -Encoding UTF8` 都会加），而严格的 `json.loads` / 首行匹配不认 BOM。
- 修：`analysis/` 下的脚本已统一用 `utf-8-sig` 读取；自己写的脚本也请如此。
  提交前可确认：`(Get-Content -Encoding Byte -TotalCount 3 file.json)` 不应是 `239 187 191`。

### 脚本里中文输出在某些终端变成方块
- 控制台代码页问题。`chcp 65001` 或换 Windows Terminal + pwsh 7。

## 网络

### 首次拉 Falcor / packman 极慢或中断
- 见 `docs/00-environment.md` 第 4 节实测。要点：拉取只需一次，之后构建离线可做。
  中断后直接重跑 `tools\build.ps1`，不要删 `vendor\falcor\external\packman`（已下的包会复用）。
