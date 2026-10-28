# 依赖版本记录

> 由 `tools/upgrade-falcor.ps1` 升级后手工更新本文件。它是"这轮实验用的到底是哪个框架版本"
> 的唯一答案——`.rdc` 的 manifest 里也会引用 `falcorVersion`。

## Falcor

| 项 | 值 |
|---|---|
| 上游 | <https://github.com/NVIDIAGameWorks/Falcor> |
| 锁定 ref | `9.0` |
| commit | `759aad033ff610fb0d82c74f7e0a508d0096d5f2` |
| 锁定日期 | 2026-10-28 |
| 获取方式 | `git submodule`（本地尚未初始化，见下方状态） |

commit 由 `git ls-remote --tags https://github.com/NVIDIAGameWorks/Falcor refs/tags/9.0`
实测得到（2026-10-28），与 GitHub 上 `9.0` tag 一致。

## 状态

**`vendor/falcor` 尚未落地**：当次环境的网络无法完成克隆（见 `docs/00-environment.md`
第 4 节）。首次可联网时执行：

```powershell
pwsh -File tools\bootstrap.ps1
```

它会：加子模块 → checkout `9.0` → 递归子模块 → `setup.bat` 拉 packman → configure → 构建。
落地之后请把实际 `git -C vendor/falcor rev-parse HEAD` 的结果补到上表，
并确认与本文档记录的 commit 一致（不一致就说明 tag 被移动过，要在实验记录里注明）。

## 其他

| 组件 | 版本 | 来源 |
|---|---|---|
| packman cmake | 3.24.1 | `vendor/falcor/dependencies.xml` |
| packman ninja | 1.10.2 | 同上 |
| packman python | 3.10.11 | 同上 |
| Slang | 2025.13.2 | 同上 |

这些由 Falcor 自己管理，**不要**替换成系统里更新的版本——预设已经把
`cmakeExecutable` / `CMAKE_MAKE_PROGRAM` 指向 packman 里的副本。
