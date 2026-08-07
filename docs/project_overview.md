# 项目总览

## 项目目标

用 MATLAB 驱动 ADALM-PlutoSDR 接收 GPS L1 导航电文（后续可扩展 Galileo E1 /
北斗 B1I 等同频段信号），并实时显示。项目参考 SoftGNSS（perrysou/GNSS_SDR）
与 GNSS-SDR 的架构，分四个里程碑推进。

## 硬件清单与选购指南

| 硬件 | 说明 | 状态 |
|---|---|---|
| ADALM-PlutoSDR | AD9363，频率 325 MHz–3.8 GHz，覆盖 L1 (1575.42 MHz) | ✅ |
| 有源 GPS 天线 | 内置 LNA，需 3–5 V 直流馈电（经同轴线中心导体） | ✅ 已购 |
| Bias-T 偏置器 | 给有源天线馈电，同时保证 1575 MHz 射频通过 | ⬜ 待购 |
| SMA 射频线 | 天线 → bias-T → Pluto RX1A | ⬜ 视情况 |
| TX→RX 回环线 | M1 数据链路验证用（SMA 短线直连） | ✅ |

### Bias-T 选购要点

- **频段**：必须覆盖 1.2–1.6 GHz（含 1575.42 MHz），常见"10 MHz–6 GHz"宽带均可
- **馈电**：按天线标称电压选 3.3 V 或 5 V，电流余量 ≥ 100 mA
- **结构**：三端口——RF+DC（接天线）、RF（接 Pluto，直流隔离）、DC（接电源），
  防止直流倒灌进接收机
- **插损** ≤ 1 dB；淘宝搜"GPS 偏置器 / bias-tee 5V / 有源天线馈电器"，
  或 Mini-Circuits ZFBT-4R2G+ 系列
- 天线放置于窗边、天顶方向开阔处

## 信号与前端参数

- GPS L1 C/A：1575.42 MHz，1.023 Mcps，码周期 1 ms，导航电文 50 bps
- 前端推荐：中心 1575.42 MHz，采样率 **4–5 MSPS**，带宽 ≥ 2.5 MHz，AGC 或手动增益
- 说明：Pluto 的 TX/RX 基带采样率必须一致（共享 AD9363 基带时钟）

## 软件架构（四阶段）

```text
PlutoSDR (L1)
   │  step() 连续流 / capture() 大块采集
   ▼
前端采集 matlab/frontend/
   │
   ▼
捕获 (M2)  FFT 并行码相位搜索，32 颗 PRN × 多普勒
   │
   ▼
跟踪 (M3)  DLL + PLL 多通道，1 ms 相干积分，C/N0
   │
   ▼
解码/定位 (M4)  50 bps 电文 → 星历 → 伪距 → 最小二乘定位
   │
   ▼
实时 GUI  频谱 / 捕获网格 / 天空图 / C/N0 / 电文 / 位置
```

## 与参考项目的关系

- **perrysou/GNSS_SDR（SoftGNSS v3.0）**：MATLAB 核心算法（捕获/跟踪/导航）
  可直接移植；其输入为 int8 交织 IQ 文件，与本项目 `plutoGnssFrontEnd.m`
  输出格式一致
- **gnss-sdr/gnss-sdr**：C++ 实时接收机，原生支持 PlutoSDR
  （`PlutoSDR` 信号源，4 MSPS 实时配置），可作为基准验证工具
  （生成 RINEX / PVT），MATLAB 负责显示

## 里程碑路线图

| 里程碑 | 内容 | 状态 |
|---|---|---|
| M1 | 连续采集链路验证（无丢帧） | ✅ PASS |
| M2 | 捕获模块（FFT 并行码相位搜索，离线调通） | ✅ 合成信号 PASS（08-07） |
| M3 | 实时跟踪 | ⬜ |
| M4 | 导航电文解码 + 定位 + 实时 GUI | ⬜ |
