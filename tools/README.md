# tools/

PowerShell 自动化。全部兼容 Windows PowerShell 5.1 与 PowerShell 7（本机默认是 5.1）。

## 按使用顺序

| 脚本 | 什么时候跑 | 作用 |
|---|---|---|
| `preflight.ps1` | **装环境之前**、或下载卡住时 | 30 秒测三条关键链路的真实吞吐，换算出首次搭建的 ETA，把"能不能开始这 10 GB"变成可判断的结论 |
| `verify.ps1` | 任何时候怀疑环境有问题 | 只读体检：VS/SDK/驱动/盘/子模块/RenderDoc/覆盖层状态。HARD 问题退出码 1 |
| `install-toolchain.ps1` | 一次性 | 装 VS2022 BuildTools + SDK 19041 + RenderDoc（非管理员会自己走 UAC） |
| `bootstrap.ps1` | 一次性 | 串起：装工具链 → 体检 → 加子模块 → 拉 packman → configure → 构建 → 冒烟跑 |
| `sync-passes.ps1` | 改了 `research/passes.txt` / 新增 pass / 仓库搬家 | 生成注入块；`-Check` 只检查不写 |
| `build.ps1` | 每次构建 | `-Configure` 重新 configure；`-Target <Name>` 只编某个插件 |
| `check-build.ps1` | 构建后 | 断言插件契约：DLL / `plugins.json` / 着色器部署 |
| `run-mogwai.ps1` | 想直接跑一张图 | 设工作目录、`FALCOR_MEDIA_FOLDERS`、日志，收拢截图 |
| `run-experiment.ps1` | 日常跑实验 | 读 `experiments/<exp>/configs/*.json`，再调上面那个 |
| `capture.ps1` | 抓帧 | `interactive`（qrenderdoc）或 `cmd`（renderdoccmd）两种模式 + manifest |
| `new-pass.ps1` | 开新 pass | 从模板生成库并写入清单 |
| `new-experiment.ps1` | 开新实验 | 复制实验模板，自动编号 |
| `format.ps1` | 提交前 | 用 packman 的 clang-format 15 格式化 `research/`；`-Check` 只查 |
| `clean-passes.ps1` | 升级上游前 / 想回到干净状态 | 还原 `Source/RenderPasses/CMakeLists.txt` |
| `upgrade-falcor.ps1` | 换 Falcor 版本 | 强制执行正确顺序：清覆盖层 → fetch → checkout → 子模块 → 重注入 → 重建 |
| `dev-shell.ps1` | 用 Ninja 预设时 | 进 VS 开发环境（`windows-vs2022` 预设不需要） |
| `env.ps1` | 被上面这些 dot-source | 常量与助手函数（`Get-MogwaiExe`、`Write-Utf8NoBom` 等） |

## 两个容易踩的约定

1. **`env.ps1` 里的 `$script:` 变量会覆盖同名参数**。需要接受同名参数的脚本必须在
   dot-source 之前先存一份（`sync-passes.ps1`、`clean-passes.ps1` 里就是这么做的）。
2. **写文件一律 UTF-8 无 BOM**（`Write-Utf8NoBom`）。PS 5.1 的
   `Set-Content -Encoding UTF8` 会加 BOM，进而让 Python 的 `json.loads` 与首行匹配失败。

## 退出码

所有脚本遵循：`0` 成功（可带警告），非 `0` 失败。`bootstrap.ps1` 在第一个失败处停下并说明下一步。
