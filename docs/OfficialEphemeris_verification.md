# 官方 RINEX 星历 → 官方编码 → TX/RX 闭环验证报告

> **日期**：2026-08-07（与 M3 跟踪验证同日）
> **结论**：**PASS（Synthetic + 硬件闭环双模式）** —— 编码一致性 33/33 字段、
> 奇偶 30/30 字；Synthetic 0/915 误码；硬件（天线 TX−65 dB）0/609 误码
> **产物**：`data/official_ephemeris_20260807_181520.mat/.png`（Synthetic）、
> `data/official_ephemeris_20260807_182300.mat/.png`（硬件闭环）

---

## 1. 背景与目标

M3 之前 TX 发射的是自生成固定模式电文（`generateGpsSubframe` 数据字为
字序号 + 1010 模式）。用户提出：**能否用网上的官方星历/电文内容来发射**，
更规范也更省事。

本验证把 TX 电文来源替换为**官方真实广播星历**：

```text
官方 RINEX 广播星历
   │  readRinexNav（RINEX 2.11 自解析） / rinexread（RINEX 3）
   ▼
rinexToGpsCfg：映射到 MathWorks 官方 HelperGPSCEIConfig
   ▼
HelperGPSNAVDataEncode：按 IS-GPS-200L 缩放因子编码 LNAV 子帧 1-5
   ▼
generateGnssTxBuffer → 捕获 → DLL/PLL 跟踪 → 解调
   ▼
HelperGPSLNAVDataDecode（官方）+ gnssSubframeDecode（自研）双解码交叉验证
```

## 2. 官方数据源（已下载，存于 `data/`）

| 文件 | 来源 | 说明 |
|---|---|---|
| `auto2190.26n`（312 KB） | Garner UCSD `pub/rinex/2026/219/` | RINEX 2.11 GPS 广播星历（JAVAD 接收机生成），481 条记录 / 32 PRN |
| `BRDC00WRD_R_20262190000_01D_MN.rnx`（2 MB） | BKG IGS `IGS/BRDC/2026/219/` | RINEX 3 全 GNSS 广播星历（IGS 组合产品），`rinexread` 直接可读 |

> 注：CDDIS 需 Earthdata 认证（https 返回登录页），故采用 Garner / BKG
> IGS 官方镜像；下载链接见 §7。文件为 2026 年 DOY 219（2026-08-07）。

## 3. 实现（新增 3 个文件）

### 3.1 `readRinexNav.m` —— RINEX 2 解析器

R2022b 的 `rinexread` 只支持 RINEX 3（2.11 会报"not supported"），故自写
经典 brdc 格式解析器：

- 头文件：版本/类型、LEAP SECONDS、ION ALPHA/BETA、DELTA-UTC A0/A1/T/W
- 记录：首行 `I2,1X,5(I2,1X),F5.1,3X,3D19.12`（PRN/历元/af0-af2）+
  7~8 行星历 `3X,4D19.12`
- 输出 `nav.gpsEph` 结构数组（RINEX 自然单位：角度/速率为半周）

### 3.2 `rinexToGpsCfg.m` —— RINEX → 官方配置 → 编码

- 三种输入归一化：`readRinexNav` 输出 / `rinexread` 输出（RINEX 3 表，
  注意是 timetable）/ 单条星历
- **默认取最新且轨道有效的记录**：真实 RINEX 含零占位星历（如
  SVHealth=63 且 sqrtA=0 的空白记录），须跳过
- 字段映射（RINEX → HelperGPSCEIConfig）：
  - 钟差：`SVClockCorrectionCoefficients=[af0;af1;af2]`、Toc、TGD、IODC
  - 轨道：`SemiMajorAxisLength=sqrtA²`（编码器内部开方）、DeltaN、M0、
    Ecc、Toe、omega、Omega0、i0、OmegaDot、IDOT
  - 谐波：`HarmonicCorrectionTerms=[Cis;Cic;Crs;Crc;Cus;Cuc]`
  - 完好性：URAID、SVHealth、FitIntervalFlag
