# 0003-sw-vs-hw-rt — 软件光追 vs 硬件光追：方案对比与调参

> 状态：**立项**（口径与协议已定，代码未开始）。
> 范围来自与项目负责人的确认：软件侧做 **GPU 自研 LBVH 遍历** 与 **屏幕空间/SDF 近似** 两条；
> 指标同时看 **性能**、**画质偏差**、**构建开销（时间与显存）**。

## 0. 结论先行：本课题的硬约束

Falcor 9.0 **不暴露** BVH 节点结构（只有不透明的 `RtAccelerationStructure`，Slang 里看不到节点）。
因此"软件光追"在 Falcor 里唯一诚实的定义是：**自己从场景三角形建一份 BVH，自己写遍历**。
好消息是这条路可行——`gScene.getIndices(meshID, tri)`、`gScene.getVertex(i)` 在 shader 里可用，
Falcor 还自带 `BitonicSort` / `PrefixSum` 可以复用来建 LBVH。

## 1. 要回答的问题（可证伪）

| # | 问题 | 证伪条件 |
|---|---|---|
| Q1 | 同场景/同着色/同分辨率下，自研 LBVH 遍历比 DXR 慢几倍？随三角形数与发散程度如何变化？ | 差距 < 2× 且不随复杂度变化 |
| Q2 | 这个差距里，多少来自遍历本身（ALU/带宽/占用率），多少来自降噪/近似换来的画质损失？ | 遍历开销无法与近似收益分离 |
| Q3 | 屏幕空间/SDF 近似在什么性能预算下画质可接受（相对参考图的 PSNR/SSIM 阈值）？ | 任何预算下画质都不可接受或性能无优势 |
| Q4 | 微调（workgroup 尺寸、ray compaction、排序、wavefront vs megakernel）能把差距缩小多少？ | 调参对差距无显著影响（<10%） |

**参考真值**：硬件 RT（DXR pipeline）以高 spp 渲染的图，作为软件遍历与近似的偏差基准。

## 2. 方法：一个 pass，多个后端（防混淆的唯一正确做法）

新增 `research/passes/RTProbe/`，`backend` 属性四选一：

| backend | 遍历由谁执行 | 对应现实中的方案 |
|---|---|---|
| `Pipeline` | RT 硬件 + DXR，SBT 多命中组 | 工业主流：DXR / Vulkan RT、RTXDI、UE5 硬件光追 |
| `Inline` | RT 硬件，由 compute 调度（`SceneRayQuery`） | 工业混合路线：RT 用于阴影/GI 探针；学术讨论占用率与发散 |
| `Software` | 我们自己的 LBVH（compute 栈式遍历） | 学术主线：LBVH 构建、遍历、coherence、带宽分析 |
| `ScreenSpace` | 不遍历几何（深度 + 屏幕空间射线 / SDF） | 工业折衷：SSR、Lumen 的软件追踪路径 |

**铁律**（否则数据不可比）：

1. 四个后端共用**同一份着色代码**（`RTProbeShading.slangh`），只让"遍历"这一个变量变。
2. 共用同一相机、同一场景、同一分辨率、同一 spp、同一 `RAY_FLAG` 与 epsilon。
3. 输出统一为 `color`（RGBA16F）→ `ToneMapper` → 落盘，禁止每个后端自己选格式。
4. **不要**直接对比上游不同 pass（例如 `MinimalPathTracer` vs `GBufferRT` 的 traceInline）：
   它们着色阶段不同，比出来的差值毫无意义。

## 3. 学术 ↔ 工业 对照表（随阅读更新）

| 关注点 | 学术路线 | 工业路线 | 本课题的测点 |
|---|---|---|---|
| 加速结构 | LBVH / SBVH、增量更新、压缩节点 | 驱动内 BVH（不透明）、每帧重建 or refit | 自建 LBVH 的构建时间与显存 vs DXR 隐式成本 |
| 遍历 | 栈式 / wavefront / megakernel、ray sorting、compaction | 固定功能 RT core；shader 里只写 `TraceRay` | Software vs Pipeline/Inline 的帧时间与发散 |
| 相干性 | tile/ Morton 排序、ray stream、两级调度 | 通常交给硬件重排 | 排序开启前后 Software 的加速比 |
| 替代方案 | SDF 追踪、neural caching | SSR + SDF + 硬件 RT 混合（Lumen 形态） | ScreenSpace 的画质-性能曲线 |
| 降噪 | SVGF/ReSTIR/NRD 类 | NRD/DLSS、时域累积 | 同 spp 下各后端的噪声与收敛（若接降噪需单列） |

> 阅读清单先记在本表空白处，写进 `docs/` 前不必背下来——表格本身就是报告的一节。

## 4. 测量协议

