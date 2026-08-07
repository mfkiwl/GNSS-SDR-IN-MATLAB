# GNSS-SDR-IN-MATLAB 项目交接文档

> **交接日期**：2026-08-07
> **编写方**：Codex 会话（工作目录 `C:\Users\chang.su\Documents\Codex in Matlab`）
> **目的**：为下一个 Codex 会话提供完整、准确的项目上下文，使其无需从零探索即可继续开发

---

## 1. 项目概览

**目标**：用 MATLAB 驱动 ADALM-PlutoSDR 接收 GPS L1 (1575.42 MHz) 信号，完成
**捕获 → 跟踪 → 导航电文解码 → 实时显示** 全链路，最终以实时 GUI 展示
频谱、捕获结果、天空图、C/N0、解码导航电文与定位结果。

**当前阶段**：

| 里程碑 | 内容 | 状态 |
|---|---|---|
| M1 | PlutoSDR 连续采集链路验证（4 MSPS、无丢帧） | ✅ PASS（2026-08-06） |
| M2 | 捕获模块：32 颗 PRN 并行码相位搜索（FFT） | ⬜ 待开发（下一步） |
| M3 | 跟踪模块：DLL/PLL 多通道实时跟踪 | ⬜ 规划中 |
| M4 | 导航电文解码 + 定位解算 + 实时 GUI | ⬜ 规划中 |

**总体架构**：

```text
PlutoSDR (L1 1575.42 MHz)
   │  step() 连续流 / capture() 大块离线采集
   ▼
前端采集（matlab/frontend/，已完成）
   │
   ▼
捕获 M2（FFT 并行码相位搜索，32 PRN × 多普勒 ±10 kHz）
   │
   ▼
跟踪 M3（DLL + PLL，1 ms 相干积分，C/N0）
   │
   ▼
解码/定位 M4（50 bps 电文 → 星历 → 伪距 → 最小二乘定位）
   │
   ▼
实时 GUI（uifigure：频谱/捕获网格/天空图/C-N0/电文/位置）
```

---

## 2. 环境与工具链（已配置完毕，勿重复配置）

| 软件 | 版本/路径 | 说明 |
|---|---|---|
| MATLAB | R2022b 9.13.0.2049777，`D:\tools\matlab2022b` | 110 个工具箱 |
| ADALM-Pluto 支持包 | Communications Toolbox Support Package for ADALM-Pluto Radio | 已安装，`findPlutoRadio`/`sdrrx`/`sdrtx` 可用 |
| Git for Windows | 2.55.0，`C:\Program Files\Git` | 已加入系统 PATH |
| VS Code | 1.130.x，`%LOCALAPPDATA%\Programs\Microsoft VS Code` | 已加入用户 PATH |
| GitHub CLI | 2.97.0，已登录 `suchang-ccc`（scope: repo） | 可创建/推送仓库 |
| Codex 桌面版 | 已安装 | 使用 `~/.codex/config.toml` |
| MATLAB MCP Server | v0.11.2，`C:\Users\chang.su\.matlab\agentic-toolkits\bin\matlab-mcp-core-server-win64.exe` | Codex↔MATLAB 桥接 |

### 2.1 Codex 配置（`C:\Users\chang.su\.codex\config.toml`）

`[mcp_servers.matlab]` 当前内容（注意：**用户已于 2026-08-06 13:35 自行修改**，
将 `--initial-working-folder` 从 `D:\13_MCP` 改为 `D:\suchang\program\Pluto SDR`）：

```toml
[mcp_servers.matlab]
command = 'C:\Users\chang.su\.matlab\agentic-toolkits\bin\matlab-mcp-core-server-win64.exe'
args = ['--matlab-root', 'D:\tools\matlab2022b', '--matlab-display-mode', 'desktop',
        '--initial-working-folder', 'D:\suchang\program\Pluto SDR']
tool_timeout_sec = 600
env_vars = ['WINDIR']
```

- 配置文件有备份：`C:\Users\chang.su\.codex\config.toml.bak-20260803`（MCP 未配置前的版本）
- 用户还添加了 `[sandbox_workspace_write] network_access = true`
- MATLAB Agentic Toolkit skills 已安装到 `~/.codex/skills` 与 `~/.agents/skills`
  （`matlab-create-live-script`、`matlab-debugging`、`matlab-install-products`、
  `matlab-list-products`、`matlab-read-doc`、`matlab-review-code`、`matlab-testing`）
