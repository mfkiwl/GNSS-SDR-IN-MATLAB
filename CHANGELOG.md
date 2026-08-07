# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

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

### Key Findings (M1)

- `capture()` 循环调用帧间不连续，实时流应使用 `step()`
- `transmitRepeat` 测试音缓冲必须为整数周期，避免发送端相位跳变
- `kernelBuffersCount=32` 可吸收偶发调度延迟；稳态帧间隔 9.99 ms（4 MSPS）
