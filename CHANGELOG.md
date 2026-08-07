# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [0.7.0] - 2026-08-07

### Changed

- `docs/HANDOFF.md`：全面更新项目交接文档——覆盖 M2 捕获、TX 发射、
  50 bps 电文、连续子帧同步全部硬件验证成果，19 条关键技术结论与踩坑记录，
  复现步骤、已知风险、M3/M4 下一步计划与交接检查清单

## [0.8.0] - 2026-08-07

### Added

- `matlab/tracking/tracking.m`：M3 跟踪主函数——DLL（码环）+ PLL（载波环）
  多通道跟踪，1 ms 相干积分（IntegrationMs 可调 1~10），E/P/L 相关器
  （间距可配），Costas 鉴别器 + 非相干超前减滞后包络鉴别器，二阶位置式
  环路滤波器（PLL/DLL 带宽可配），位同步对齐的 C/N0（窄带/宽带功率比），
  双极性参考比特匹配，锁定判定（C/N0 + PLL 残差 + 码相位稳定性）
- `matlab/tracking/verifyGnssTracking.m`：M3 验证脚本（Synthetic 离线 /
  硬件闭环双模式，TX 子帧 → RX step() 连续流 → 捕获 → 跟踪 → 位同步 →
  子帧解码端到端对比）
- `docs/M3_tracking.md`：验证报告（含实验图）

### Key Findings (M3 跟踪验证)

- **Synthetic PASS**：C/N0 43.2 dB-Hz（真值 45），频率误差 0.03 Hz，
  码相位误差 0.01 采样，610 位 0 误码，子帧解码全对
- **硬件闭环 PASS**（TX −65 dB 天线场景，12.5 s step 流）：C/N0 35.9 dB-Hz，
  频率误差 0.11 Hz，609 位 0 误码，子帧解码全对
- **二阶环路滤波器必须用位置式 PI**：增量式会把比例项也积分成双积分器，
  导致噪声下随机游走、频偏下极限环（实测发散到 −55 kHz）
- **C/N0 的 20 ms 窗口必须按位同步对齐**：跨比特翻转时窄带功率被抵消，
  C/N0 低估 ~25 dB（比特仍 0 误码）
- 端到端子帧解码需 ≥ 600 位跟踪比特（12 s 采集）保证任意对齐下含完整子帧
- 参考比特匹配须测双极性（BPSK 180° 极性模糊）

## [0.9.0] - 2026-08-07

### Added

- `matlab/acquisition/readRinexNav.m`：RINEX 2.11 GPS 广播星历解析器
  （自包含，R2022b `rinexread` 仅支持 RINEX 3）
- `matlab/acquisition/rinexToGpsCfg.m`：官方 RINEX（2/3）→
  `HelperGPSCEIConfig` → `HelperGPSNAVDataEncode` LNAV 编码链路，
  自动跳过零占位星历、按历元换算 TOW、填入电离层/UTC 参数
- `matlab/acquisition/verifyOfficialEphemeris.m`：官方电文端到端验证
  （官方解码 33 字段交叉验证 + Synthetic 闭环）
- `data/auto2190.26n`（Garner UCSD）、`data/BRDC00WRD_R_20262190000_01D_MN.rnx`
  （BKG IGS 组合）：2026-08-07 官方广播星历样本
- `docs/OfficialEphemeris_verification.md`：验证报告（含实验图）

### Changed

- `gpsWordParity.m`：补全 ICD-GPS-200 §20.3.5.4 两项规则——HOW（字 2）
  与字 10 的 D29/D30 恒为 0（反馈重置），以及前字 D30=1 时本字 bit1..24
  位反转；新增 wordNumber 参数
- `generateGpsSubframe.m`：TLM 字改为 ICD 形状；逐字传字序号；
  `meta.dataWords` 改为实际发送逻辑位（字 10 的 bit23/24 为 ICD 反推值）
- `gnssSubframeDecode.m`：校验与字段提取先还原 D30 位反转，按字序号
  校验（含 HOW/字 10 特例）

### Key Findings (官方星历验证)

- **PASS（Synthetic 闭环）**：编码一致性 33/33 字段、奇偶 30/30 字、
  捕获精确命中、跟踪 C/N0 43.8 dB-Hz、0/915 误码、子帧解码全匹配
- **自研奇偶链原不合 ICD**：连续 D29/D30 链且无位反转，自洽但无法与
  官方 Helper 链互操作；修复后四向交叉验证全过，M3/M2.5 回归 PASS
- RINEX 2 的 M0/DeltaN 等超范围字段按 ICD 字段位宽二补码回绕（物理
  等效），比对须按字段范围取模
- CDDIS 需 Earthdata 认证，改用 Garner/BKG IGS 镜像

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
