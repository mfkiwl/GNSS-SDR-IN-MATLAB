# GNSS 接收项目（PlutoSDR + MATLAB）

## 项目目标

用 MATLAB 驱动 ADALM-PlutoSDR 接收 GPS L1 导航电文（后续扩展 GLONASS/Galileo/北斗），并实时显示。

## 硬件清单

| 硬件 | 说明 | 状态 |
|---|---|---|
| ADALM-PlutoSDR | AD9363，频率 325 MHz–3.8 GHz，覆盖 GPS L1 (1575.42 MHz) | ✅ 已有 |
| 有源 GPS 天线 | 内置 LNA，需要 3–5 V 直流馈电（经同轴线中心导体） | ✅ 已购 |
| Bias-T 偏置器 | 给有源天线馈电，同时保证 1575 MHz 射频通过 | ⬜ 待购（见下） |
| SMA 射频线 | 天线 → bias-T → Pluto RX1A（SMA 公母头匹配） | ⬜ 视情况 |

### Bias-T 选购要点

- **频率**：工作频段必须覆盖 1.2–1.6 GHz（至少含 1575.42 MHz），典型产品覆盖 10 MHz–4/6 GHz
- **直流馈电**：输出 3.3 V 或 5 V（以你天线标称电压为准，绝大多数有源 GPS 天线 3–5 V），电流余量 ≥ 100 mA
- **结构**：三端口——RF+DC（接天线）、RF（接 Pluto，直流被隔离）、DC（接电源）；这样直流不会倒灌进 Pluto 的 RX 口
- **插损**：≤ 1 dB 为佳
- **推荐形式**：
  - 成品：Mini-Circuits ZFBT-4R2G+ 系列、淘宝"GPS 偏置器/bias-tee 5V"、"有源天线馈电器"
  - 或带电源的 GPS 信号分配器（兼做 bias-T）
- **注意**：Pluto 的 RX1A 口是交流耦合，接 bias-T 的 RF 端（DC 隔离端）最稳妥；天线端电压别接反，极性一般是中心导体为正

## 软件架构（三个阶段）

### 阶段一：前端采集（已完成脚手架）

`plutoGnssFrontEnd.m` —— 配置 Pluto 接收 L1 并保存 IQ：

```matlab
cd('D:\13_MCP\GNSS')
plutoGnssFrontEnd                        % 默认 2.5 MSPS, 2 s
plutoGnssFrontEnd('Fs',5e6,'DurationMs',5000,'GainMode','Manual','GainDb',45)
```

输出：`data\pluto_gnss_<时间戳>.mat`（complex double）和 `.bin`（int8 交织 I/Q，SoftGNSS 兼容）。

### 阶段二：捕获（Acquisition）

对 32 颗 PRN 做并行码相位搜索（FFT 相关），输出每颗卫星的多普勒频移与码相位。
**已完成离线调通（2026-08-07）**，文件：

| 文件 | 功能 |
|---|---|
| `acquisition.m` | 捕获主函数：FFT 并行码相位搜索（PRN x 多普勒二维搜索） |
| `generateSyntheticGpsSignal.m` | 合成 GPS L1 C/A 信号（延迟/多普勒/噪声可控，离线测试用） |
| `runAcquisitionTests.m` | 离线测试脚本（6 项，全部 PASS） |

```matlab
cd('D:\13_MCP\GNSS')

% 合成一段已知参数信号（PRN5，码相位 876，多普勒 +2300 Hz，C/N0=45 dB-Hz）
[sig, truth] = generateSyntheticGpsSignal('PRN', 5, 'Fs', 2.5e6, ...
    'DurationMs', 30, 'CodePhase', 876, 'DopplerHz', 2300, 'CN0dBHz', 45);

% 捕获（默认：32 PRN，多普勒 +-10 kHz / 500 Hz 步进，10 ms 非相干积分）
acq = acquisition(sig, 2.5e6);
acq.detectedPRN     % 检测到的卫星 PRN
acq.results         % 每颗卫星的码相位（采样点）/ 多普勒 / 检测指标

% 一键回归测试
runAcquisitionTests
```

