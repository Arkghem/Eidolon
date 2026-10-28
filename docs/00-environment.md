# 00 · 环境

> 这份文档记录的是**这台机器**的事实与验收命令，不是通用教程。
> 环境变了就更新这里，别让文档和现实脱节。

## 1. 版本矩阵（已验证）

| 组件 | 版本 / 路径 | 状态 |
|---|---|---|
| OS | Windows 11 26200（64 位） | ✔ Falcor 要求 Win10 20H2+ |
| GPU | NVIDIA GeForce RTX 5060，8 GB 显存 | ✔ DXR；⚠ 显存偏小 |
| 驱动 | 610.88 | ✔ Falcor 要求 ≥ 535 |
| CPU / RAM | 16 逻辑核 / 32 GB | ✔ |
| 仓库盘 | `D:\Eidolon`，184 GB 空闲 | ✔ |
| git | 2.56.0.windows.2 + git-lfs 3.8.0 | ✔ |
| Visual Studio 2022 | **未安装** | ✘ 阻断构建 |
| Windows SDK 10.0.19041 | **未安装** | ✘ 预设强制该版本 |
| RenderDoc | **未安装** | ✘ 抓帧所需 |
| 系统 Python | 3.15.1 | 仅用于 `analysis/`；Falcor 用 packman 的 3.10.11 |

Falcor 的实际工具链**不依赖**系统里那些 CMake/Ninja：`windows-*` 预设把
`cmakeExecutable` 指向 `tools/.packman/cmake`（3.24.1）、`CMAKE_MAKE_PROGRAM` 指向
`tools/.packman/ninja`（1.10.2），构建时由 packman 提供。所以系统里装着 CMake 4.4.5、
MinGW 的 ninja 1.13.2 都不影响——**但 MinGW 的 gcc/g++ 不能用来构建 Falcor**。

## 2. 为什么必须是 VS2022 + SDK 19041

- Falcor 在 Windows 上只支持 MSVC + D3D12（Linux 才走 GCC/Clang + Vulkan）。
- `CMakePresets.json` 的 `windows-base` 写死了 `CMAKE_SYSTEM_VERSION=10.0.19041.0`。
  只装 VS2022 默认带来的 22621/26100 SDK 时，CMake 会报找不到 19041。
  两条路任选：
  1. 装组件 `Microsoft.VisualStudio.Component.Windows10SDK.19041`（推荐）；
  2. 配置时覆盖：`cmake --preset windows-vs2022 -DCMAKE_SYSTEM_VERSION=10.0.26100.0`。
- 另外 `--toolset host=x86`：32 位宿主工具链，正常安装自带。

## 3. 安装

```powershell
# 推荐：用仓库脚本（幂等，非管理员会自己走 UAC 提权）
pwsh -File tools\install-toolchain.ps1
```

等价的手工命令（winget 源可用时）：

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools -e `
  --accept-package-agreements --accept-source-agreements `
  --override "--quiet --wait --norestart --nocache `
              --add Microsoft.VisualStudio.Workload.VCTools `
              --add Microsoft.VisualStudio.Component.Windows10SDK.19041 `
              --includeRecommended"

winget install --id BaldurKarlsson.RenderDoc -e `
  --accept-package-agreements --accept-source-agreements
```

手动装的话，官方入口：

- VS Build Tools：<https://aka.ms/vs/17/release/vs_buildtools.exe>（工作负载选
  "使用 C++ 的桌面开发"，单个组件勾 "Windows 10 SDK (10.0.19041.0)"）
- RenderDoc：<https://renderdoc.org/>（要 **1.35+**，Falcor 用 D3D12 Agility SDK）

## 4. 网络（2026-10-28 实测，重要）

这台机器当前对国际链路极慢且不稳定：

| 目标 | 实测 |
|---|---|
| `github.com` git 传输 | 起初可 `ls-remote`（5 s），随后直接连不上（`Failed to connect ... after 22 s`） |
| `codeload.github.com` tarball | ~9 KB/s（150 s 下 1.3 MB） |
| `aka.ms`（VS 引导器） | 20 s 内 0 字节 |
| `cdn.jsdelivr.net` | 单文件可用（~10 s 一个 13 KB 文件） |
| `mirrors.tuna.tsinghua.edu.cn` | ~580 KB/s |

