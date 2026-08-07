# GNSS-SDR-IN-MATLAB 项目交接文档

> **交接日期**：2026-08-07（第三次交接，新增 M3 DLL/PLL 跟踪模块全部
> Synthetic + 硬件闭环验证成果）
> **编写方**：Codex 会话（工作目录 `C:\Users\chang.su\Documents\Codex in Matlab`）
> **目的**：为下一个 Codex 会话提供完整、准确、经过实测验证的项目上下文，
> 使其无需从零探索即可继续开发 M4

---

## 1. 项目概览

**目标**：用 MATLAB 驱动 ADALM-PlutoSDR 接收 GPS L1 (1575.42 MHz) 信号，完成
**捕获 → 跟踪 → 导航电文解码 → 定位 → 实时显示** 全链路。

**当前阶段**：

| 里程碑 | 内容 | 状态 |
|---|---|---|
| M1 | PlutoSDR 连续采集链路验证（4 MSPS、无丢帧） | ✅ PASS（2026-08-06） |
| M2 | 捕获模块：32 PRN FFT 并行码相位搜索 | ✅ PASS（离线 6/6 + 硬件链路，2026-08-07） |
| M2.5 | TX 合成 GPS 发射 + 50 bps 电文 + 连续子帧收发验证 | ✅ PASS（2026-08-07） |
| M3 | 跟踪模块：DLL/PLL 多通道跟踪（Synthetic + 硬件闭环） | ✅ PASS（2026-08-07，详见 §5.7） |
| M3.5 | 官方 RINEX 星历电文：官方数据 + MathWorks 编码链路 + 闭环验证 | ✅ PASS（2026-08-07，详见 §5.8） |
| M4 | 导航电文子帧解析 + 定位解算 + 实时 GUI | ⬜ 待开发（下一步） |

> 注意：M2 的验收标准②"捕获 ≥4 颗真实卫星"仍未完成——原因是**有源天线未供电**
> （bias-T 尚未到货）。当前所有硬件验证均通过 **TX 发射合成 GPS 信号**完成，
> 接收链路与算法已就绪，只差真实卫星。

**总体架构**：

```text
PlutoSDR (L1 1575.42 MHz)
   │  step() 连续流（实时） / capture() 大块采集（离线）
   ▼
前端采集（matlab/frontend/，M1 完成）
   ▼
捕获 M2（acquisition.m：FFT 圆周相关，32 PRN × ±10 kHz，500 Hz 步进）
   ▼
跟踪 M3（DLL + PLL，1-10 ms 相干积分，C/N0）【待开发】
   ▼
解码 M4（50 bps 电文 → 子帧同步 → 星历 → 伪距 → 最小二乘定位）
   │   ├─ 子帧编码/解码模块已就绪（gpsWordParity / generateGpsSubframe /
   │   │   gnssSubframeDecode，连续子帧收发验证 0 错误）
   │   └─ 星历解析、定位、GUI【待开发】
   ▼
实时 GUI（uifigure：频谱/捕获网格/天空图/C-N0/电文/位置）【待开发】
```

---

## 2. 环境与工具链（已配置完毕，勿重复配置）

| 软件 | 版本/路径 | 说明 |
|---|---|---|
| MATLAB | R2022b 9.13.0.2049777，`D:\tools\matlab2022b` | 110 个工具箱 |
| ADALM-Pluto 支持包 | Communications Toolbox Support Package for ADALM-Pluto Radio | `findPlutoRadio`/`sdrrx`/`sdrtx` 可用 |
| Satellite Communications Toolbox | `gnssCACode`/`gnssBitSynchronize` 可用 | C/A 码生成 |
| Navigation Toolbox | `gnssconstellation` 可用 | 后续天空图用 |
| Git for Windows | 2.55.0，`C:\Program Files\Git` | 已加入 PATH |
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