关键设计要点：

- **码相位语义**：从块起点到下一个码周期起点的延迟（采样点，1-based），
  可直接作为 M3 跟踪的初始码相位
- **FFT 相关必须是圆周相关**（FFT 长度 = 块长），不能用零填充线性相关——
  否则码相位接近码周期末尾时会错位（已踩坑修复）
- **多普勒步进 500 Hz**：估计误差 +-250 Hz（格点量化）；弱信号（C/N0<38 dB-Hz）
  建议用 `IntegrationMs>1` 相干积分，并把 `DopplerStep` 相应减小
- **检测门限默认 6**（峰值/噪声均值）：纯噪声 8 组随机种子实测最大约 3.6，余量充足

参考：SoftGNSS `acquisition.m`（perrysou/GNSS_SDR）；真实卫星数据接入
（`plutoGnssFrontEnd` 采集的 .mat）后直接调用 `acquisition(data, fs)` 即可。

### 回环自测（TX 发射合成 GPS → RX 捕获）

`verifyGnssLoopback.m` —— 用 Pluto TX 发射合成 C/A 码，RX 采集后跑捕获，
验证全射频链路（无需真实卫星）：

```matlab
cd('D:\13_MCP\GNSS')
verifyGnssLoopback                                            % 默认（链路验证）
verifyGnssLoopback('TxGain', -89.75, 'TxAmplitude', 0.034)    % 真实 GPS 功率量级（C/N0≈45 dB-Hz）
```

辅助文件：

| 文件 | 功能 |
|---|---|
| `generateGnssTxBuffer.m` | 生成 TX 基带缓冲（整数个码周期，可含 50 bps 电文） |
| `plutoGnssTx.m` | 独立发射脚本（天线测试用） |
| `verifyGnssLoopback.m` | 回环闭环验证：TX 发射 + RX 采集 + 捕获 + 判定 |

要点（均已实测）：

- **Pluto TX `Gain` 属性范围 0 ~ -89.75 dB，0 = 最大输出**；回环/天线测试
  务必从负值衰减起步，避免 RX 饱和削波
- TX/RX 采样率必须一致（2.5 MSPS，Pluto 共享基带时钟）；TX 缓冲须整数个码周期
- 回环信号 TX/RX 共时钟，捕获多普勒应为 0 Hz
- 强信号（C/N0≥60 dB-Hz）下 C/A 码互相关会让 32 颗 PRN 全部越门限，属已知物理现象；
  真实 GPS 信号电平（C/N0≈45 dB-Hz）无此问题，判定标准为目标星指标 ≥ 3 倍次高

### 阶段三：跟踪 + 导航电文解码 + 实时显示

- 每通道 DLL/PLL 跟踪，解调 50 bps 导航电文
- 解析星历（Subframe 1/2/3）、时间、伪距
- 最小二乘定位 → 实时显示：天空图、频谱、C/N0、解码子帧、位置/时间
- 参考：SoftGNSS `tracking.m` / `postNavigation.m`；GNSS-SDR 作为对照验证

## 与两个参考项目的关系

- **perrysou/GNSS_SDR（SoftGNSS v3.0）**：MATLAB 核心算法可直接移植/复用，需把前端换成我们的 `plutoGnssFrontEnd` 输出格式
- **gnss-sdr/gnss-sdr**：C++ 实时接收机，原生支持 PlutoSDR（`PlutoSDR` 信号源），可跑在 WSL2/Docker 里做基准验证（生成 RINEX、PVT），MATLAB 负责显示与教学演示

## 下一步

1. 购买并接入 bias-T，给有源天线供电（天线放窗边/开阔处）
2. 实测前端：跑 `plutoGnssFrontEnd('DurationMs', 5000)`，检查频谱是否出现 GPS 信号特征
3. 实现捕获模块（可先用我们之前存的 .mat 数据离线调试）
4. 实现跟踪与导航电文解码，最后做成实时 GUI