**含义**：VS BuildTools（7–10 GB）+ packman 依赖（2–5 GB）在这个链路上不现实。
首次拉取 Falcor 与依赖时，请使用你能连通的通道（代理 / VPN / 公司镜像 / 离线包），
拉完一次之后本地构建不再需要网络。

动手前先跑一次预检，别靠猜：

```powershell
pwsh -File tools\preflight.ps1          # 30 秒，给出三条链路实测速率 + ETA 结论
pwsh -File tools\preflight.ps1 -Strict  # ETA 超阈值时退出码 1（适合写进检查脚本）
```

### 镜像尝试结果（2026-10-28，省下次的时间）

| 通道 | 结果 |
|---|---|
| `gitee.com/mirrors/Falcor` | ❌ 是 Netflix 的 **falcor.js** 前端库，同名不同物 |
| `gitee.com/mirrors_NVIDIA/Falcor` | ❌ 空壳（只有 README.md） |
| `ghfast.top` / `bgithub` / `kkgithub` / `gitclone.com` | ❌ 连接超时或 0 字节 |
| `ghproxy.net` | ❌ 0.6 KB/s，等于不可用 |
| `cdn.jsdelivr.net/gh/NVIDIAGameWorks/Falcor@9.0/<path>` | ✅ **单文件可用**（每个小文件约 1–10 s），可用来核对头文件/API，但不能用来下载整仓 |

结论：需要整仓时没有可用捷径，只能等一条能连 GitHub 的链路。核对单个源文件时
jsDelivr 足够（本次就是靠它核实了 `ComputePass.h`、`RenderPass.h`、`Dictionary.h`、
`Gui.h`、`ShaderVar.h`、`RenderPassStandardFlags.h` 等）。

`tools/install-toolchain.ps1` 在这种网络下会失败并留下
`out/logs/p0-install.log`——去那里看它卡在哪一步，不要反复重试。

## 5. 验收

```powershell
pwsh -File tools\verify.ps1
```

它把问题分成两类：

- **HARD**（退出码 1）：VS2022/VCTools、Windows SDK 19041、驱动 ≥535、`vendor/falcor`。
  不修好无法构建。
- **SOFT**（退出码 0，有警告）：RenderDoc 缺失、packman 未拉取、Mogwai 未构建、
  覆盖层未同步、显存 <10 GB 等。

预期输出形态（修好之后）：

```
  [OK  ] Visual Studio 2022    17.14.x (C:\Program Files\Microsoft Visual Studio\2022\BuildTools)
  [OK  ] MSVC toolset          14.4x
  [OK  ] Windows SDK 19041     10.0.19041.0
  [OK  ] NVIDIA GPU            NVIDIA GeForce RTX 5060 / driver 610.88 / 8151 MiB
  [WARN] VRAM                  8151 MiB - keep experiments at 1080p...
  [OK  ] vendor/falcor         checked out at 9.0
  [OK  ] pass overlay          up to date with research/passes.txt
  [OK  ] RenderDoc             C:\Program Files\RenderDoc\qrenderdoc.exe (1.46)
  [OK  ] Mogwai.exe            ...\bin\RelWithDebInfo\Mogwai.exe
```

## 6. Python

- **Falcor 自己的 Python 扩展**用的是 packman 提供的 3.10.11（与二进制 ABI 绑定）。
  想用 `import falcor` 就按官方做法用 Python 3.10 环境（`FALCOR_USE_SYSTEM_PYTHON=OFF`
  是默认值，别改）。Agility SDK 的 Python 扩展还要求开启 Windows「开发者模式」。
- **本仓库的 `analysis/`** 是独立工具，与 Falcor 无关，建议建独立 venv：

  ```powershell
  python -m venv .venv
  .\.venv\Scripts\Activate.ps1
  pip install -r analysis\requirements.txt
  ```

  系统 Python 3.15 太新，个别科学计算轮子可能还没发布；装不上就换 3.12。

## 7. 磁盘预算

| 项 | 大约 |
|---|---|
| Falcor 源码 + 6 个子模块 | 0.3 GB |
| packman 依赖（关掉 USD） | 2–4 GB |
| 构建产物（RelWithDebInfo） | 5–12 GB |
| `out\captures\*.rdc` | 每帧 50–500 MB，随场景/显存涨 |

`FALCOR_ENABLE_USD=OFF` 由 `tools/build.ps1` 默认传入，能省 1–2 GB 与可观编译时间。