- 参考仓库克隆于 `D:\12_GitHub\`：`matlab-mcp-core-server`、`matlab-agentic-toolkit`

### 2.2 用户自有目录（重要上下文）

`D:\suchang\program\Pluto SDR\` 是用户自建的 Pluto 工作目录（2026-07-22 起），
**不要改动**，其内容：

| 子目录/文件 | 内容 |
|---|---|
| `自回环测试\` | 用户自写的 TX→RX 回环脚本：`FM.m`、`QAM16.m`、`QAM64.m` |
| `Matlab官方示例\` | 官方示例：CaptureRFDataToBasebandFile、FMBroadcastReceiver、SpectrumAnalysis |
| `CommLab\` | 本项目的 CommLab 副本（2026-08-04 复制）+ 运行产物 |
| `.vscode\mcp.json` | 用户自己的 VS Code MCP 配置 |
| `adalmplutoradio.mlpkginstall` 等 | 支持包离线安装文件 |

---

## 3. 硬件状态

| 硬件 | 状态 |
|---|---|
| ADALM-PlutoSDR（序列号 `104473023196000bf5ff1a00aae12c3ca8`） | ✅ 可用；**交接时（08-07）不在线，需重新插拔/检查** |
| 有源 GPS L1 天线 | ✅ 已购，**尚未通电**（等 bias-T） |
| Bias-T 偏置器 | ⬜ 待购（选购要点见 §3.2） |
| TX→RX 回环线（SMA 短线） | ✅ M1 验证用 |

### 3.1 PlutoSDR 识别特征

- USB 串口：`PlutoSDR Serial Console (COM3)`（COM 号可能随插入顺序变化）
- 网络：`PlutoSDR USB Ethernet/RNDIS Gadget`，本机 192.168.2.10 ↔ Pluto 192.168.2.1
  （RNDIS IP 可能变化；MATLAB 对象属性中曾见 `uri: ip:10.0.0.200`，属遗留值）
- 固件版本 **0.38**（支持包测试版本 0.34，启动时有警告，不影响使用；
  若出现异常行为可考虑降级固件，参考 Hardware Setup App）
- **代码中一律用 `findPlutoRadio()` 自动检测设备 ID**，不要硬编码 `usb:0`

### 3.2 Bias-T 选购要点（给用户/采购）

- 频段覆盖 1.2–1.6 GHz（含 1575.42 MHz），典型"10 MHz–6 GHz"宽带产品均可
- 馈电 3.3 V 或 5 V（按天线标称），电流余量 ≥100 mA
- 三端口结构：RF+DC 接天线、RF 接 Pluto（直流隔离）、DC 接电源，防直流倒灌
- 插损 ≤1 dB；淘宝搜"GPS 偏置器 / bias-tee 5V / 有源天线馈电器"，
  或 Mini-Circuits ZFBT-4R2G+ 系列；天线放窗边、天顶开阔处

---

## 4. 代码资产清单

### 4.1 位置总览（三处，内容按需同步）

| 位置 | 用途 |
|---|---|
| `C:\Users\chang.su\Documents\Codex in Matlab\GNSS\`（工作区） | **开发主副本**（apply_patch 可编辑） |
| `D:\13_MCP\GNSS\`（MATLAB 运行目录） | MATLAB 实际运行位置（含 `data\` 产物） |
| `C:\Users\chang.su\Documents\GNSS-SDR-IN-MATLAB\`（Git 仓库） | GitHub 仓库本地副本，`main` 分支 |

**同步规则**：工作区与 `D:\13_MCP\GNSS` 内容一致（用 `Copy-Item` 双向同步并校验哈希）；
Git 仓库结构独立（`matlab/frontend` 等），每次进展 commit + push。

### 4.2 前端模块文件（`matlab/frontend/`）

| 文件 | 功能 |
|---|---|
| `gnssSettings.m` | GNSS 参数：中心频率 1575.42 MHz、采样率 2.5e6、AGC、SoftGNSS 兼容格式定义 |
| `plutoGnssFrontEnd.m` | L1 采集脚本：`findPlutoRadio` 自动检测 → `sdrrx` 配置 → `capture` 大块采集 → 存 `.mat` + SoftGNSS 兼容 int8 交织 `.bin` |
| `verifyPlutoStream.m` | M1 验证脚本：A 前端健康 / B step 连续流 / C 回环音相位连续性 / D 大块 capture 对照 |

### 4.3 辅助模块（`matlab/commlab/`）

通信原理实验平台（uifigure GUI）：AM/FM/ASK/QAM/FSK 调制解调 + TDM/FDM 复用演示。
文件：`CommLab.m`、`genSignal.m`、`demodSignal.m`、`defaultParams.m`、
`runCommLabTests.m`、`README.md`。核心算法与 GUI 分离，单元测试 7/7 PASS。

### 4.4 文档

- `docs/project_overview.md`：硬件选购、架构、路线图
- `docs/M1_streaming_verification.md`：M1 方案与结论
- `docs/HANDOFF.md`：本文档副本
- `README.md`、`CHANGELOG.md`、`LICENSE`(MIT)、`.gitignore`

---

## 5. M1 成果与关键技术结论（核心，务必理解）

### 5.1 M1 最终判定（2026-08-06，4 MSPS / 15 s 流 / 2 s 对照）

| 检查项 | 结果 | 实测数据 |
|---|---|---|
| A. 前端健康 | ✅ PASS | RMS=0.244，削波 0.22%，DC=0.042 |
| B. step 连续流 | ✅ PASS | 稳态帧间隔 **9.99 ms**（≤12 ms），p95=11.96 ms，max=53.5 ms |
| C. 回环音连续性 | ✅ PASS | 频率误差 33 Hz，SNR **81.0 dB**，**相位跳变 0 次**（1500 帧） |
| D. 大块 capture 对照 | ℹ️ 信息项 | 2 s 块完整（8M/8M 采样），耗时 4.26 s |

另有一次 20 s 长稳态测试：1935 帧、有效吞吐 **3.869 MSPS**、稳态帧间隔 **9.77 ms**、
p95=11.16 ms、相位跳变 0、首帧延迟 678.7 ms（一次性）。

### 5.2 六大关键发现（设计 M3 时必须遵守）

1. **`capture(rx, N)` 循环调用帧间不连续**——每次调用重新同步，
   实测每帧 ~124 ms、逐帧相位跳变。**`capture` 只用于一次性大块离线采集**。
2. **`step(rx)` 是真正的连续流接口**——帧内容首尾相接、相位连续。
   M3 实时化必须基于 `step()`（配合双缓冲）。
3. **测试音必须相位连续**：`transmitRepeat` 的缓冲须含整数个信号周期
   （3 ms × 97.333 kHz = 292 整周期）。若用非整数周期（如 97.123 kHz × 1 ms），
   TX 自身每周期跳相，会把发送端瑕疵误判为接收端丢帧（曾导致 M1 假 FAIL）。
4. **`rx.kernelBuffersCount = 32`** 可吸收偶发调度尖峰（实测 max 53 ms 被吸收）。
5. **首次 `step()` 有 ~0.7 s 一次性初始化延迟**——计入启动时间即可。
6. **Pluto 的 TX/RX 基带采样率必须一致**（AD9363 共享基带时钟），
   不一致报错 `Tx/Rx baseband sample rates do not match`。

### 5.3 M1 结果文件

`D:\13_MCP\GNSS\data\verify_20260806_183737.mat`（完整指标）与 `.png`（图形）。

---

## 6. 复现与验证步骤

```matlab
cd('D:\13_MCP\GNSS')
verifyPlutoStream                            % 默认 4 MSPS, 15 s（需回环线）
verifyPlutoStream('DurationSec', 30)         % 加长验证
verifyPlutoStream('Fs', 2.5e6, 'DurationSec', 10)  % 低采样率对照
```

自动化方式（无需打开桌面）：

```powershell
& 'D:\tools\matlab2022b\bin\matlab.exe' -batch "addpath('D:\13_MCP\GNSS'); verifyPlutoStream();"
```

判定：A/B/C 全部 PASS；D 仅对照。常见坑：回环线未接、测试音缓冲非整数周期、
USB 供电不足。

---

## 7. 已知问题与风险

| 问题 | 说明与对策 |
|---|---|
| 固件版本提示 | 0.38 vs 支持包测试 0.34；可继续用，异常时降级 |
| capture 速率限制 | 有效 ~1.5 MSPS，仅离线用；实时必须 step() |
| Pluto 在线不稳定 | 常被拔插；每次运行前 `findPlutoRadio()` 检测 |
| MATLAB 多实例 | -batch 与桌面实例可并存；曾遇到启动瞬时挂起（150 s 无输出），重试即恢复 |
| AGC 无信号源削波 | M1 A 项阈值已放宽（削波 <5%、DC <0.3） |
| 无 bias-T 收不到 GPS | 天线未供电；bias-T 到货前无法捕获真实卫星 |
| 沙箱限制 | 工作区内 `Remove-Item -Recurse -Force` 被策略拦截；`view_image` 不可用（DeepSeek 模型），图像验证用程序化手段（对象计数/文件大小/数值统计） |
| 文件编辑限制 | `apply_patch` 只能编辑工作区相对路径；`D:` 盘文件用 PowerShell 写入/复制 |
| 用户配置变更 | config.toml 已被用户改过（见 §2.1）；改动前先备份 |

---

## 8. 下一步计划（M2 优先）

### M2：捕获模块

- **输入**：`capture(rx, fs×5)` 采集 5 s L1 数据（离线调通用），或 `step()` 实时帧
- **算法**：FFT 并行码相位搜索——对 32 颗 PRN，搜索多普勒 ±10 kHz
  （步进 500 Hz），用 C/A 码 FFT 相关找峰值，参考 SoftGNSS `acquisition.m`
- **输出**：每颗卫星的码相位、多普勒频移、检测指标（峰值/噪声比）
- **本机辅助**：Satellite Communications Toolbox 提供 `gnssCACode`（C/A 码生成）、
  `gnssBitSynchronize`；Navigation Toolbox 提供 `gnssconstellation`
- **验收**：① 用合成信号（带延迟/多普勒）能正确捕获；② bias-T 到货接天线后
  能捕获 ≥4 颗真实卫星
- **文件规划**：`matlab/acquisition/acquisition.m` + 测试脚本

### M3：跟踪模块

- `step()` 连续流 + 10 ms 帧批处理，每通道 DLL（码环）+ PLL（载波环）
- 双缓冲：后台采集线程持续 `step()`，主线程处理
- 验收：C/N0 稳定、环路锁定、位同步

### M4：解码 + 定位 + 实时 GUI

- 50 bps 导航电文 → 子帧解析 → 星历 → 伪距 → 最小二乘定位
- GUI 参考 CommLab 的 `uifigure` 技术栈
- 实时显示：频谱、捕获网格、天空图、C/N0、电文、位置

---

## 9. 工作流约定

1. **GitHub 更新**：每次有进展 → 更新代码 + `CHANGELOG.md` + 相关文档 →
   `git add/commit/push`（仓库：`C:\Users\chang.su\Documents\GNSS-SDR-IN-MATLAB`，
   远端：`github.com/suchang-ccc/GNSS-SDR-IN-MATLAB`，public）
2. **与用户中文交流**，结论先行，文件用绝对路径链接
3. **测试先行**：核心改动后用 `matlab -batch` 跑验证脚本
4. **文件同步**：工作区 ↔ `D:\13_MCP\GNSS` 保持哈希一致
5. **设备操作谨慎**：涉及硬件（TX 发射、串口、SDR）前先与用户确认

---

## 10. 常用命令速查

```powershell
# MATLAB 自动化
& 'D:\tools\matlab2022b\bin\matlab.exe' -batch "addpath('D:\13_MCP\GNSS'); <命令>;"

