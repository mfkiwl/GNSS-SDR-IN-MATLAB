# GNSS-SDR-IN-MATLAB 项目交接文档

> **交接日期**：2026-08-10（第四次交接，M1→M4 全部里程碑完成）
> **编写方**：Codex 会话（工作目录 `C:\Users\chang.su\Documents\Codex in Matlab`）
> **目的**：为下一个 Codex 会话提供完整、准确、经过实测验证的项目上下文，
> 覆盖 M1~M4 全部成果、硬件状态、代码资产、关键技术结论、复现步骤与
> 下一步计划，使新会话无需从零探索即可继续（真实卫星定位 / 性能增强）。
> **当前 Git HEAD**：`7e019cc`（main，与 GitHub `origin/main` 同步，19 个提交）

---

## 1. 项目概览

**目标**：用 MATLAB 驱动 ADALM-PlutoSDR 完成 GPS L1 (1575.42 MHz) 接收机
全链路：**采集 → 捕获 → 跟踪 → 导航电文解码 → 星历 → 伪距 → 定位 →
实时显示**。

**当前阶段（全部核心里程碑 PASS）**：

| 里程碑 | 内容 | 状态 |
|---|---|---|
| M1 | PlutoSDR 连续采集链路（4 MSPS、无丢帧） | ✅ PASS（2026-08-06） |
| M2 | 捕获：32 PRN FFT 并行码相位搜索 | ✅ PASS（离线 6/6 + 硬件链路） |
| M2.5 | TX 合成 GPS + 50 bps 电文 + 连续子帧收发 | ✅ PASS（2026-08-07） |
| M3 | 跟踪：DLL/PLL 多通道（Synthetic + 硬件闭环） | ✅ PASS（2026-08-07） |
| M3.5 | 官方 RINEX 星历电文链路（MathWorks 官方编码） | ✅ PASS（Synthetic + 硬件） |
| M4.1 | 星历解析 26 字段 + 卫星 ECEF 位置 | ✅ PASS（2026-08-07） |
| M4.2 | 多星定位（伪距 + 最小二乘） | ✅ PASS（Synthetic 218 m / **硬件 133 m**） |
| M4 GUI | uifigure 实时显示 + 一键演示 + 原始电文输出 | ✅ 完成（2026-08-10） |

**唯一未完成的外部依赖**：M2 验收标准②"捕获 ≥4 颗真实卫星"——原因是
**有源天线未供电（bias-T 未到货）**。当前全部硬件验证通过 **TX 发射模拟
卫星信号 + RX 有源天线（无源接收）** 完成；接收链路与算法已就绪，只差
真实卫星（详见 §9 下一步）。

**总体架构（已全部实现）**：

```text
PlutoSDR (L1 1575.42 MHz)
   │  step() 连续流（实时） / capture() 大块采集（离线）
   ▼
前端采集（plutoGnssFrontEnd.m，M1）
   ▼
捕获（acquisition.m：FFT 圆周相关，32 PRN × ±10 kHz）
   ▼
跟踪（tracking.m：DLL + PLL 多通道，C/N0，位同步）
   ▼
电文解码（demodulateNavBits / gnssSubframeDecode：前导码+奇偶校验+BPSK 极性消除）
   ▼
星历（gnssEphDecode：子帧 1/2/3 → 26 字段）
   ▼
卫星位置（satellitePosition.m：IS-GPS-200 §20.3.3.4）
   ▼
伪距（gnssPseudorange.m：亚毫秒比特边界解析）
   ▼
定位（leastSquaresPosition.m：最小二乘，位置+钟差，GDOP）
   ▼
实时显示（gnssLiveGui.m：uifigure C/N0/天空图/电文/位置）
```

**TX 侧链路**（用于闭环验证）：官方 RINEX 星历（`readRinexNav`/`rinexread`）
→ 官方 Helper 编码（`rinexToGpsCfg` → `HelperGPSNAVDataEncode`）→ 多星叠加
基带（`generateMultiSatTxBuffer`）→ Pluto TX。

---

## 2. 环境与工具链（已配置完毕，勿重复配置）

| 软件 | 版本/路径 | 说明 |
|---|---|---|
| MATLAB | R2022b 9.13.0.2049777，`D:\tools\matlab2022b` | 110 个工具箱 |
| ADALM-Pluto 支持包 | Communications Toolbox Support Package for ADALM-Pluto Radio | `findPlutoRadio`/`sdrrx`/`sdrtx` 可用 |
| Satellite Communications Toolbox | `gnssCACode`/`gnssBitSynchronize` | C/A 码生成 |
| Navigation Toolbox | `rinexread`（仅 RINEX 3）、`gnssconstellation` | RINEX 3 读取 |
| 官方 Helper（关键） | `D:\tools\matlab2022b\examples\satcom\main\` | `HelperGPSNavigationConfig`/`HelperGPSNAVDataEncode`/`HelperGPSLNAVDataDecode` 等，**须 addpath** |
| Git for Windows | 2.55.0，`C:\Program Files\Git` | 已加入 PATH；**自带 `gzip.exe`（解 .Z 用）** |
| GitHub CLI | 2.97.0，已登录 `suchang-ccc`（scope: repo） | 可推送 |
| Codex 桌面版 | 已安装 | 使用 `~/.codex/config.toml` |
| MATLAB MCP Server | v0.11.2，`C:\Users\chang.su\.matlab\agentic-toolkits\bin\matlab-mcp-core-server-win64.exe` | Codex↔MATLAB 桥接 |

### 2.1 Codex 配置（`C:\Users\chang.su\.codex\config.toml`）

```toml
model = "deepseek-v4-flash"
model_provider = "deepseek"
model_reasoning_effort = "high"

