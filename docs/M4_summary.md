# M4 阶段总结报告：星历解析 → 多星定位 → 实时显示

> **阶段**：M4（导航电文子帧解析 + 定位解算 + 实时 GUI）
> **时间**：2026-08-07 ~ 2026-08-10
> **结论**：**核心验收全部 PASS** —— M4.1 星历解析、M4.2 多星定位
> （Synthetic + **硬件闭环**）、实时 GUI、一键演示
> **当前 HEAD**：`50bc3fa`（main，已推送）

---

## 1. 阶段目标与验收

用 MATLAB + PlutoSDR 完成 GPS 接收机全链路：**电文子帧解析 → 星历还原 →
卫星位置 → 伪距 → 最小二乘定位 → 实时显示**。因有源天线 bias-T 未供电，
真实卫星不可用，全程以 **TX 发射模拟卫星信号 + RX 有源天线接收** 的方式
闭环验证（发射内容为官方 RINEX 真实星历）。

| 子项 | 内容 | 验收 | 状态 |
|---|---|---|---|
| M4.1 | 子帧 1/2/3 → 星历 26 字段 + 卫星 ECEF 位置 | 字段与官方 RINEX 量化容差内一致；32 星物理校验 | ✅ PASS（08-07） |
| M4.2 | 多星 TX → 伪距 → 最小二乘定位 | 解算位置距参考点 < 300 m | ✅ PASS（Synthetic 218 m / **硬件 133 m**） |
| M4 GUI | uifigure 实时显示（C/N0/天空图/电文/位置） | 可回放/实时显示 | ✅ 完成（08-10） |
| 演示 | 一键运行 + 可视化 + 原始电文输出 | 跑通并出图 | ✅ 完成 |
| 真实卫星 | bias-T 供电后真实星座定位 | — | ⬜ 待 bias-T |

## 2. 交付物清单

### 代码（`matlab/acquisition/`，30 个 .m 全部同步）

| 模块 | 用途 |
|---|---|
| `readRinexNav.m` | RINEX 2.11 广播星历解析（`rinexread` 不支持 2.x） |
| `rinexToGpsCfg.m` | RINEX → 官方 HelperGPSNavigationConfig → LNAV 子帧编码 |
| `verifyOfficialEphemeris.m` | 官方电文验证（Synthetic + 硬件闭环） |
| `gnssEphDecode.m` | 子帧 1/2/3 → 星历 26 字段 |
| `satellitePosition.m` | 星历 → 卫星 ECEF 位置 + 钟差（IS-GPS-200 §20.3.3.4） |
| `verifyGnssEphDecode.m` | M4.1 验证（字段 + 32 星物理校验） |
| `generateMultiSatTxBuffer.m` | 多星叠加 TX 缓冲（每星独立延迟/幅度） |
| `gnssPseudorange.m` | 跟踪 + 子帧 → 伪距（亚毫秒比特边界解析） |
| `leastSquaresPosition.m` | 伪距最小二乘定位（位置 + 钟差，含 GDOP） |
| `verifyGnssPositioning.m` | M4.2 定位验证（Synthetic / 硬件双模式） |
| `demoGnssPositioning.m` | 一键演示（5 幅可视化 + 总览 + 原始电文输出） |
| `gnssLiveGui.m` | 实时显示 GUI（uifigure） |

### 文档（`docs/`）

| 文档 | 内容 |
|---|---|
| `M4_ephemeris.md` | M4.1 星历解析 + 卫星位置验证报告 |
| `M4_positioning.md` | M4.2 定位验证报告（Synthetic + 硬件附录 A） |
| `M4_summary.md` | **本文档**（阶段总结） |
| `HANDOFF.md` | 项目交接文档（§5.9-5.12 覆盖 M4） |

### 数据产物（`data/`，.mat 含完整结果）

| 产物 | 场景 |
|---|---|
| `gnss_eph_decode_20260807_183432.mat` | M4.1 阶段 A+B |
| `gnss_positioning_20260807_190418.mat` | M4.2 Synthetic（218 m） |
| `gnss_positioning_20260810_105452.mat` | M4.2 **硬件**（133 m） |
| `demo_gnss_positioning_20260810_105452_*.png` | 硬件演示 6 图 |
| `gnss_live_gui_20260810.png` | GUI 截图 |

## 3. 验证结果汇总

### 3.1 M4.1 星历解析（Synthetic）

```text
[A] 字段 26/26 通过；卫星位置 r=2.6421e7 m (PASS)
[CONST] 32 星半径 2.6509e7±2.0e5 m (PASS)，整周期对径比 0.9963±0.0041 (PASS)
[B] 24 s 合成闭环：捕获 metric 125.5、跟踪 CN0 43.9、0/1185 误码、
    星历还原 26/26
```

### 3.2 M4.2 多星定位（注入真实星座几何）

| 指标 | Synthetic（08-07） | 硬件（08-10） |
|---|---|---|
| 卫星数 | 6（PRN 11/1/3/28/15/24） | 6（同） |
| 捕获 | 6/6（metric 125.5） | 6/6（1 ms 捕获） |
| 跟踪 CN0 | 40.8~41.8 dB-Hz | 43.5~44.5 dB-Hz |
| 伪距 vs 注入真值 | 6.5 m | **4.1 m** |
| 定位误差（参考点上海） | 217.9 m | **132.7 m** |
| GDOP / 残差 RMS | 7.7 / 38.5 m | 7.7 / 20.9 m |
| 验收 | PASS（<300 m） | PASS（<300 m） |