# 设备检测
[System.IO.Ports.SerialPort]::GetPortNames()
Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -match 'Pluto' }
Test-Connection 192.168.2.1 -Count 2

# Git（仓库目录）
git -C 'C:\Users\chang.su\Documents\GNSS-SDR-IN-MATLAB' status -sb
git -C 'C:\Users\chang.su\Documents\GNSS-SDR-IN-MATLAB' add -A
git -C 'C:\Users\chang.su\Documents\GNSS-SDR-IN-MATLAB' commit -m "feat: ..."
git -C 'C:\Users\chang.su\Documents\GNSS-SDR-IN-MATLAB' push

# GitHub
gh repo view suchang-ccc/GNSS-SDR-IN-MATLAB
```

---

## 11. 参考资料

- [perrysou/GNSS_SDR](https://github.com/perrysou/GNSS_SDR)：SoftGNSS v3.0，
  MATLAB 离线接收机（采集→捕获→跟踪→定位），其 `initSettings.m` 关键参数：
  `dataType='int8'`、`IF=9.548e6`、`samplingFreq=38.192e6`、`codeFreqBasis=1.023e6`、
  `codeLength=1023`、`acqSearchBand=14e3`、`acqThreshold=2.5`
- [gnss-sdr/gnss-sdr](https://github.com/gnss-sdr/gnss-sdr)：C++ 实时接收机，
  原生 PlutoSDR 信号源（`plutosdr_signal_source`）；官方实时配置：
  `SignalSource.device_address=192.168.2.1`、`sampling_frequency=4000000`
- [MathWorks: GPS Receiver Acquisition and Tracking Using Pluto SDR](https://www.mathworks.com/help/satcom/ug/gps-receiver-acquisition-and-tracking-using-pluto-sdr.html)
- 本地官方示例：`D:\suchang\program\Pluto SDR\Matlab官方示例\`
- [Bilkent 便携 GNSS 接收机项目](https://ee.bilkent.edu.tr/fuar/2026/group_b6/project_page_b6.html)
- [NTNU 论文（Pluto+GPS 实测）](https://ntnuopen.ntnu.no/ntnu-xmlui/handle/11250/3155908)

---

## 12. 交接检查清单（给下一个会话）

- [ ] 阅读本文档
- [ ] 检查 Pluto 是否在线（`findPlutoRadio` / 串口 / ping）
- [ ] 确认 `D:\13_MCP\GNSS` 与工作区 `GNSS\` 同步
- [ ] 与用户确认：bias-T 是否已到货、天线是否接好
- [ ] 开始 M2 前与用户对齐验收标准