[mcp_servers.matlab]
command = 'C:\Users\chang.su\.matlab\agentic-toolkits\bin\matlab-mcp-core-server-win64.exe'
args = ['--matlab-root', 'D:\tools\matlab2022b', '--matlab-display-mode', 'desktop',
        '--initial-working-folder', 'D:\suchang\program\Pluto SDR']
tool_timeout_sec = 600
env_vars = ['WINDIR']
```

- 备份：`C:\Users\chang.su\.codex\config.toml.bak-20260803`
- 用户添加了 `[sandbox_workspace_write] network_access = true`
- **主模型为 DeepSeek（deepseek-v4-flash），不支持原生图像输入**，见 §2.2

### 2.2 图像查看（重要）

当前模型不支持 `view_image`。**图像验证统一使用已安装的
`deepseek-vision-skill`**：

```powershell
node "C:\Users\chang.su\.codex\skills\deepseek-vision-skill\scripts\describe-image.js" "路径\图.png"
node "C:\Users\chang.su\.codex\skills\deepseek-vision-skill\scripts\describe-image.js" --prompt "具体问题" "路径\图.png"
```

- API key 已配置在 skill 目录 `config.json`（Zhipu GLM-4V-Flash）
- 该脚本有 provider 白名单检查（仅 deepseek-v4-flash/pro），当前配置满足
- 程序化验证替代方案：`rms`、`max(abs)`、对象计数、`Get-FileHash`、数值统计

### 2.3 用户自有目录（勿改动）

`D:\suchang\program\Pluto SDR\`：用户自建 Pluto 工作目录（2026-07-22 起），
含用户自写回环脚本（FM/QAM）、官方示例、CommLab 副本。**不要改动**。

---

## 3. 硬件状态

| 硬件 | 状态 |
|---|---|
| ADALM-PlutoSDR（序列号 `104473023196000bf5ff1a00aae12c3ca8`） | ✅ 在线（COM3 + RNDIS + ping 192.168.2.1 通） |
| TX 天线 | ✅ 无源拉杆天线（接 Pluto TX 口，拉到约 5 cm = 1/4 波长） |
| RX 天线 | ✅ 有源 GPS 天线（接 Pluto RX 口；**未接 bias-T，LNA 不工作、无源接收**） |
| Bias-T 偏置器 | ⬜ **待购**（真实卫星捕获的前提，见 §3.2） |
| TX→RX 回环线（SMA 短线） | ✅ 在用户手边（M1/M2 回环验证用过） |

### 3.1 识别特征

- USB 串口：`PlutoSDR Serial Console (COM3)`（COM 号可能变化）
- 网络：`PlutoSDR USB Ethernet/RNDIS Gadget`，本机 192.168.2.10 ↔ Pluto 192.168.2.1
- 固件 0.38（支持包测试版本 0.34，启动有警告，不影响使用）
- **代码中一律用 `findPlutoRadio()` 自动检测设备 ID，不硬编码 `usb:0`**

### 3.2 Bias-T 选购要点（给用户/采购）

- 频段覆盖 1.2–1.6 GHz（含 1575.42 MHz），典型"10 MHz–6 GHz"宽带产品均可
- 馈电 3.3 V 或 5 V（按天线标称），电流余量 ≥100 mA
- 三端口：RF+DC 接天线、RF 接 Pluto（直流隔离）、DC 接电源，防直流倒灌
- 插损 ≤1 dB；淘宝搜"GPS 偏置器 / bias-tee 5V"；天线放窗边、天顶开阔处

### 3.3 实测功率标定结论（天线场景）

- 天线路径损耗约 **−44 dB**（相对回环线直连）
- RX 手动增益 20 dB 时噪声底 RMS ≈ 0.0005
- **单星档位**（M3/M3.5 硬件验证）：TX −65 dB / 幅度 0.1 / RX 20 dB →
  CN0 35.9~39.1 dB-Hz（2026-08-10 复测 CN0 39.1，环境稳定）
- **多星档位**（M4.2 硬件定位，2026-08-10 实测）：TX **−60 dB** / 每星
  幅度 0.1（6 星叠加峰值 0.6，`Normalize=false`）/ RX 20 dB → 单星 CN0
  **43.5~44.5 dB-Hz**
- 回环线档位：TX −89.75 dB / 幅度 0.034 / RX 10 dB
- 强信号警示：TX −30 dB 时 32 PRN 全部越捕获门限（C/A 互相关伪峰）

---

## 4. 代码资产清单

### 4.1 位置总览（三处，内容按需同步）

| 位置 | 用途 |
|---|---|
| `C:\Users\chang.su\Documents\Codex in Matlab\GNSS\`（工作区） | **开发主副本**（apply_patch 可编辑） |
| `D:\13_MCP\GNSS\`（MATLAB 运行目录） | MATLAB 实际运行位置（含 `data\` 产物） |
| `C:\Users\chang.su\Documents\GNSS-SDR-IN-MATLAB\`（Git 仓库） | GitHub 仓库本地副本，`main` 分支 |

**同步规则**：工作区与 `D:\13_MCP\GNSS` 内容一致（`Copy-Item` + SHA256 校验）；
Git 仓库结构独立（`matlab/frontend`、`matlab/acquisition`、`matlab/tracking`、
`matlab/commlab`），每次进展 commit + push。**当前 30 个 .m 全部 SHA256 一致**。

### 4.2 工作区文件清单（30 个 .m，均为 UTF-8 无 BOM）

**基础/前端（M1）**：

| 文件 | 功能 |
|---|---|
| `gnssSettings.m` | 全局参数：中心频率、采样率、C/A 码参数 |
| `plutoGnssFrontEnd.m` | L1 采集：检测 → sdrrx → capture → 存 .mat/.bin |
| `verifyPlutoStream.m` | M1 验证（A 健康/B step 流/C 回环音/D capture 对照） |

**捕获/合成/电文（M2/M2.5）**：

| 文件 | 功能 |
|---|---|
| `acquisition.m` | 捕获主函数：FFT 圆周相关，32 PRN × ±10 kHz；参数 `IntegrationMs`/`NonCoherentN`/`DopplerStep`/`Threshold`/`PRNList` |
| `generateSyntheticGpsSignal.m` | 合成信号生成器（延迟/多普勒/C-N0 可控） |
| `runAcquisitionTests.m` | 捕获离线回归测试（6 项，6/6 PASS） |
| `generateGnssTxBuffer.m` | TX 基带缓冲（整数码周期，可含 50 bps 电文；`Amplitude`/`NavBits`） |
| `plutoGnssTx.m` | 独立 TX 发射脚本 |
| `verifyGnssLoopback.m` | 回环/天线闭环验证（TX+RX+捕获+判定） |
| `demodulateNavBits.m` | 50 bps 电文解调（精对齐、逐 ms 剥码、位同步、符号判决） |
| `verifyGnssNavData.m` | 电文收发验证（40 位测试序列，0 错误） |

**子帧/奇偶（M2.5，M3.5 已修复 ICD 合规）**：

| 文件 | 功能 |
|---|---|
| `gpsWordParity.m` | 30 位字奇偶校验（ICD-GPS-200 §20.3.5.4；**含 HOW/字 10 特例与 D30 位反转**，wordNumber 参数） |
| `generateGpsSubframe.m` | 完整子帧生成（TLM/HOW/8 数据字；`meta.dataWords` 为实际发送逻辑位） |
| `gnssBitEdgeDetect.m` | 比特边缘检测（能量法 + 翻转直方图法） |
| `gnssSubframeDecode.m` | 子帧同步（前导码+奇偶校验+BPSK 极性消除）+ 字段解码 + 参考对比 |
| `verifyGnssContinuousNav.m` | 连续子帧收发验证（Synthetic/硬件两模式） |

**跟踪（M3）**：

| 文件 | 功能 |
|---|---|
| `tracking.m` | DLL+PLL 多通道跟踪、C/N0、位同步、锁定判定；参数 `PRNList`/`PllBandwidth`/`DllBandwidth`/`CorrSpacing`/`ReferenceBits` |
| `verifyGnssTracking.m` | M3 验证（Synthetic/硬件双模式，端到端子帧对比） |

**官方星历（M3.5）**：

| 文件 | 功能 |
|---|---|
| `readRinexNav.m` | RINEX 2.11 GPS 广播星历解析器（`rinexread` 不支持 2.x；自动跳过零占位星历） |
| `rinexToGpsCfg.m` | RINEX（2/3）→ 官方 HelperGPSCEIConfig → HelperGPSNAVDataEncode LNAV 编码；自动按历元算 TOW |
| `verifyOfficialEphemeris.m` | 官方电文验证（33 字段交叉验证 + Synthetic/硬件闭环；`Synthetic`/`MsgPRN` 参数） |

**M4.1 星历/卫星位置**：

| 文件 | 功能 |
|---|---|
| `gnssEphDecode.m` | 子帧 1/2/3 → 星历 26 字段（位宽/缩放/符号与官方解码器一致） |
| `satellitePosition.m` | 星历 → 卫星 ECEF 位置 + 钟差（IS-GPS-200 §20.3.3.4；输入角度为半周） |
| `verifyGnssEphDecode.m` | M4.1 验证（阶段 A 确定性 + 阶段 B 合成闭环；字段对比 + 32 星物理校验） |

**M4.2 定位**：

| 文件 | 功能 |
|---|---|
| `generateMultiSatTxBuffer.m` | 多星叠加 TX 缓冲（每星独立延迟/幅度/多普勒；`Normalize` 开关） |
| `gnssPseudorange.m` | 跟踪+解码子帧 → 伪距（亚毫秒比特边界解析；返回 `[rho, eSf]`） |
| `leastSquaresPosition.m` | 伪距最小二乘定位（位置+钟差，高斯-牛顿迭代，GDOP） |
| `verifyGnssPositioning.m` | M4.2 定位验证（Synthetic/硬件双模式；参数 `NumSats`/`RefLat`/`RefLon`/`AcqIntegrationMs`/`TxGain`/`TxAmplitude`） |

**M4 GUI/演示**：

| 文件 | 功能 |
|---|---|
| `demoGnssPositioning.m` | 一键演示：跑全链路 + 5 幅可视化 + 总览图 + 控制台原始电文输出（`MsgPRN` 选星） |
| `gnssLiveGui.m` | uifigure 实时界面：C/N0 曲线/天空图/解码电文/定位结果；合成/硬件/载入结果三模式；`SnapshotFile` 无头截图 |

**文档**：`README_GNSS.md`（项目 README）、`README_M1.md`。

### 4.3 Git 仓库结构与状态

```text
GNSS-SDR-IN-MATLAB/
├── docs/
│   ├── project_overview.md / M1~M3_tracking.md / NavData / ContinuousNav
│   ├── OfficialEphemeris_verification.md   # M3.5 官方星历电文
│   ├── M4_ephemeris.md / M4_positioning.md # M4.1 / M4.2（含硬件附录 A）
│   ├── M4_summary.md                       # M4 阶段总结（推荐先读）
│   ├── HANDOFF.md                          # 本文件副本
│   └── images/                             # 各验证实验图
├── matlab/
│   ├── frontend/  acquisition/  tracking/  commlab/
├── data/                                   # auto2190.26n + RINEX3（gitignore 例外）
├── CHANGELOG.md（0.1.0 ~ 0.14.0）
├── README.md / LICENSE / .gitignore
```

**当前状态**：HEAD `7e019cc`，main 与 origin/main 同步（19 个提交，远端
71 个文件；matlab/acquisition 25 个 .m）。仓库干净。

关键提交：

| 提交 | 内容 |
|---|---|
| `60f1ba5` | M3 跟踪验证 PASS（Synthetic + 硬件） |
| `0096d2f` | 官方 RINEX 星历电文链路 + 奇偶链 ICD 修复 |
| `7ad007a` | 官方子帧 1 硬件闭环 PASS |
| `19b0fb4` | M4.1 星历解析 + 卫星位置 |
| `1fa38be` | M4.2 多星定位 PASS（218 m） |
| `9b16aad`/`7f84e20` | 一键演示 + 原始电文输出 |
| `d8be4d9` | **M4.2 硬件多星定位 PASS（133 m）** |
| `50bc3fa` | 实时 GUI |
| `7e019cc` | M4 阶段总结报告 |

---

## 5. 已验证成果（按阶段，附实测数据与产物）

### 5.1 M1：连续采集链路（2026-08-06）

- 4 MSPS / 15 s 流：帧间隔稳态 9.99 ms（≤12 ms）、p95 11.96 ms、相位跳变
  0 次、回环音 SNR 81 dB
- 20 s 长稳态：1935 帧、有效吞吐 3.869 MSPS、首帧延迟 678.7 ms（一次性）
- 产物：`data\verify_20260806_183737.mat/.png`
- **核心结论：实时必须用 `step()`；`capture()` 循环帧间不连续**

### 5.2 M2：捕获模块离线测试（6/6 PASS）

| 测试 | 场景 | 结果 |
|---|---|---|
| T1 | PRN5，码相位 876，多普勒 +2300 Hz，C/N0=45 | metric 25.4，参数精确 |
| T2 | PRN12，C/N0=35（5 ms 相干 ×10） | metric 16.4，参数精确 |
| T3 | 纯噪声 32 PRN 全扫描 | 最大 metric 3.54，零虚警 |
| T4 | 双星 PRN3+17 | 两颗全捕获 |
| T5 | 码相位回绕（2495/2500） | metric 9.6 |
| T6 | 相干积分路径（IntegrationMs=5） | metric 14.5 |

门限标定：8 组随机种子纯噪声最大指标 3.39–3.62，**默认门限 6，余量约 1.7×**。

### 5.3 回环线验证（TX 合成 GPS → RX 捕获）

- TX −89.75 dB / 幅度 0.034 / RX 10 dB：仅命中 PRN5（metric 69，多普勒
  +0.0 Hz），其余 PRN 噪声级
- 强信号档（TX −30 dB）32 颗 PRN 全部越门限——C/A 码互相关伪峰（已知现象）
- 产物：`data\gnss_loopback_20260807_155343.mat`

### 5.4 天线传输验证（拉杆 TX → 有源 RX，无 bias-T）

- TX −65 dB / 幅度 0.1 / RX 20 dB：仅命中 PRN5（metric 37.7，多普勒
  +0.0 Hz），其余 PRN 3.4–3.6，领先度 10.4×
- 证明无 bias-T 时天线链路仍可验证（发射信号比真实卫星强 ~80 dB）
- 产物：`data\gnss_loopback_20260807_160409.mat`

### 5.5 50 bps 导航电文收发验证

- 40 位测试序列（TLM 前导码 `10001011` 开头），TX −65 dB
- 捕获 PRN5（metric 15.8，多普勒 0 Hz）；解调 **100 位 0 比特错误**
- 产物：`data\gnss_navdata_20260807_162158.mat/.png`

### 5.6 连续 GPS 子帧收发验证

- 发射 1 个完整子帧（300 位 = 6 s）持续重复；`step()` 连续流采集 12 s
- 比特边缘检测：最优偏移 18 ms，边界翻转率 0.44；子帧边界同步：起点位
  233，BPSK 极性消除（极性=取反）
- 解码：TOW=80000、子帧号=1、TLM=010101；**300 位 0 比特错误**
- 产物：`data\gnss_continuous_20260807_164313.mat`
- 报告：`docs/ContinuousNav_verification.md`

### 5.7 M3 跟踪模块验证（DLL + PLL）

- **Synthetic PASS**：8 s 合成信号 +1200 Hz/码相位 777/C/N0=45；捕获
  metric 134；锁定 CN0 43.2（真值 45）、频率误差 0.03 Hz、码相位误差
  0.01 采样；610 位 **0 误码**；子帧解码 1/1
- **硬件闭环 PASS**（TX −65 dB / RX 20 dB，12.5 s step 流）：捕获 metric
  18.2、领先度 5.1×；锁定 CN0 35.9、码相位 std 0.020 采样、频率误差
  0.11 Hz；609 位 **0 误码**；子帧解码 1/1
- 产物：`data\gnss_tracking_20260807_173214.mat`（硬件）/ `_173105.mat`
- 报告：`docs/M3_tracking.md`；代码在 `matlab/tracking/`

### 5.8 官方 RINEX 星历电文验证（M3.5）

- **官方数据源**：Garner UCSD `auto2190.26n`（RINEX 2.11，481 条记录 /
  32 PRN）+ BKG IGS `BRDC00WRD_R_20262190000_01D_MN.rnx`（RINEX 3 组合）；
  CDDIS 需 Earthdata 认证故用 IGS 镜像（下载链接见 §11）
- **链路**：`readRinexNav`/`rinexread` → `rinexToGpsCfg` →
  MathWorks 官方 `HelperGPSNAVDataEncode` → TX/RX 闭环
- **Synthetic PASS**：编码一致性 33/33 字段、奇偶 30/30 字、捕获精确命中、
  跟踪 CN0 43.8、**0/915 误码**、子帧解码全匹配
- **硬件闭环 PASS**（TX −65 dB，官方子帧 1，12.5 s）：捕获 metric 26.9 /
  领先度 7.6、CN0 36.7、**0/609 误码**、子帧 TOW=75603 全字段匹配
- **重大修复：自研奇偶链 ICD 不合规**——`gpsWordParity` 补全 HOW（字 2）
  与字 10 的 D29/D30=0（反馈重置）和 D30 位反转；修复后自研链与官方
  Helper 链四向逐位互操作，M3/M2.5 回归 PASS
- 产物：`data\official_ephemeris_20260807_181520.mat/.png`（Synthetic）、
  `_182300.mat/.png`（硬件）；报告：`docs/OfficialEphemeris_verification.md`

### 5.9 M4.1 星历解析 + 卫星位置

- **链路**：官方 RINEX/编码 → TX 900 位 → 捕获 → 跟踪 → 子帧解码 →
  `gnssEphDecode`（26 字段）→ `satellitePosition`
- **阶段 A（确定性）PASS**：26/26 字段与官方 RINEX 量化容差内一致；
  **32 星整周期对径比 0.9963±0.0041**（ECEF 下开普勒传播的独立物理验证）
- **阶段 B（24 s 合成闭环）PASS**：捕获 metric 125.5、跟踪 CN0 43.9、
  **0/1185 误码**，星历还原 26/26，卫星位置 r=2.642e7 m 合理
- 产物：`data\gnss_eph_decode_20260807_183432.mat`；
  报告：`docs/M4_ephemeris.md`

### 5.10 M4.2 多星定位（Synthetic）

- **方法**：官方 RINEX 星历在统一 T_sf=469764 s 算 6 星位置，以参考点
  （上海 31.2304N/121.4737E）到各星真实距离为伪距注入多星 TX；接收端
  全链路解算后与参考点对比
- **PASS**：6/6 星捕获+跟踪（CN0 40.8-41.8，0 误码）、星历 26 字段、
  伪距 vs 注入真值 **6.5 m**、位置距参考点 **217.9 m**（GDOP 7.7，
  残差 RMS 38.5 m）
- 产物：`data\gnss_positioning_20260807_190418.mat`；
  报告：`docs/M4_positioning.md`

### 5.11 M4.2 硬件多星定位（2026-08-10）

- **链路**：TX 6 星叠加（子帧 1，6 s 缓冲，增益 **−60 dB**）→ 有源天线
  RX 12.5 s → **1 ms 捕获** 6/6 → 多通道跟踪（CN0 43.5~44.5）→ 伪距 →
  最小二乘（星历用 RINEX 已知数据，因硬件仅发子帧 1）
- **PASS**：伪距 vs 注入真值 **4.1 m**，定位误差 **132.7 m**（参考点上海，
  GDOP 7.7，残差 RMS 20.9 m）
- **关键排障**：5 ms 相干捕获对周期码有 ±1 ms 多周期歧义，多星/弱信号下
  部分卫星锁错周期（码相位偏 500~1000 采样）→ 硬件多星捕获改 **1 ms**
  后 6 星码相位全部精确；TX 增益 −60 dB 保证单星 CN0 ~43
- 演示产物：`data\demo_gnss_positioning_20260810_105452_*.png`；
  报告：`docs/M4_positioning.md` 附录 A

### 5.12 M4 实时显示 GUI + 一键演示

- `gnssLiveGui.m`：uifigure 四面板（C/N0 动态曲线/天空图/解码电文/定位
  结果）+ 播放控制（播放/暂停/滑杆）；合成 / 硬件 / 载入结果三模式；
  `SnapshotFile` 无头截图。实测载入硬件结果回放正常（6 星曲线、
  TOW=78295、定位 PASS 132.7 m）
- `demoGnssPositioning.m`：一键跑全链路 + 6 张可视化 + 控制台输出解码
  **原始电文**（300 位比特 + TLM/HOW/数据字 + 星历 26 字段，含 BPSK
  极性校正；`MsgPRN` 选星）
- GUI 截图：`docs/images/gnss_live_gui_20260810.png`

---

## 6. 关键技术结论与踩坑记录（核心，务必阅读）

### 6.1 MATLAB 语言/工具箱

1. **函数调用跨行续行必须写 `...`**：R2022b 行尾逗号不自动续行；方括号内
   续行例外。
2. **`gnssCACode` 返回 int8**：做算术前必须 `2*double(ca)-1`，否则与复数
   `.*` 报"不支持复整数算术运算"。
3. **结构数组字段裸用是逗号分隔列表**：`acq.results.PRN` 不能直接参与运算，
   必须 `[acq.results.PRN]` 拼接。
4. **行/列向量广播陷阱**：列向量与行向量 `==` 会隐式扩展成矩阵；解调
   比特流统一用行向量。
5. **`struct()` 遇 cell 值会展开成结构数组**：`struct('a', cellArr)` 生成
   size(cellArr) 的结构数组；要存 cell 单字段须 `struct('a', {cellArr})`
   （gnssLiveGui 实测踩坑）。
6. **MATLAB `+` 会把零虚部折叠成实数**：`zeros + complex(x,0)` 结果是
   real（isreal=1），而 Pluto TX 要求 complex 输入；须显式
   `complex(buf, 0)`（generateMultiSatTxBuffer 实测踩坑）。
7. **cell 与字符串比较须用 `strcmp`**：`cell == 's'` 报错。
8. `.m` 文件 UTF-8 无 BOM；MATLAB 默认按 UTF-8 读取，中文注释/字符串可用；
   **控制台输出偶发乱码**，关键输出用 ASCII 标签更稳。

### 6.2 捕获算法（M2/M4）

9. **FFT 相关必须是圆周相关**：FFT 长度 = 块长（1 ms 码周期），不能零填充
   做线性相关——码相位接近码周期末尾时线性相关无法回绕对齐。
10. **码相位语义**：从块起点到下一个码周期起点的延迟（采样点，1-based），
    直接作为跟踪初始值。
11. **多普勒格点量化**：500 Hz 步进 → 估计误差 ±250 Hz；弱信号
    （C/N0<38）须 `IntegrationMs>1` 相干积分 + 缩小 `DopplerStep`
    （5 ms 相干配 100 Hz 步进，C/N0=35 可捕获）。
12. **检测门限 6**（峰值/噪声均值，剔除峰 ±2 点）；纯噪声 8 种子最大
    3.39–3.62。
13. **强信号互相关伪峰**：C/N0 ≥ 60 dB-Hz 时 32 PRN 全部越门限；判定用
    "目标指标 ≥ 3× 次高"（领先度）。
14. **⚠️ 5 ms 相干捕获的多周期歧义（M4.2 硬件排障核心）**：圆周相关对
    周期码有 ±1 ms 等高峰；多星/弱信号下部分卫星锁错周期（码相位偏
    500~1000 采样，DLL 牵引范围仅 ~1 chip 必失锁）。**硬件多星捕获须用
    `IntegrationMs=1`**（实测 6 星码相位全部精确）；合成模式 5 ms 无此
    问题（无射频噪声）。

### 6.3 PlutoSDR 硬件（TX/RX）

15. **TX `Gain` 范围 0 ~ −89.75 dB，0 = 最大输出**（与直觉相反）；测试
    从衰减档起步（初测 `Gain=0` 削波 79%）。
16. **TX/RX 采样率必须一致**（AD9363 共享基带时钟），否则报
    `Tx/Rx baseband sample rates do not match`。
17. **`transmitRepeat` 缓冲与 `capture` 单帧上限均为 2^24 采样**：2.5 MSPS
    下 TX 最多 1 个子帧（6 s = 15M 采样）；长采集必须用 `step()` 连续流。
18. **TX 缓冲必须整数个码周期**（1 ms = 2500 采样），否则每周期跳相；
    电文缓冲须整数个 20 ms 比特。
19. **`kernelBuffersCount=32`** 吸收偶发调度尖峰；首次 `step()` 有
    ~0.7 s 一次性初始化延迟。

### 6.4 电文/子帧处理

20. **BPSK 180° 极性模糊**：必须由前导码 + 奇偶校验消除极性；
    `gnssSubframeDecode` 对原样/取反两种极性都验证；**展示原始比特时也
    须做极性校正**（demo/GUI 已处理）。
21. **位同步**：能量法弱信号区分度低（峰/次峰 ~1.0）；**翻转直方图法**
    （`real(c(i)*conj(c(i+1))) < 0`）更可靠，正确对齐翻转率约 0.5。
22. GPS 电文字结构：30 位/字 × 10 字 = 300 位/子帧 = 6 s；TLM 前导码
    `10001011`；HOW 的 TOW 指**下一子帧**起点（本子帧起点 =
    (TOW−1)×6 s）。
23. **⚠️ ICD 奇偶链特例（M3.5 修复）**：HOW（字 2）与字 10 的 D29/D30
    恒为 0（反馈重置），且前字 D30=1 时本字 bit1..24 取反（D30 位反转）。
    自研链与 MathWorks 官方 Helper 链现已逐位互操作。

### 6.5 M3 跟踪

24. **二阶环路滤波器必须用位置式 PI**（`f = f0 + Kp*e + Ki*sum(e)`）：
    增量式会把比例项积分成双积分器（实测发散到 −55 kHz）；位置式从
    40 Hz 离格频偏 ~1 s 内可靠牵入。
25. **Costas 鉴别器模 π**：牵入范围仅环路带宽量级；初值必须来自捕获
    （DopplerStep=100 → 误差 ≤50 Hz）；高动态后续应加 FLL 辅助。
26. **C/N0 的 20 ms 窗口必须按位同步对齐**：跨比特翻转时窄带功率被抵消，
    C/N0 低估 ~25 dB（实测 35.9 → 11.2 dB-Hz，比特仍 0 误码）。
27. **端到端子帧解码需 ≥ 600 位跟踪比特**（12 s 采集）；参考匹配须测
    双极性（`bits==1-ref` 后 100%）。

### 6.6 M4 星历/定位（2026-08-07/10 新增）

28. **⚠️ 亚毫秒比特边界解析（伪距精度核心）**：子帧起点 = 比特边界 =
    码相位零点，位于毫秒网格的分数位置。整数 ms 比特同步锚定子帧产生
    每星 ±1 ms（300 km）伪距歧义（初版位置误差 1776 km）。解法：
    能量曲线抛物线插值得亚毫秒比特相位 b_true → 子帧起点分数毫秒
    P = skipMs + b_true + (syncIndex−1)×20 → 码相位零点采样
    **e_sf = floor(P)×msLen + codePhase(floor(P)+1)**。修复后伪距一致
    6.5 m（合成）/ 4.1 m（硬件）。
29. **统一锚定子帧 1**：不同子帧起点差 6-12 s（卫星位移 ~50 km）会造成
    伪距几何不一致；所有星须统一锚定子帧 1（TOW 基准一致）。
30. **采集时长保证完整子帧**：900 位场景（Synthetic）需有效比特 ≥1199
    （28 s 采集）；300 位场景（硬件）12.5 s 足够。
31. **ECEF 60 s 位移可达 ~350 km**：轨道运动（~231 km/60 s）+ 地球自转
    视运动（≤1925 m/s）叠加；判定按 [100,400] km 并附加轨道半径稳定性
    （60 s 内 <5 km）。
32. **整周期对径是 ECEF 下的强校验**：GPS 周期 ≈ 半个恒星日，一个周期后
    地球自转 ~180°，ECEF 位置对径（≈2r）——32 星实测 0.9963±0.0041。
33. **星历外推超出 2 h 拟合区间会失真**：PRN13/32 在 Toe 外 4 h 处出现
    663 km 伪近星；星座校验须在每星自身 Toe 处计算；选星须 |Toe−T_sf|
    ≤ 2 h。
34. **ICD 字段二补码回绕**：RINEX 的 M0/DeltaN 等超出字段位宽时按二补码
    回绕（物理等效），比对须按字段范围取模（M0 模 2 半周、DeltaN 模
    2^-27 等）。
35. **多星重复周期歧义是公共时标误差**（各星缓冲同相位），被最小二乘
    钟差吸收，不影响位置；但仍须检查各星锚定在同一重复周期内。
36. **RINEX 2 角度单位为半周（semi-circle）**，与 IS-GPS-200 自然单位
    一致，可直接填入官方 CEI 配置；`satellitePosition` 内部 ×π 转弧度。

---

## 7. 复现与验证步骤

### 7.1 离线测试（无需硬件）

```matlab
cd('D:\13_MCP\GNSS')
addpath('D:\tools\matlab2022b\examples\satcom\main');   % 官方 Helper

