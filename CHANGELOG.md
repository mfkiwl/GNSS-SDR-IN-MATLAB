# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [0.6.0] - 2026-08-07

### Added

- `matlab/acquisition/gpsWordParity.m`：GPS 30 位字奇偶校验（ICD-GPS-200）
- `matlab/acquisition/generateGpsSubframe.m`：完整子帧电文生成（TLM/HOW/数据字）
- `matlab/acquisition/gnssBitEdgeDetect.m`：比特边缘检测（能量法 + 翻转直方图法）
- `matlab/acquisition/gnssSubframeDecode.m`：子帧边界同步（前导码 + 奇偶校验 +
  BPSK 极性消除）与字段解码
- `matlab/acquisition/verifyGnssContinuousNav.m`：连续子帧收发验证脚本
  （TX 持续发射 → RX step() 连续流 → 自主同步 → 解码对比）
- `docs/ContinuousNav_verification.md`：验证报告（含实验图）

### Key Findings (连续电文验证)

- **BPSK 180° 极性模糊**须由前导码 + 奇偶校验消除（单比特相位校准可能全反）
- Pluto `transmitRepeat` 缓冲与 `capture` 单帧均受 2^24 采样上限约束：
  2.5 MSPS 下 TX 最多 1 子帧（6 s），长采集须用 `step()` 连续流
- 位同步翻转直方图法优于纯能量法（弱信号下能量峰/次峰比仅 ~1.0，
  正确边界翻转率实测 0.44，接近理论 0.5）
- 硬件验证 PASS：6 秒子帧边界同步成功，电文 0 比特错误

## [0.5.0] - 2026-08-07

### Added

- `matlab/acquisition/demodulateNavBits.m`：50 bps 导航电文解调
  （码相位精对齐、逐 ms 剥码、位同步、40 位周期参考对齐、符号判决）
- `matlab/acquisition/verifyGnssNavData.m`：导航电文收发验证脚本
  （TX 发射带电文合成 GPS → RX 采集 → 捕获 → 解调 → 画图 → 存档）
- `docs/NavData_verification.md`：验证报告（含实验图）

### Key Findings (导航电文验证)

- 天线场景（拉杆 TX → 有源 RX，无 bias-T）100 位电文 **0 比特错误**，匹配率 1.000
- 参考对齐必须按 **40 位周期**循环生成（`mod` 索引），不能对截断序列 `circshift`：
  99 不是 40 的倍数，截断序列循环移位会破坏周期结构、产生成簇假错误
- 室内天线场景每比特相干能量存在多径幅度波动，但不影响 20 ms 积分后的符号判决

## [0.4.0] - 2026-08-07

### Added

- 天线传输验证：拉杆天线 TX → 有源天线 RX（无 bias-T，无源接收）闭环 **PASS**

### Changed

- `verifyGnssLoopback` 默认功率改为拉杆天线实测推荐值（TX -65 dB）
- README、docs/M2_acquisition.md：补充天线验证结果与功率建议

### Key Findings (天线验证)

- 天线路径损耗约 -44 dB（相对回环线），TX -65 dB 即回到真实 GPS 信号量级
- 无 bias-T 时有源天线以无源状态接收仍可稳定捕获（链路余量足够）
- 拉杆天线 1/4 波长（≈5 cm）起步即可，长度不敏感

## [0.3.0] - 2026-08-07

### Added

- `matlab/acquisition/generateGnssTxBuffer.m`：Pluto TX 基带缓冲生成器
  （合成 GPS C/A 码，整数码周期，可选 50 bps 电文）
- `matlab/acquisition/plutoGnssTx.m`：独立发射脚本（回环/天线测试）
- `matlab/acquisition/verifyGnssLoopback.m`：回环闭环验证
  （TX 发射合成 GPS → RX 采集 → 捕获 → 判定）

### Changed

- README、docs/M2_acquisition.md：补充回环验证结果与 TX 功率标定说明

### Key Findings (回环验证)

- **Pluto TX `Gain` 范围 0 ~ -89.75 dB，0 = 最大输出**；负值才是衰减，
  回环直连时 RX 会严重饱和（初测削波 79%）
- 回环信号 TX/RX 共时钟，捕获多普勒精确 0 Hz
- 强信号（C/N0 ≥ 60 dB-Hz）下 C/A 码互相关使 32 PRN 全部越门限；
  真实 GPS 功率量级（C/N0≈45 dB-Hz）下只剩目标星，判定标准为目标指标 ≥ 3× 次高

## [0.2.0] - 2026-08-07

### Added

- `matlab/acquisition/acquisition.m`：M2 捕获主函数（FFT 并行码相位搜索，
  32 PRN × 多普勒 ±10 kHz）
- `matlab/acquisition/generateSyntheticGpsSignal.m`：合成 GPS L1 C/A 信号生成器
  （延迟/多普勒/C/N0 可控，离线测试与标定用）
- `matlab/acquisition/runAcquisitionTests.m`：捕获模块离线回归测试（6 项，全部 PASS）
- `docs/M2_acquisition.md`：M2 方案、踩坑记录与测试结论

### Changed

- README：里程碑状态更新（M2 离线调通）、捕获模块快速开始示例
- docs/project_overview.md：M2 状态更新

### Key Findings (M2)

- 码相位搜索必须用**圆周相关**（FFT 长度 = 块长），零填充线性相关在大码相位时错位
- 码相位语义统一为"块起点到下一码周期起点的延迟（采样点，1-based）"
- 500 Hz 多普勒步进量化误差 ±250 Hz；弱信号需相干积分（IntegrationMs>1）
- 检测门限 6（峰值/噪声均值）：纯噪声 8 种子实测最大 3.39~3.62，零虚警

## [0.1.0] - 2026-08-07

### Added

- 项目骨架：README、LICENSE(MIT)、.gitignore、docs 文档
- `matlab/frontend/gnssSettings.m`：GNSS 前端与接收机参数配置
- `matlab/frontend/plutoGnssFrontEnd.m`：PlutoSDR L1 采集脚本（自动检测设备，
  输出 .mat 与 SoftGNSS 兼容的 int8 交织 .bin）
- `matlab/frontend/verifyPlutoStream.m`：M1 连续采集链路验证脚本
- `matlab/commlab/`：辅助模块，通信原理实验平台（AM/FM/ASK/QAM/FSK/TDM/FDM
  调制解调交互演示）
- `docs/M1_streaming_verification.md`：M1 验证方案与结论（PASS）
- `docs/HANDOFF.md`：项目交接文档（环境/硬件/代码资产/技术结论/下一步计划）

### Key Findings (M1)

- `capture()` 循环调用帧间不连续，实时流应使用 `step()`
- `transmitRepeat` 测试音缓冲必须为整数周期，避免发送端相位跳变
- `kernelBuffersCount=32` 可吸收偶发调度延迟；稳态帧间隔 9.99 ms（4 MSPS）
