# 04 · 实验规范

## 1. 目录

```
experiments/<NNNN-slug>/
├─ README.md            # 问题 / 假设 / 方法 / 参数 / 观察 / 结论 / 后续（模板见 _template）
├─ graphs/*.py          # 渲染图脚本
├─ configs/*.json       # 数值参数（分辨率、场景、额外命令行参数）
├─ figures/             # 入库的图（对照图、曲线）——小、可引用
└─ results/             # gitignored：原始帧、csv、metrics.json
```

生成：

```powershell
pwsh -File tools\new-experiment.ps1 -Slug taa-history-rejection -Pass HelloPass
```

编号自动取当前最大值 +1，保证目录序 = 时间序。

## 2. 配置格式

`configs/*.json`（`tools/run-experiment.ps1` 读取；`-ConfigName` 可切换文件做参数扫描）：

| 字段 | 类型 | 说明 |
|---|---|---|
| `name` | string | 与目录名一致，便于报告引用 |
| `graph` | string | 相对实验目录的图脚本路径 |
| `scene` | string | `""` 表示不载入场景；相对路径按实验目录解析，否则交给 Falcor 的 media 搜索 |
| `width` / `height` | int | 分辨率，默认 1920×1080（8 GB 显存建议不要更高） |
| `headless` | bool | 是否无窗口运行 |
| `tag` | string | 产物目录名（`out/frames/<tag>`、`out/captures/<tag>`） |
| `extraArgs` | string[] | 直接透传给 Mogwai，如 `["--use-cache", "--debug-shaders"]` |
| `capture.mode` | `interactive` \| `cmd` | 默认抓帧模式 |
| `capture.frame` | int | `cmd` 模式下抓第几帧，`-1` 表示不指定 |

一次只改一个变量，才叫实验。多个变量一起改，结论归因不了。

## 3. 可复现性硬规则

1. **分辨率、spp、帧号写进 config**，不要用"上次好像是这样"。
2. **同机同驱动做对比**。换驱动/换构建配置的所有历史数字作废（manifest 里有版本号）。
3. **性能数字只认 RelWithDebInfo**，且关闭调试层。
4. **`results/` 不追求入库**，但要能被重新生成：复现命令必须写在 README 的「运行」一节。
5. **`.rdc` 不进 git**；要留证据就留 manifest + 关键截图 + 结论文字。

## 4. 度量

### 单帧对比

```powershell
python analysis/metrics.py --ref results\baseline\ref_0000.png `
                          --test results\candidate\out_0000.png `
                          --json results\metrics.json
```

输出 RMSE / PSNR / SSIM（装了 `flip-evaluator` 还有 FLIP）。
注意 SSIM 实现：有 `scikit-image` 就用它，否则用内置的均匀窗口实现——
后者够做回归跟踪，但**不要**当成论文里的标准 SSIM 引用。

### 多帧/批量对比

`results/` 摆成：

```
results/
├─ baseline/   ref_0000.png ref_0001.png ...
└─ candidate/  out_0000.png out_0001.png ...
```

```powershell
python analysis/compare.py --experiment 0007-taa-denoiser
```

按帧号配对，产出 `results/compare/compare.png`（基线/新/差值三联）+ `metrics.csv`。

### 汇总

```powershell
python analysis/run_report.py --out out/report.md
```

## 5. figures/ 与 results/ 的分工

| | 入库 | 内容 |
|---|---|---|
| `figures/` | 是 | 最终被引用的图：对照图、曲线、局部裁切。单图控制在几百 KB 内 |
| `results/` | 否 | 全部原始帧、csv、抓帧截图。可随时删了重跑 |

判据：**如果这张图是"结论的一部分"，放 `figures/`；如果只是"过程中的数据"，放 `results/`。**

## 6. 写作要求（README 模板已含）

最小要求，否则这个实验目录三个月后等于不存在：

- 第 1 节：一句**可证伪**的问题；
- 第 2 节：假设 + "如果成立应该观察到什么"；
- 第 6 节：至少一条 RenderDoc 观测证据 + 一个数字；
- 第 7 节：成立/不成立 + 意外发现。

## 7. 与 pass 的关系

- 一个 pass 可以被多个实验复用；实验不复制 pass 代码，只改参数/图。
- 实验若发现需要新的 pass 能力，先改 pass，再回填实验记录，并在 pass 的 `README.md`
  里加一行"相关实验"。
- 三个已选方向（实时 GI/路径追踪+降噪、超分/时域重建、材质体积 SDF）暂时都跑在
  `HelloPass` 的骨架上；接入真课题时按 `docs/01-architecture.md` 第 5 节的帧资源契约扩展，
  不要各自发明一套纹理命名。
