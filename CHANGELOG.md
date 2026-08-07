# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

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