当前模型不支持 `view_image`（工具被禁用）。**图像验证统一使用已安装的
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
| TX 天线 | ✅ 无源拉杆天线（接 Pluto TX 口，拉到约 5 cm = 1/4 波长即可） |
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

### 3.3 实测功率标定结论（天线场景，2026-08-07）

- 天线路径损耗约 **−44 dB**（相对回环线直连）
- RX 手动增益 20 dB 时噪声底 RMS ≈ 0.0005
- TX 增益 −30 dB → RX RMS 0.0025（C/N0≈48 dB-Hz）；−65 dB → 噪声级但可捕获
- **推荐档位**：天线场景 TX −65 dB / 幅度 0.1 / RX 20 dB；回环线 TX −89.75 dB /
  幅度 0.034 / RX 10 dB（详细见 §6）

---

## 4. 代码资产清单

### 4.1 位置总览（三处，内容按需同步）

| 位置 | 用途 |
|---|---|
| `C:\Users\chang.su\Documents\Codex in Matlab\GNSS\`（工作区） | **开发主副本**（apply_patch 可编辑） |
| `D:\13_MCP\GNSS\`（MATLAB 运行目录） | MATLAB 实际运行位置（含 `data\` 产物） |
| `C:\Users\chang.su\Documents\GNSS-SDR-IN-MATLAB\`（Git 仓库） | GitHub 仓库本地副本，`main` 分支 |

**同步规则**：工作区与 `D:\13_MCP\GNSS` 内容一致（`Copy-Item` 双向同步 + SHA256 校验）；
Git 仓库结构独立（`matlab/frontend`、`matlab/acquisition`），每次进展 commit + push。

### 4.2 工作区文件清单（20 个，均为 UTF-8 无 BOM）

| 文件 | 功能 |
|---|---|
| `gnssSettings.m` | 全局参数：中心频率、采样率、C/A 码参数 |
| `plutoGnssFrontEnd.m` | L1 采集：检测 → sdrrx → capture → 存 .mat/.bin |
| `verifyPlutoStream.m` | M1 验证脚本（A 健康/B step 流/C 回环音/D capture 对照） |
| `acquisition.m` | **M2 捕获主函数**：FFT 圆周相关，32 PRN × ±10 kHz |
| `generateSyntheticGpsSignal.m` | 合成信号生成器（延迟/多普勒/C-N0 可控，离线测试用） |
| `runAcquisitionTests.m` | 捕获离线回归测试（6 项，6/6 PASS） |
| `generateGnssTxBuffer.m` | TX 基带缓冲生成（整数码周期，可含 50 bps 电文） |
| `plutoGnssTx.m` | 独立 TX 发射脚本 |
| `verifyGnssLoopback.m` | 回环/天线闭环验证（TX 发射 + RX 采集 + 捕获 + 判定） |
| `demodulateNavBits.m` | 50 bps 电文解调（精对齐、逐 ms 剥码、位同步、符号判决） |
| `verifyGnssNavData.m` | 电文收发验证脚本（40 位测试序列，0 错误） |
| `gpsWordParity.m` | GPS 30 位字奇偶校验（ICD-GPS-200 §20.3.5.4） |
| `generateGpsSubframe.m` | 完整子帧生成（TLM/HOW/8 数据字，含校验） |
| `gnssBitEdgeDetect.m` | 比特边缘检测（能量法 + 翻转直方图法） |
| `gnssSubframeDecode.m` | 子帧同步（前导码 + 奇偶校验 + BPSK 极性消除）+ 字段解码 + 对比 |
| `verifyGnssContinuousNav.m` | 连续子帧收发验证（Synthetic/硬件两模式） |
| `tracking.m` | **M3 跟踪主函数**：DLL+PLL 多通道跟踪、C/N0、位同步、锁定判定 |
| `verifyGnssTracking.m` | M3 验证脚本（Synthetic/硬件闭环双模式，端到端子帧对比） |
| `readRinexNav.m` | **M3.5** RINEX 2.11 GPS 广播星历解析器（`rinexread` 不支持 2.x） |
| `rinexToGpsCfg.m` | **M3.5** RINEX → 官方 HelperGPSCEIConfig → LNAV 子帧编码 |
| `verifyOfficialEphemeris.m` | **M3.5** 官方电文验证：官方解码 33 字段交叉验证 + Synthetic 闭环 |
| `README_GNSS.md` | 项目 README（含各验证模块用法） |
| `README_M1.md` | M1 验证方案文档 |

### 4.3 Git 仓库结构

```text
GNSS-SDR-IN-MATLAB/
├── docs/
│   ├── project_overview.md           # 总览：硬件/架构/路线图
│   ├── M1_streaming_verification.md  # M1 验证方案与结论
│   ├── M2_acquisition.md             # M2 捕获模块方案与结论（含回环/天线验证）
│   ├── NavData_verification.md       # 50 bps 电文验证报告
│   ├── ContinuousNav_verification.md # 连续子帧验证报告（最新）
│   ├── HANDOFF.md                    # 本文件副本
│   └── images/                       # 验证实验图（navdata/continuous 两张）
├── matlab/
│   ├── frontend/                     # gnssSettings/plutoGnssFrontEnd/verifyPlutoStream
│   ├── acquisition/                  # 捕获 + TX + 电文 + 子帧全部模块
│   ├── tracking/                     # M3 DLL/PLL 跟踪（tracking/verifyGnssTracking）
│   └── commlab/                      # 辅助模块（通信原理实验平台）
├── CHANGELOG.md（0.1.0 ~ 0.6.0）
├── README.md / LICENSE / .gitignore
```

**当前 HEAD**：`88a4986`（连续子帧验证 PASS）；仓库干净、与 `origin/main` 同步。

---

## 5. 已验证成果（按阶段，附实测数据与产物）

### 5.1 M1：连续采集链路（2026-08-06）

- 4 MSPS / 15 s 流：帧间隔稳态 9.99 ms（≤12 ms）、p95 11.96 ms、相位跳变 0 次、
  回环音 SNR 81 dB
- 20 s 长稳态：1935 帧、有效吞吐 3.869 MSPS、首帧延迟 678.7 ms（一次性）
- 产物：`D:\13_MCP\GNSS\data\verify_20260806_183737.mat/.png`
- 核心结论：**实时必须用 `step()`；`capture()` 循环帧间不连续**

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

- TX −89.75 dB / 幅度 0.034 / RX 10 dB：**仅命中 PRN5**（metric 69，多普勒 +0.0 Hz），
  其余 PRN 噪声级
- 强信号档（TX −30 dB）32 颗 PRN 全部越门限——C/A 码互相关伪峰，属已知现象
- 产物：`data\gnss_loopback_20260807_155343.mat`（干净单星结果）

### 5.4 天线传输验证（拉杆 TX → 有源 RX，无 bias-T）

- TX −65 dB / 幅度 0.1 / RX 20 dB：**仅命中 PRN5**（metric 37.7，多普勒 +0.0 Hz），
  其余 PRN 3.4–3.6，领先度 10.4×
- 证明**无 bias-T 时天线链路仍可验证**（发射信号比真实卫星强 ~80 dB）
- 产物：`data\gnss_loopback_20260807_160409.mat`

### 5.5 50 bps 导航电文收发验证

- 40 位测试序列（GPS TLM 前导码 `10001011` 开头），TX −65 dB
- 捕获 PRN5（metric 15.8，多普勒 0 Hz）；解调 **100 位 0 比特错误**（匹配率 1.000）
- 产物：`data\gnss_navdata_20260807_162158.mat/.png`

### 5.6 连续 GPS 子帧收发验证（模拟真实环境）

- 发射 1 个完整子帧（300 位 = 6 s：TLM 前导码 + HOW(TOW=80000) + 8 数据字，
  含 ICD-GPS-200 奇偶校验）持续重复；`step()` 连续流采集 12 s
- **比特边缘检测**：最优偏移 18 ms，边界翻转率 0.44（理论正确约 0.5）
- **6 秒子帧边界同步**：前导码 + 10 字奇偶校验全部通过，起点位 233，
  BPSK 极性消除（极性=取反）
- 解码：TOW=80000、子帧号=1、TLM=010101；**300 位 0 比特错误**（逐位一致）
- 产物：`data\gnss_continuous_20260807_164313.mat`（`results.txBits/bits/dec` 完整保留）
- 报告：`docs/ContinuousNav_verification.md`（含实验图）

### 5.7 M3 跟踪模块验证（DLL + PLL，2026-08-07）

- **Synthetic PASS**：8 s 合成信号注入 +1200 Hz 多普勒/码相位 777/C/N0=45；
  捕获 metric 134；跟踪锁定 CN0 43.2 dB-Hz（真值 45）、频率误差 0.03 Hz、
  码相位误差 0.01 采样；610 位 **0 误码**；子帧解码 1/1（TOW=80000）
- **硬件闭环 PASS**（TX −65 dB / RX 20 dB 天线场景，12.5 s `step()` 流）：
  捕获 PRN5 metric 18.2、领先度 5.1×；锁定 CN0 35.9 dB-Hz、码相位 std
  0.020 采样、频率误差 0.11 Hz；609 位 **0 误码**；子帧解码 1/1
- 产物：`data\gnss_tracking_20260807_173214.mat`（硬件）/ `_173105.mat`（Synthetic）
- 报告：`docs/M3_tracking.md`（含实验图）；代码在 `matlab/tracking/`

### 5.8 官方 RINEX 星历电文验证（2026-08-07）

- **官方数据源**：Garner UCSD `auto2190.26n`（RINEX 2.11，481 条记录 /
  32 PRN）+ BKG IGS `BRDC00WRD_R_20262190000_01D_MN.rnx`（RINEX 3 组合）；
  CDDIS 需 Earthdata 认证故用 IGS 镜像
- **链路**：`readRinexNav`/`rinexread` → `rinexToGpsCfg` →
  MathWorks 官方 `HelperGPSNAVDataEncode`（IS-GPS-200L）→ TX/RX 闭环
- **Synthetic 闭环 PASS**：编码一致性 33/33 字段、奇偶 30/30 字、
  捕获精确命中（+1200 Hz、码相位 778、领先度 28.6）、跟踪 C/N0 43.8
  dB-Hz、**0/915 误码**、子帧解码全匹配
- **重大修复：自研奇偶链 ICD 不合规**——`gpsWordParity` 补全 HOW（字 2）
  与字 10 的 D29/D30=0（反馈重置）和 D30 位反转；修复后自研链与官方
  Helper 链四向逐位互操作，M3/M2.5 回归 PASS
- 产物：`data/official_ephemeris_20260807_181520.mat/.png`；
  报告：`docs/OfficialEphemeris_verification.md`

---

## 6. 关键技术结论与踩坑记录（核心，务必阅读）

### 6.1 MATLAB 语言/工具箱

1. **函数调用跨行续行必须写 `...`**：R2022b 中行尾逗号不自动续行，
   否则解析报"无效表达式"。方括号内续行例外。
2. **`gnssCACode` 返回 int8**：做算术前必须 `2*double(ca)-1`，否则与复数
   `.*` 报"不支持复整数算术运算"。
3. **结构数组字段裸用是逗号分隔列表**：`acq.results.PRN` 不能直接参与运算，
   必须 `[acq.results.PRN]` 拼接。
4. **行/列向量广播陷阱**：列向量与行向量 `==` 会隐式扩展成矩阵，
   导致 `sum`/`&&` 结果非标量。解调比特流统一用行向量，诊断时注意方向。
5. `.m` 文件 UTF-8 无 BOM；MATLAB 默认按 UTF-8 读取，中文注释/字符串可用；
   **控制台输出偶发乱码**（中文标签），关键输出用 ASCII 更稳。

### 6.2 捕获算法（M2）

6. **FFT 相关必须是圆周相关**：FFT 长度 = 块长（1 ms 码周期），
   不能零填充做线性相关——码相位接近码周期末尾（如 2495/2500）时线性相关
   无法回绕对齐，峰值位置和幅度全错。
7. **码相位语义**：从块起点到下一个码周期起点的延迟（采样点，1-based），
   直接作为 M3 跟踪初始值。合成信号生成器用 `(n - CodePhase)` 采样码片。
8. **多普勒格点量化**：500 Hz 步进 → 估计误差 ±250 Hz；弱信号
   （C/N0<38 dB-Hz）须用 `IntegrationMs>1` 相干积分并缩小 `DopplerStep`
   （5 ms 相干配 100 Hz 步进，C/N0=35 可捕获）。
9. **检测门限 6**（峰值/噪声均值，剔除峰 ±2 点）：纯噪声 8 种子实测最大
   3.39–3.62。
10. **强信号互相关伪峰**：C/N0 ≥ 60 dB-Hz 时 32 PRN 全部越门限（互相关比
    峰值低约 24 dB）。真实 GPS 电平无此问题；回环测试判定标准采用
    "目标指标 ≥ 3× 次高"。

### 6.3 PlutoSDR 硬件（TX/RX）

11. **TX `Gain` 属性范围 0 ~ −89.75 dB，0 = 最大输出**（与直觉相反），
    负值才是衰减；回环/天线测试必须从衰减档起步（初测 `Gain=0` 削波 79%）。
12. **TX/RX 采样率必须一致**（AD9363 共享基带时钟），不一致报错
    `Tx/Rx baseband sample rates do not match`。
13. **`transmitRepeat` 缓冲与 `capture` 单帧上限均为 2^24 采样**
    （16,777,216）：2.5 MSPS 下 TX 最多 1 个子帧（6 s = 15M 采样）；
    长采集必须用 `step()` 连续流（分块 `capture` 帧间不连续，M1 结论）。
14. **TX 缓冲必须整数个码周期**（1 ms = 2500 采样），否则 `transmitRepeat`
    每周期跳相。电文缓冲须整数个 20 ms 比特（且 20 ms = 20 码周期）。
15. **`kernelBuffersCount=32`** 可吸收偶发调度尖峰；首次 `step()` 有
    ~0.7 s 一次性初始化延迟。

### 6.4 电文/子帧处理

16. **BPSK 180° 极性模糊**：单比特相位校准可能全反（若能量最大比特是 −1）。
    必须由**前导码 + 奇偶校验**消除极性（真实接收机做法）——
    `gnssSubframeDecode` 对原样/取反两种极性都验证。
17. **参考序列对齐必须按 40 位周期 mod 循环**：对截断序列 `circshift`
    （99 位截断、40 位周期）会破坏周期结构，产生成簇假错误。
18. **位同步**：能量法弱信号下峰/次峰比仅 ~1.0（区分度低）；
    **翻转直方图法**（`real(c(i)*conj(c(i+1))) < 0` 统计边界翻转率，
    无需绝对相位）更可靠，正确对齐翻转率约 0.5。
19. GPS 电文字结构：30 位/字 × 10 字 = 300 位/子帧 = 6 s；TLM 前导码
    `10001011`；奇偶校验含前字 D29/D30 反馈（子帧首字前值为 0）。

### 6.5 M3 跟踪（2026-08-07 新增）

20. **二阶环路滤波器必须用位置式 PI**（`f = f0 + Kp*e + Ki*sum(e)`）：
    增量式 `f += Kp*e + ...` 会把比例项也积分成双积分器，噪声下频率随机
    游走、频偏下极限环（实测发散到 −55 kHz）；位置式从 40 Hz 离格频偏
    ~1 s 内可靠牵入。
21. **Costas 鉴别器模 π**（atan(Q_P/I_P)）：牵入范围仅环路带宽量级；初值
    必须来自捕获（DopplerStep=100 → 误差 ≤50 Hz，位置式环路可牵入），
    高动态场景后续应加 FLL 辅助。
22. **C/N0 的 20 ms 窗口必须按位同步对齐**：跨比特翻转时窄带功率被抵消，
    C/N0 低估 ~25 dB（实测 35.9 → 11.2 dB-Hz，比特仍 0 误码）；先位同步，
    再按 `(bitOffset + skipMs) mod 20` 对齐窗口计算。
23. **端到端子帧解码需 ≥ 600 位跟踪比特**（12 s 采集）：385 位时子帧起点
    落在 286 位即窗口截断；参考匹配须测双极性（BPSK 180° 模糊下 `bits==ref`
    仅 ~63%，`bits==1-ref` 后 100%）。

---

## 7. 复现与验证步骤

### 7.1 离线测试（无需硬件）

```matlab
cd('D:\13_MCP\GNSS')
runAcquisitionTests                          % M2 捕获 6/6
verifyGnssContinuousNav('Synthetic', true)   % 连续子帧离线模拟
verifyGnssTracking('Synthetic', true)        % M3 跟踪离线（8 s 合成）
```

### 7.2 硬件验证（需相应接线）

```matlab
verifyPlutoStream                            % M1，需回环线
verifyGnssLoopback('TxGain', -89.75, 'TxAmplitude', 0.034, 'RxGain', 10)  % 回环线
verifyGnssLoopback                           % 天线场景（默认 TX -65）
verifyGnssNavData                            % 50 bps 电文（天线场景）
verifyGnssContinuousNav                      % 连续子帧（天线场景，12 s）
verifyGnssTracking                           % M3 跟踪（天线场景，12.5 s）
```

PowerShell 自动化（无需打开桌面）：

```powershell
& 'D:\tools\matlab2022b\bin\matlab.exe' -batch "addpath('D:\13_MCP\GNSS'); <命令>;"
```

> **MATLAB -batch 注意**：每次启动约 10–30 s；函数名不能以 `_` 开头；
> 长脚本内联注意 `%` 注释会吞掉后续内容。

---

## 8. 已知问题与风险

| 问题 | 说明与对策 |
|---|---|
| bias-T 未到货 | 真实卫星捕获（M2 验收②）阻塞；当前用 TX 合成信号替代验证 |
| 室内多径 | 天线场景每比特能量波动大（min/max 差约 12 dB）；20 ms 积分余量足够，符号判决不受影响 |
| 位同步区分度 | 能量法弱信号峰/次峰比 ~1.0；用翻转直方图法（已实现） |
| 强信号互相关 | C/N0 ≥ 60 dB-Hz 时 32 PRN 虚警；真实电平无此问题，测试用领先度判定 |
| 固件版本提示 | 0.38 vs 支持包测试 0.34；可继续用，异常时降级 |
| Pluto 在线不稳 | 常被拔插；每次运行前 `findPlutoRadio()` 检测 |
| MATLAB 多实例 | -batch 与桌面可并存；曾遇启动瞬时挂起（150 s 无输出），重试即恢复 |
| view_image 不可用 | 用 deepseek-vision-skill（§2.2） |
| 控制台中文乱码 | MATLAB 输出偶发乱码；关键数据用 ASCII 标签打印 |

---

## 9. 下一步计划（M4 优先）

### M3：跟踪模块（DLL + PLL）

- **已完成**（2026-08-07，详见 §5.7 / docs/M3_tracking.md）：
  `tracking.m` 实现 DLL+PLL 多通道跟踪 + 位同步 + C/N0 + 锁定判定，
  Synthetic 与硬件闭环双模式 PASS（0 比特误码、子帧解码全对）
- **剩余**：`step()` 分块在线处理（当前为整段离线处理）；多通道硬件验证
  （当前单星）；弱信号（C/N0<35）PLL 带宽调优；高动态加 FLL 辅助

### M4：解码 + 定位 + 实时 GUI（下一步）

- 子帧解析基础已就绪（`gnssSubframeDecode`：TLM/HOW/数据字 + 奇偶校验）
- 需补：星历子帧 1/2/3 字段解析、伪距计算、最小二乘定位、`uifigure` GUI
  （频谱/捕获网格/天空图/C-N0/电文/位置），参考 CommLab 的 uifigure 技术栈
- **官方星历链路已铺好**（M3.5）：`rinexToGpsCfg` 的字段映射即 M4 星历
  解析的逆向；M4 直接从解调子帧提取星历（子帧 1=钟差/完好性、
  2/3=开普勒根数+谐波）计算卫星位置

### 硬件：bias-T 到货后

1. 给有源天线供电（bias-T：天线 RF+DC → Pluto RF，DC 接 3.3/5 V 电源）
2. `plutoGnssFrontEnd('DurationMs', 5000, 'Fs', 2.5e6)` 采集真实 L1
3. `acquisition(data, fs)` → 期望捕获 ≥4 颗真实卫星（M2 验收②）
4. 真实电文用 `demodulateNavBits` + `gnssSubframeDecode` 解析；
   `tracking(data, fs, acq)` 多通道跟踪

---

## 10. 工作流约定

1. **GitHub 更新**：每次进展 → 更新代码 + `CHANGELOG.md` + 相关文档 →
   `git add/commit/push`（仓库：`C:\Users\chang.su\Documents\GNSS-SDR-IN-MATLAB`）
2. **与用户中文交流**，结论先行，文件用绝对路径链接
3. **测试先行**：核心改动后用 `matlab -batch` 跑验证脚本
4. **文件同步**：工作区 ↔ `D:\13_MCP\GNSS` 保持 SHA256 一致
5. **设备操作谨慎**：涉及硬件（TX 发射、串口、SDR）前先与用户确认；
   TX 发射仅限室内低功率短时（1575.42 MHz 为受保护频段）

---

## 11. 常用命令速查

```powershell
# MATLAB 自动化
& 'D:\tools\matlab2022b\bin\matlab.exe' -batch "addpath('D:\13_MCP\GNSS'); <命令>;"

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
```

---

## 12. 参考资料

- [perrysou/GNSS_SDR](https://github.com/perrysou/GNSS_SDR)：SoftGNSS v3.0，
  MATLAB 离线接收机（采集→捕获→跟踪→定位）
- [gnss-sdr/gnss-sdr](https://github.com/gnss-sdr/gnss-sdr)：C++ 实时接收机，
  原生 PlutoSDR 信号源
- [MathWorks: GPS Receiver Acquisition and Tracking Using Pluto SDR](https://www.mathworks.com/help/satcom/ug/gps-receiver-acquisition-and-tracking-using-pluto-sdr.html)
- ICD-GPS-200：30 位字奇偶校验算法（§20.3.5.4），本项目实现于 `gpsWordParity.m`
- 本地官方示例：`D:\suchang\program\Pluto SDR\Matlab官方示例\`
- 本项目报告：`docs/M2_acquisition.md`、`docs/NavData_verification.md`、
  `docs/ContinuousNav_verification.md`、`docs/M3_tracking.md`（含实验图）

---

## 13. 交接检查清单（给下一个会话）

- [x] 阅读本文档（重点 §5 成果、§6 踩坑、§9 下一步）
- [ ] 检查 Pluto 在线（`findPlutoRadio` / 串口 / ping）
- [ ] 确认 `D:\13_MCP\GNSS` 与工作区 `GNSS\` 同步（SHA256）
- [ ] 与用户确认：bias-T 是否已到货、天线是否已供电
- [ ] 跑一次离线回归（`runAcquisitionTests`、`verifyGnssContinuousNav('Synthetic', true)`）
- [x] M3 已完成（Synthetic + 硬件闭环 PASS）；开始 M4 前与用户对齐验收标准