**固定项**：相机用脚本固定（不交互）、分辨率 960×540 / 1280×720 / 1920×1080 三档、
spp ∈ {1, 4}、maxBounces = 0（只测主光线，先隔离遍历成本）。
**采样**：每档 ≥300 帧，丢弃前 30 帧（着色器编译/缓存预热），报告**中位数**与 **P95**。

**帧时间采集**：Mogwai 的 Timing Capture 扩展（脚本全局对象 `tc`）：

```python
tc.captureFrameTime(r"D:\Eidolon\experiments\0003-sw-vs-hw-rt\results\frames.csv")
```

**归因**（只看总时间会误判）：用 RenderDoc 抓一帧，记录 dispatch 数、占用率相关计数、
以及 Software 后端的累加遍历步数（我们会把它写进一个 `Buffer` 里导出）。

**GPU/驱动**：同机同驱动；`RelWithDebInfo`；关闭 D3D12 调试层；显存上限 8 GB——
LBVH 额外占用约 `三角形数 × 12 B` + 节点，重场景先降分辨率验证可行性。

## 5. 阶段与验收

| 阶段 | 交付 | 验收标准 |
|---|---|---|
| **P0 骨架** | `RTProbe` 支持 `Pipeline` + `Inline`，共用着色 | 两后端输出**像素级一致**（PSNR = ∞），帧时间 CSV 可复现 |
| **P1 硬件基线** | 3 分辨率 × 2 场景的 A/B 曲线 | 差距稳定可复现（同机三次波动 < 5%） |
| **P2 软件遍历** | LBVH 构建（compute）+ 栈式遍历；构建时间/显存进表 | 与 `Pipeline` 画质差异仅来自浮点/自阴影偏差（定量给出） |
| **P3 近似路线** | `ScreenSpace`（深度 + 屏幕空间射线）或 SDF 追踪 | 画出画质-性能曲线，指出"性能预算 → 画质"拐点 |
| **P4 调参矩阵** | workgroup ∈ {8,16,32}、compaction on/off、排序 on/off、wavefront vs megakernel | 每次只动一个变量；给出缩小差距的最优组合 |
| **P5 结论** | `figures/` 对照图 + 一页结论 | 能回答：什么场景下软件遍历更划算、工业为何选硬件 |

## 6. 已知风险

| 风险 | 影响 | 应对 |
|---|---|---|
| 自建 BVH 的构建开销可能盖过遍历收益 | Q1 结论被扭曲 | 构建时间单列；区分"每帧重建"与"仅首帧构建"两种模式 |
| 四个后端的着色难以做到逐位一致 | 画质对比出现假差异 | 共享 `.slangh`；先做 A/B 像素一致验证（P0 验收） |
| `Inline` 与 `Pipeline` 差距很小（同一硬件） | Q1 一部分答案可能是"没差别" | 这本身是有价值的工业结论，如实报告 |
| 8 GB 显存 | 重场景 + LBVH 会 OOM | 先 960×540；LBVH 用 32 位节点压缩 |
| 屏幕空间近似缺几何 | 画质差距过大，结论变成"显然更差" | 明确它的定位是"性能预算极限下的下界"，并与 SDF 变体分开报 |

## 7. 计划中的文件

```
research/passes/RTProbe/
├─ RTProbe.h/.cpp            # 四后端切换、SBT、LBVH 构建调度
├─ RTProbeShading.slangh     # 唯一一份着色代码（四后端共用）
├─ RTProbe.rt.slang          # Pipeline 后端（rayGen/closestHit/miss）
├─ RTProbe.cs.slang          # Inline 后端（SceneRayQuery）
├─ RTProbeSoftware.cs.slang  # Software 后端（自建 LBVH 遍历）
├─ RTProbeSS.cs.slang        # ScreenSpace 后端
└─ RTProbeBuild.cs.slang     # LBVH 构建（Morton + 排序）

experiments/0003-sw-vs-hw-rt/
├─ graphs/hw_pipeline.py、hw_inline.py、sw_lbvh.py、ss_trace.py
├─ configs/*.json            # 分辨率 / spp / backend / 排序开关
└─ figures/                  # 最终对照图
```

运行方式（每个后端起一个图，参数走 config）：

```powershell
pwsh -File tools\run-experiment.ps1 -Experiment 0003-sw-vs-hw-rt -ConfigName hw-pipeline.json
```

## 8. 下一步（P0）

1. 写 `RTProbe` 的 `Pipeline` 与 `Inline` 两个后端（三角形网格场景，v1 不支持曲线/SDF 几何）；
2. 共享 `RTProbeShading.slangh` 保证着色一致；
3. 用 `analysis/metrics.py` 验证两后端像素级一致（这是整条测量链的信任基础）；
4. 接 `tc.captureFrameTime` 出第一份 CSV。