runAcquisitionTests                          % M2 捕获 6/6
verifyGnssContinuousNav('Synthetic', true)   % 连续子帧离线
verifyGnssTracking('Synthetic', true)        % M3 跟踪离线
verifyOfficialEphemeris('Synthetic', true)   % M3.5 官方星历（合成）
verifyGnssEphDecode                          % M4.1 星历解析（阶段 A+B，~1 min）
verifyGnssPositioning                        % M4.2 多星定位（Synthetic，~1.5 min）
```

### 7.2 演示 / GUI（推荐先看现象）

```matlab
demoGnssPositioning('MsgPRN', 11)            % 全链路 + 6 图 + 原始电文
gnssLiveGui                                  % 实时 GUI（先跑定位）
gnssLiveGui('LoadFile', 'D:\13_MCP\GNSS\data\gnss_positioning_20260810_105452.mat')
```

### 7.3 硬件验证（需 TX 发射确认；低功率短时，1575.42 MHz 为受保护频段）

```matlab
verifyPlutoStream                            % M1，需回环线
verifyGnssLoopback('TxGain', -89.75, 'TxAmplitude', 0.034, 'RxGain', 10)  % 回环线
verifyGnssLoopback                           % 天线场景（默认 TX -65）
verifyGnssNavData                            % 50 bps 电文
verifyGnssContinuousNav                      % 连续子帧（12 s）
verifyGnssTracking                           % M3 跟踪（12.5 s）
verifyOfficialEphemeris('Synthetic', false, 'CaptureSec', 12.5)  % 官方子帧 1
verifyGnssPositioning('Synthetic', false)    % M4.2 硬件多星定位（默认 1 ms 捕获 + TX -60）
demoGnssPositioning('Synthetic', false, 'MsgPRN', 11)            % 硬件演示
```

PowerShell 自动化（无需打开桌面）：

```powershell
& 'D:\tools\matlab2022b\bin\matlab.exe' -batch "addpath('D:\13_MCP\GNSS'); addpath('D:\tools\matlab2022b\examples\satcom\main'); <命令>;"
```

> **MATLAB -batch 注意**：每次启动约 10–30 s；函数名不能以 `_` 开头；
> 长脚本内联注意 `%` 注释会吞掉后续内容；工具调用超时设 600~1200 s。

---

## 8. 已知问题与风险

| 问题 | 说明与对策 |
|---|---|
| bias-T 未到货 | 真实卫星捕获（M2 验收②）阻塞；当前用 TX 合成信号替代验证 |
| 室内多径 | 天线场景每比特能量波动大（min/max 差约 12 dB）；20 ms 积分余量足够 |
| 多星捕获歧义 | 5 ms 相干捕获在多星/弱信号下会锁错周期；硬件多星已固化 1 ms（§6.2-14） |
| 硬件仅发子帧 1 | TX 缓冲 6 s 上限；定位时星历用 RINEX 已知数据（完整 5 子帧发射见 §9） |
| 伪距注入量化 | 延迟按采样点（120 m）量化，定位误差 ~100-200 m 级；亚采样注入可提升 |
| 强信号互相关 | C/N0 ≥ 60 dB-Hz 时 32 PRN 虚警；测试用领先度判定 |
| 固件版本提示 | 0.38 vs 支持包测试 0.34；可继续用，异常时降级 |
| Pluto 在线不稳 | 常被拔插；每次运行前 `findPlutoRadio()` 检测 |
| MATLAB 多实例 | -batch 与桌面可并存；曾遇启动瞬时挂起（150 s），重试即恢复 |
| view_image 不可用 | 用 deepseek-vision-skill（§2.2） |
| 控制台中文乱码 | MATLAB 输出偶发乱码；关键数据用 ASCII 标签 |
| 内存占用 | Synthetic 28 s 信号 ~60M 采样（~1 GB）+ 多星缓冲，峰值 ~2.5 GB；内存紧张时减 NumSats/时长 |

---

## 9. 下一步计划

### 9.1 bias-T 到货后：真实卫星定位（最高优先）

1. 给有源天线供电（bias-T：天线 RF+DC → Pluto RF，DC 接 3.3/5 V 电源）
2. `plutoGnssFrontEnd('DurationMs', 5000, 'Fs', 2.5e6)` 采集真实 L1
3. `acquisition(data, fs)` → 期望捕获 ≥4 颗真实卫星（M2 验收②）
4. `tracking(data, fs, acq)` 多通道跟踪 → `demodulateNavBits` +
   `gnssSubframeDecode` → `gnssEphDecode` → `satellitePosition` →
   `gnssPseudorange` → `leastSquaresPosition`（参考点 = 天线实际位置，
   可用 SP3 精密星历交叉验证，见 §11 下载）

### 9.2 性能/功能增强（不依赖硬件）

- **硬件完整 5 子帧发射**：TX 缓冲切换（每 6 s 换下一子帧，
  `tx.transmitRepeat(新缓冲)`），使星历也可从信号解码（当前硬件仅子帧 1）
- **多普勒注入**：当前全 0 Doppler 静态场景；多星可加不同多普勒（注意
  缓冲回绕相位跳变，可接受小多普勒）
- **伪距精度**：注入延迟亚采样插值（当前 120 m 量化）；DLL 亚码片细化
- **GUI 实时流**：接 Pluto `step()` 增量跟踪（当前为结果回放）
- **高动态**：PLL 加 FLL 辅助；弱信号（C/N0<35）PLL 带宽调优
- **多系统扩展**：Galileo/北斗（RINEX 3 已可读）

---

## 10. 工作流约定

1. **GitHub 更新**：每次进展 → 更新代码 + `CHANGELOG.md` + 相关文档 →
   `git add/commit/push`（仓库：`C:\Users\chang.su\Documents\GNSS-SDR-IN-MATLAB`）
2. **与用户中文交流**，结论先行，文件用绝对路径链接
3. **测试先行**：核心改动后用 `matlab -batch` 跑验证脚本 + 回归
   （M3/M2.5 的 Synthetic 回归不可回归）
4. **文件同步**：工作区 ↔ `D:\13_MCP\GNSS` 保持 SHA256 一致
5. **设备操作谨慎**：涉及硬件（TX 发射、串口、SDR）前先与用户确认；
   TX 发射仅限室内低功率短时
6. **官方 Helper addpath**：凡涉及编码/解码验证必须
   `addpath('D:\tools\matlab2022b\examples\satcom\main')`

---

## 11. 常用命令速查

```powershell
# MATLAB 自动化
& 'D:\tools\matlab2022b\bin\matlab.exe' -batch "addpath('D:\13_MCP\GNSS'); addpath('D:\tools\matlab2022b\examples\satcom\main'); <命令>;"

