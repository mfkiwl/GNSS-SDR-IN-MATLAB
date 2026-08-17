# GNSS-SDR-IN-MATLAB

基于 **MATLAB + ADALM-PlutoSDR** 的 GNSS 软件接收机：接收 GPS L1 信号，完成
**捕获 → 跟踪 → 导航电文解码 → 实时显示** 全链路。

[![MATLAB](https://img.shields.io/badge/MATLAB-R2022b-orange)](https://www.mathworks.com/products/matlab.html)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/Status-M5%20PASS-brightgreen)]()

## 项目目标

用 MATLAB 驱动 ADALM-PlutoSDR（AD9363）接收 GPS L1 (1575.42 MHz) 信号，
在 MATLAB 中完成卫星捕获、码/载波跟踪、导航电文（50 bps）解码与定位解算，
并以实时 GUI 展示频谱、捕获结果、天空图、C/N0、导航电文与定位结果。

## 里程碑状态

| 里程碑 | 内容 | 状态 |
|---|---|---|
| M1 | PlutoSDR 连续采集链路验证（4 MSPS、无丢帧） | ✅ PASS (2026-08-06) |
| M2 | 捕获模块：32 颗 PRN 并行码相位搜索（FFT） | ✅ PASS (2026-08-07) |
| M3 | 跟踪模块：DLL/PLL 多通道跟踪（Synthetic + 硬件闭环） | ✅ PASS (2026-08-07) |
| M4 | 导航电文解码 + 星历/定位解算 + 实时 GUI | ✅ PASS (2026-08-17，硬件闭环定位 133/136 m) |
| M5 | 真实卫星接收：窗外有源天线（Bias-T），完整导航电文 + 广播星历解码 | ✅ PASS (2026-08-17，PRN 27，GPS Week 384) |

## 硬件要求

- ADALM-PlutoSDR（USB 连接，识别为串口 + RNDIS 网卡）
- 7020-SDR 新板（Z7020+AD9361，MATLAB 支持包直接识别，固件 0.38；
  板载 **0.5 ppm TCXO**，L1 频偏约 ±0.8 kHz，工作点 TX −60 dB / RX 40 dB）
- 有源 GPS L1 天线（内置 LNA，需 3–5 V 馈电）
- **Bias-T 偏置器**：给有源天线馈电，同时通过 L1 射频（详见 [docs/project_overview.md](docs/project_overview.md)）
- TX→RX 回环线（SMA 短线，用于 M1 数据链路验证）

## 软件要求

- MATLAB R2021a+（本项目在 R2022b 验证）
- Communications Toolbox（含 ADALM-Pluto Radio 支持包）
- Signal Processing Toolbox、DSP System Toolbox
- Satellite Communications Toolbox（可选，含 `gnssCACode` 等辅助函数）

## 快速开始

```matlab
cd('GNSS-SDR-IN-MATLAB/matlab/frontend')

% 1) 采集一段 GPS L1 IQ 数据（保存 .mat 与 SoftGNSS 兼容 .bin）
plutoGnssFrontEnd('DurationMs', 5000)

% 2) 验证连续采集链路（需 TX-RX 回环线）
verifyPlutoStream

% 3) 捕获：离线测试（合成信号，6/6 PASS）
addpath('GNSS-SDR-IN-MATLAB/matlab/acquisition')
runAcquisitionTests

% 4) M3 跟踪：离线合成信号验证（Synthetic 模式，无硬件）
addpath('GNSS-SDR-IN-MATLAB/matlab/tracking')
verifyGnssTracking('Synthetic', true)

% 5) 长采集（真实卫星完整导航电文，≥30 s；自动丢弃 step() 流启动瞬态 10 s）
plutoGnssFrontEnd('DurationMs', 35000, 'GainMode', 'Manual', 'GainDb', 50)
```

## 仓库结构

```text
GNSS-SDR-IN-MATLAB/
├── docs/
│   ├── project_overview.md           # 项目总览：硬件选购、架构、路线图
│   ├── M1_streaming_verification.md  # M1 连续采集验证方案与结论
│   ├── M4_positioning.md             # M4.2 多星定位验证报告（Synthetic + 硬件闭环）
│   └── M5_real_satellite_reception.md # M5 真实卫星接收：完整导航电文/星历解码
├── matlab/
│   ├── frontend/                     # 射频前端：采集 + M1 验证
│   │   ├── gnssSettings.m
│   │   ├── plutoGnssFrontEnd.m
│   │   └── verifyPlutoStream.m
│   ├── acquisition/                  # M2/M4：捕获、子帧同步、电文解码、星历/定位、GUI
│   ├── tracking/                     # M3：跟踪模块（DLL/PLL，已验证 PASS）
│   ├── decoding/                     # M4：导航电文解码（并入 acquisition 验证脚本）
│   └── commlab/                      # 辅助模块：通信原理实验平台（调制解调演示）
├── data/                             # 采集数据与导出（gitignore，不入库）
│   └── prn27_navdata_20260817.txt    # 真实卫星比特流 + 原始子帧 + 星历导出示例
├── CHANGELOG.md
├── LICENSE
└── README.md
```

## 参考项目

- [perrysou/GNSS_SDR](https://github.com/perrysou/GNSS_SDR) —— SoftGNSS v3.0，MATLAB 离线接收机（算法参考）
- [gnss-sdr/gnss-sdr](https://github.com/gnss-sdr/gnss-sdr) —— C++ 实时 GNSS 接收机，原生支持 PlutoSDR（对照验证）
- [MathWorks: GPS Receiver Acquisition and Tracking Using Pluto SDR](https://www.mathworks.com/help/satcom/ug/gps-receiver-acquisition-and-tracking-using-pluto-sdr.html)

## 许可

MIT License，详见 [LICENSE](LICENSE)。