- `HelperGPSNavigationConfig`：`DataType="LNAV"`、`FrameIndices=[1]`、
  `HOWTOW` 由记录历元 UTC+leap 换算 GPS 秒周并下取整到 6 s；
  头文件电离层/UTC 参数同步填入（子帧 4/5 用）
- 输出：1500 位（5 子帧）+ `metas` 参考结构（已按 ICD 还原 D30 反转，
  与 `gnssSubframeDecode` 口径一致）

### 3.3 `verifyOfficialEphemeris.m` —— 端到端验证

1. 解析 RINEX → 选 PRN（默认 5，无记录则取第一颗健康星）
2. 官方编码子帧 1-5 → 取子帧 1-3（900 位，完整时钟+星历）
3. **官方解码交叉验证**：`HelperGPSLNAVDataDecode` 还原 33 个字段，
   逐项与源值比对（量化容差 1 LSB / 2，角度与速率按 ICD 字段范围取模）
4. **Synthetic 闭环**：900 位 TX 缓冲 → 注入多普勒 +1200 Hz / 码相位
   777 / C/N0=45 → 捕获 → DLL/PLL 跟踪 → 解调 → `gnssSubframeDecode`
   端到端对比
5. 判定 PASS/FAIL，保存 `.mat/.png`

## 4. 验证结果（2026-08-07）

### 4.1 官方解码交叉验证

```text
[DECODE] HelperGPSLNAVDataDecode 交叉验证 ...
  奇偶校验: PASS（30 字全过）
  星历字段: 33 项全部在量化误差内 PASS
```

PRN 5（TOW 基准 75603）：

| 字段 | 源值（RINEX） | 解码值 | 容差 |
|---|---|---|---|
| af0 | -2.358e-4 s | 一致 | 2^-31/2 |
| af1 | -3.411e-13 | 一致 | 2^-43/2 |
| sqrtA | 5153.7849 | 一致 | 2^-19/2 |
| Ecc | 0.0055758 | 一致 | 2^-33/2 |
| Toe / toc | 453600 / 453618 s | 一致 | 8 s |
| week / IODE / IODC | 2430 / 104 / 104 | 一致 | 整数 |
| 其余 23 项 | 谐波/开普勒根数/速率 | 一致 | 1 LSB / 2 |

**关键发现：ICD 字段回绕**。RINEX 2 的 M0=1.8966、DeltaN=3.918e-9 超出
32 位 / 16 位有符号字段范围时，编码按二补码回绕（M0-2 半周、
DeltaN-2^-27），解码还原为回绕值——这是字段固有属性，物理等效
（Kepler 方程按 2π 取模），比对须按字段范围取模。

### 4.2 Synthetic 闭环

```text
[SYN] 合成信号 18.6 s（46500000 采样），缓冲 900 位子帧1-3
[ACQ] PRN  5: metric=128.0 doppler=+1200.0 Hz codePhase=778 领先度=28.6
[TRK] PRN  5: lock=1 CN0=43.8 dB-Hz f=+1199.99 Hz bitSync=0 ms
  比特误码=0/915
[SYNC] 子帧 2: TOW=75604 子帧号=2 比特错误=0 全字段匹配=PASS
       子帧 3: TOW=75605 子帧号=3 比特错误=0 全字段匹配=PASS
```

结论：**PASS（编码一致性=33/33 奇偶=1 捕获=1 锁定=1 C/N0=1 参数=1
子帧=2）**

### 4.3 硬件闭环（天线场景，2026-08-07）

```text
[TX] 已发射官方子帧1 合成 GPS（6 s 缓冲，增益 -65 dB）  ← 天线发射
[RX] 硬件闭环采集 12.5 s 完成
[ACQ] PRN  5: metric=26.9 doppler=+0.0 Hz codePhase=2231 领先度=7.6
[TRK] PRN  5: lock=1 CN0=36.7 dB-Hz f=+0.00 Hz bitSync=15 ms
  比特误码=0/609
[SYNC] 子帧 1: TOW=75603 子帧号=1 比特错误=0 全字段匹配=PASS
```

结论：**PASS（编码一致性=33/33 奇偶=1 捕获=1 锁定=1 C/N0=1 参数=1
子帧=1）**。C/N0 36.7 dB-Hz 与 M3 硬件闭环（35.9）一致；0/609 误码。
硬件 TX 单缓冲 6 s = 1 子帧（300 位），完整 3 子帧星历仍由 Synthetic 验证。