# 设备检测
Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -match 'Pluto' }
[System.IO.Ports.SerialPort]::GetPortNames()
Test-Connection 192.168.2.1 -Count 2

# 同步与哈希校验
Copy-Item -LiteralPath <工作区文件> -Destination <D:\13_MCP\GNSS\文件> -Force
(Get-FileHash -LiteralPath <文件> -Algorithm SHA256).Hash

# Git（仓库目录）
git -C 'C:\Users\chang.su\Documents\GNSS-SDR-IN-MATLAB' status -sb
git -C 'C:\Users\chang.su\Documents\GNSS-SDR-IN-MATLAB' add -A
git -C 'C:\Users\chang.su\Documents\GNSS-SDR-IN-MATLAB' commit -m "feat: ..."
git -C 'C:\Users\chang.su\Documents\GNSS-SDR-IN-MATLAB' push

# 图像查看（当前模型不支持 view_image）
node "C:\Users\chang.su\.codex\skills\deepseek-vision-skill\scripts\describe-image.js" "图.png"

# RINEX .Z 解压（Git 自带 gzip 支持 Unix compress）
& 'C:\Program Files\Git\usr\bin\gzip.exe' -d -k -f file.Z
```

**官方数据下载**（如需更新星历，DOY=日序, YY=年份）：

```powershell
# Garner UCSD（RINEX 2）
Invoke-WebRequest 'https://garner.ucsd.edu/pub/rinex/<YYYY>/<DDD>/auto<DDD>0.<YY>n.Z' -OutFile b.Z
& 'C:\Program Files\Git\usr\bin\gzip.exe' -d -k b.Z
# BKG IGS（RINEX 3 组合）
Invoke-WebRequest 'https://igs.bkg.bund.de/root_ftp/IGS/BRDC/<YYYY>/<DDD>/BRDC00WRD_R_<YYYY><DDD>0000_01D_MN.rnx.gz' -OutFile b.gz
& 'C:\Program Files\Git\usr\bin\gzip.exe' -d -k b.gz
# 精密星历 SP3（真实卫星定位交叉验证；BKG products 目录按 GPS 周号）
https://igs.bkg.bund.de/root_ftp/IGS/products/<周号>/
```

---

## 12. 参考资料

- [perrysou/GNSS_SDR](https://github.com/perrysou/GNSS_SDR)：SoftGNSS v3.0
  （`postNavigation.m`/`calculatePseudoranges.m` 的伪距思路已被本项目借鉴）
- [gnss-sdr/gnss-sdr](https://github.com/gnss-sdr/gnss-sdr)：C++ 实时接收机，
  原生 PlutoSDR 信号源（可做基准验证）
- [MathWorks: GPS Receiver Acquisition and Tracking Using Pluto SDR](https://www.mathworks.com/help/satcom/ug/gps-receiver-acquisition-and-tracking-using-pluto-sdr.html)
- MathWorks 官方 Helper：`D:\tools\matlab2022b\examples\satcom\main\`
  （HelperGPSNavigationConfig / HelperGPSNAVDataEncode / HelperGPSLNAVDataDecode
  / HelperGPSCEIConfig）
- IS-GPS-200（LNAV 编码、星历参数 §20.3.3.4、奇偶校验 §20.3.5.4）
- 本地官方示例：`D:\suchang\program\Pluto SDR\Matlab官方示例\`
- 本项目报告：`docs/` 下 M1~M4 各阶段验证报告 + `M4_summary.md`

---

## 13. 交接检查清单（给下一个会话）

- [ ] 阅读本文档（重点 §5 成果、§6 踩坑、§9 下一步）
- [ ] 检查 Pluto 在线（`findPlutoRadio` / 串口 / ping）
- [ ] 确认 `D:\13_MCP\GNSS` 与工作区 `GNSS\` 同步（SHA256，30 个 .m）
- [ ] 确认 Git 仓库 HEAD 与 origin/main 同步（当前 `7e019cc`）
- [ ] 与用户确认：bias-T 是否已到货、天线是否已供电
- [ ] 跑一次离线回归（`runAcquisitionTests`、
      `verifyGnssTracking('Synthetic', true)`、`verifyGnssEphDecode('FullLoop', false)`）
- [ ] 熟悉演示：`demoGnssPositioning('MsgPRN', 11)`、
      `gnssLiveGui('LoadFile', ...)`
- [ ] bias-T 到货后按 §9.1 执行真实卫星捕获与定位
