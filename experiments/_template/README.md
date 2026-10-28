# <NNNN-slug> — <一句话说明这轮实验在验证什么>

> 模板。`tools\new-experiment.ps1 <slug>` 会复制本目录并替换占位符。
> 每个实验目录自包含：图、配置、观测记录、图产出。

## 1. 问题

要回答的具体问题。一句话，可证伪。反例：「看看效果好不好」不是问题。

## 2. 假设

预期结论 + 理由。写清"如果假设成立，应该观察到什么"。

## 3. 方法

- 改动点（哪个 pass / 哪个着色器 / 哪些参数）
- 对照基线（`baseline/` 里的哪一版，或上游哪个 pass）
- 采集设置（分辨率、spp、帧数、是否固定 seed）

## 4. 参数

见 `configs/default.json`。关键差异与默认值的对照写在这里：

| 参数 | 基线 | 本实验 | 理由 |
|---|---|---|---|
| | | | |

## 5. 运行

```powershell
# 直接跑
pwsh -File tools\run-experiment.ps1 -Experiment <NNNN-slug>

# 跑 + 抓帧
pwsh -File tools\run-experiment.ps1 -Experiment <NNNN-slug> -Capture
```

## 6. 观察

### 视觉

（贴 `figures/` 里的图，或描述在哪里看）

### RenderDoc 抓帧看点

`out\captures\<NNNN-slug>\`，按 `manifest.json` 对应版本。要点：

1. 哪个 dispatch / draw 是这次改动的载体
2. 关键资源（输入输出纹理格式、绑定）
3. 与基线的差异（多 dispatch？带宽变化？）

### 数值

| 指标 | 基线 | 本实验 | 变化 |
|---|---|---|---|
| PSNR / SSIM | | | |
| GPU 时间 (ms) | | | |

## 7. 结论

- 假设成立 / 不成立，证据是什么
- 意外发现（如果有）

## 8. 后续

下一步要做什么，或者为什么停在这里。