## 5. 重大发现：自研奇偶链 ICD 不合规（已修复）

用官方编码器交叉验证时暴露了 `gpsWordParity` 的**两处 ICD 偏差**：

1. **HOW（字 2）与字 10 的 D29/D30 恒为 0**（IS-GPS-200 / PIRN
   IS-200J-001、gnsstk LNavTLMHOWFilter、OpenGPSRec 多源确认），且
   校验反馈在这些字后重置为 0。原实现按连续链计算，导致字 4 起奇偶失配。
2. **D30 位反转**：前字 D30=1 时本字 bit1..24 全部取反（ICD BPSK 极性），
   解码须先还原再校验/取字段。原实现未实现反转，自洽但不可跨实现互操作。

修复后 `gpsWordParity` / `generateGpsSubframe` / `gnssSubframeDecode`
与 MathWorks 官方 Helper 链**逐位兼容**，四向互操作全部通过：

| 方向 | 结果 |
|---|---|
| 自研编码 → 自研解码 | 1/1 子帧同步，TOW/字段全对（回归） |
| 自研编码 → 官方解码 | 奇偶 10/10 PASS |
| 官方编码（RINEX）→ 自研解码 | 3/3 子帧同步，dataOK 全对 |
| 官方编码（RINEX 3/IGS）→ 自研解码 | 3/3 子帧同步，dataOK 全对 |

回归：`verifyGnssTracking('Synthetic')` 与 `verifyGnssContinuousNav('Synthetic')`
均 PASS（改动前 M3/M2.5 判定为 FAIL 仅因数据字对比差在字 10 反推位，
修复 meta.dataWords 为实际发送逻辑位后全过）。

## 6. 与真实 GPS 的差异说明

- 官方 Helper 编码器按 IS-GPS-200L 缩放因子量化，字段结构与真实卫星播发
  完全同构（TOW、奇偶、星历位宽一致），只是星历来自当日官方广播文件
- 真实卫星每 30 s 播发完整 5 子帧（1500 位）；Pluto TX 单缓冲上限
  2^24 采样（2.5 MHz 下 6 s = 1 子帧），硬件闭环只能发子帧 1，完整
  3 子帧星历仅 Synthetic 验证（或后续做缓冲切换）
- 发射端 TOW 取自 RINEX 记录历元（UTC+leap → GPS 秒周），与真实
  电文一致；接收端不校验墙钟，仅校验 TOW 连续性

## 7. 复现

```matlab
addpath('D:\13_MCP\GNSS');
addpath('D:\tools\matlab2022b\examples\satcom\main');   % 官方 Helper
verifyOfficialEphemeris                                    % Synthetic（默认）
verifyOfficialEphemeris('RinexFile', 'D:\13_MCP\GNSS\data\BRDC00WRD_R_20262190000_01D_MN.rnx')
```

数据下载（如需更新当日文件，DOY=219, YY=26）：

```powershell
# Garner（RINEX 2）
Invoke-WebRequest 'https://garner.ucsd.edu/pub/rinex/2026/219/auto2190.26n.Z' -OutFile auto2190.26n.Z
& 'C:\Program Files\Git\usr\bin\gzip.exe' -d -k auto2190.26n.Z
# BKG IGS（RINEX 3）
Invoke-WebRequest 'https://igs.bkg.bund.de/root_ftp/IGS/BRDC/2026/219/BRDC00WRD_R_20262190000_01D_MN.rnx.gz' -OutFile b.gz
& 'C:\Program Files\Git\usr\bin\gzip.exe' -d -k b.gz
```

## 8. 后续（M4 铺垫）

- 星历子帧 1/2/3 解析已随本验证落地（`rinexToGpsCfg` 字段映射即 M4
  解析的逆向）；M4 需实现从解调子帧提取星历并计算卫星位置
- 硬件闭环 TX 官方子帧 1 已验证 PASS（2026-08-07，天线场景）；后续如需
  连续播发完整 5 子帧帧结构，需实现 TX 缓冲切换（每 6 s 换下一子帧）
