# 依赖版本记录

> 由 `tools/upgrade-falcor.ps1` 升级后手工更新本文件。它是"这轮实验用的到底是哪个框架版本"
> 的唯一答案——`.rdc` 的 manifest 里也会引用 `falcorVersion`。

## Falcor

| 项 | 值 |
|---|---|
| 上游 | <https://github.com/NVIDIAGameWorks/Falcor> |
| 锁定 ref | `9.0` |
| commit | `759aad033ff610fb0d82c74f7e0a508d0096d5f2` |
| 落地日期 | 2026-11-10 |
| 获取方式 | `git submodule`（`.gitmodules` 已入库） |
| 克隆方式 | `git clone --depth 1 --branch 9.0`，子模块同样 `--depth 1` |

commit 先由 `git ls-remote --tags ... refs/tags/9.0` 得到（2026-10-28），
实际检出后再用 `git -C vendor/falcor rev-parse HEAD` 复核：**一致**。
两边一致说明该 tag 未被移动，9.0 的源码就是这份。

## 状态

`vendor/falcor` 已落地并可构建。本地唯一的工作区改动是
`Source/RenderPasses/CMakeLists.txt` 末尾的 `eidolon overlay` 生成块
（由 `tools/sync-passes.ps1` 生成，`tools/clean-passes.ps1` 可还原）。

```powershell
git -C vendor/falcor status --short     # 期望：仅 M Source/RenderPasses/CMakeLists.txt
```

## 构建环境（实测）

| 项 | 值 |
|---|---|
| VS | Build Tools 2022，VCTools 工作负载 |
| Windows SDK | 10.0.19041.0（另有 26100.0）；预设钉 19041 |
| 预设 | `windows-vs2022`（VS 17 2022 生成器，`CMAKE_SYSTEM_VERSION=10.0.19041.0`） |
| 配置 | `RelWithDebInfo`，`FALCOR_ENABLE_USD=OFF` |
| RenderDoc | 1.46（winget 失败后走官方 MSI 安装） |
| packman 包缓存 | `D:\packman-repo`（约 3 GB，链接到 `vendor/falcor/external/packman`） |

## 其他

| 组件 | 版本 | 来源 |
|---|---|---|
| packman cmake | 3.24.1 | `vendor/falcor/dependencies.xml` |
| packman ninja | 1.10.2 | 同上 |
| packman python | 3.10.11 | 同上 |
| Slang | 2025.13.2 | 同上 |

这些由 Falcor 自己管理，**不要**替换成系统里更新的版本——预设已经把
`cmakeExecutable` / `CMAKE_MAKE_PROGRAM` 指向 packman 里的副本。
系统里的 CMake 4.4.5 只用于 `cmake --preset` 之外的杂活，不参与 Falcor 构建。