硬件模式说明：Pluto TX 单缓冲上限 6.7 s → 仅发射子帧 1（300 位），
卫星位置由 RINEX 已知星历提供（Synthetic 已验证从信号解码的完整链路）。

### 3.3 GUI / 演示

- `gnssLiveGui`：C/N0 动态曲线、天空图、解码电文、定位结果四面板 +
  播放控制；合成 / 硬件 / 载入结果三种模式
- `demoGnssPositioning`：一键跑全链路 + 6 张可视化 + 控制台输出解码
  原始电文（300 位比特 + TLM/HOW/数据字 + 星历 26 字段）

## 4. 关键技术结论与踩坑（M4 阶段新增）

1. **亚毫秒比特边界解析（伪距精度核心）**：子帧起点 = 比特边界 = 码相位
   零点，位于毫秒网格的分数位置。整数 ms 比特同步锚定子帧产生每星
   ±1 ms（300 km）伪距歧义（初版位置误差 1776 km）。解法：能量曲线抛物线
   插值得亚毫秒比特相位 b_true → 子帧起点分数毫秒 P → 码相位零点采样
   `e_sf = floor(P)·msLen + codePhase(floor(P)+1)`。修复后伪距一致
   6.5 m（合成）/ 4.1 m（硬件）。
2. **5 ms 相干捕获的多周期歧义**：圆周相关对周期码有 ±1 ms 等高峰，
   多星/弱信号下部分卫星锁错周期（码相位偏 500~1000 采样，DLL 牵引范围
   仅 ~1 chip 必失锁）。硬件多星捕获须用 **1 ms 相干积分**（实测 6 星
   码相位全部精确）；合成模式 5 ms 无此问题（无射频噪声）。
3. **统一锚定子帧 1**：不同子帧起点差 6-12 s（卫星位移 ~50 km）会造成
   伪距几何不一致；须统一锚定子帧 1（TOW 基准一致）。
4. **28 s 采集保证完整子帧 1**（Synthetic 900 位场景）：有效比特 ≥1199
   才保证任意对齐下含完整子帧；硬件 300 位场景 12.5 s 足够。
5. **ECEF 60 s 位移可达 ~350 km**：轨道运动（~231 km/60 s）+ 地球自转
   视运动（≤1925 m/s）叠加；判定须按 [100,400] km 并附加轨道半径稳定性。
6. **整周期对径是 ECEF 下的强校验**：GPS 周期 ≈ 半个恒星日，一个周期后
   地球自转 ~180°，ECEF 位置对径（≈2r）——32 星实测 0.9963±0.0041。
7. **字段回绕**：RINEX 的 M0/DeltaN 等超出 ICD 字段位宽时按二补码回绕
   （物理等效），比对须按字段范围取模。
8. **MATLAB 细节**：`struct()` 遇 cell 值会展开成结构数组；`+` 会把零
   虚部折叠成实数（Pluto TX 须强制 `complex`）；`cell == 字符串` 须用
   `strcmp`。
9. **多星 18 s 重复周期歧义是公共时标误差**，被最小二乘钟差吸收，不
   影响位置。

> M4 之前的关键修复（M3.5，官方星历验证时发现）：自研奇偶链补全 ICD 的
> HOW/字 10 特例（D29/D30=0）与 D30 位反转，现与官方 Helper 链逐位互操作。

## 5. 复现步骤

```matlab
addpath('D:\13_MCP\GNSS');
addpath('D:\tools\matlab2022b\examples\satcom\main');   % 官方 Helper

% M4.1 星历解析（~1 min）
verifyGnssEphDecode

% M4.2 多星定位（Synthetic，~1.5 min）
verifyGnssPositioning

% 一键演示 + 可视化 + 原始电文输出
demoGnssPositioning('MsgPRN', 11)

% 实时 GUI
gnssLiveGui
gnssLiveGui('LoadFile', 'D:\13_MCP\GNSS\data\gnss_positioning_20260810_105452.mat')

% 硬件多星定位（TX 6 星叠加 → 天线 RX，需发射确认，~2 min）
demoGnssPositioning('Synthetic', false, 'MsgPRN', 11)
```

PowerShell 无头运行：

```powershell
& 'D:\tools\matlab2022b\bin\matlab.exe' -batch "addpath('D:\13_MCP\GNSS'); addpath('D:\tools\matlab2022b\examples\satcom\main'); demoGnssPositioning('MsgPRN',11);"
```

## 6. 现状与下一步

### 已完成

- 接收机全链路：采集 → 捕获 → 跟踪 → 电文解码 → 星历 → 卫星位置 →
  伪距 → 定位 → 实时显示，Synthetic + 硬件闭环均 PASS
- 定位精度：硬件 132.7 m（受注入延迟采样量化 120 m 限制）

### 待办

1. **bias-T 到货**：给有源天线供电 → 真实卫星捕获（M2 验收 ②）→
   真实星座定位（参考点 = 天线实际位置）
2. 硬件模式发射完整 5 子帧（TX 缓冲切换，每 6 s 换子帧）→ 星历也从
   信号解码
3. GUI 接实时流（当前为结果回放；接 Pluto `step()` 需增量跟踪）
4. 多普勒注入（当前 0 Doppler 静态场景）
