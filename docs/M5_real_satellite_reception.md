# M5 真实卫星接收验证报告（窗外有源天线 → 完整导航电文/星历解码）

> **日期**：2026-08-17
> **结论**：**PASS** —— 7020-SDR 新板（Z7020+AD9361）+ Bias-T 有源天线
> （窗外），PRN 27 锁定 C/N0 **44.5~45.6 dB-Hz**，解出连续子帧
> **SF1~SF4**（奇偶校验全部通过）与**完整广播星历**（GPS Week 384）
> **产物**：`data/pluto_gnss_20260817_205815.mat/.bin`、
> `data/prn27_navdata_20260817.txt`

---

## 1. 硬件与接线

| 项 | 配置 |
|---|---|
| 接收板 | 7020-SDR 新板（Z7020+AD9361，固件 0.38，MATLAB 支持包直接识别） |
| 参考时钟 | 板载 **0.5 ppm TCXO**（L1 频偏约 ±0.8 kHz，远小于 ±10 kHz 搜索窗） |
| 天线链路 | RX1 → Bias-T（DC 馈电）→ 有源 GPS L1 天线，**置于窗外并抬高** |
| 采集参数 | L1 1575.42 MHz、2.5 MSPS、Manual 增益 50 dB |

> 注：闭环标定推荐工作点为 TX −60 dB / RX 40 dB（强信号场景）；真实卫星为
> 弱信号（约 −130 dBm），本报告使用 Manual 50 dB，避免量化受限同时保留余量。

## 2. 方法与链路

```text
窗外有源天线 → RX1(Bias-T) → 7020-SDR
  → plutoGnssFrontEnd 采集（step() 连续流 + 10 s 启动瞬态丢弃）
  → acquisition（32 PRN FFT 并行码相位搜索，±10 kHz）
  → tracking（DLL/PLL，1 ms 相干积分）
  → 位同步（20 ms 能量法）→ 比特流
  → gnssSubframeDecode（前导码 10001011 + 奇偶校验）
  → gnssEphDecode（广播星历 29 字段）
```

## 3. 关键发现：长采集三连坑

### 3.1 capture() 单次采样上限

`sdrrx.capture()` 单次上限 **16,777,216 采样**（2.5 MSPS 下约 6.7 s），
直接采 10 s 报错。长采集必须切换 `step()` 连续流
（`SamplesPerFrame` + `kernelBuffersCount=32`，M1 已验证方案），
已固化进 `plutoGnssFrontEnd.m`（[0.17.0]）。

### 3.2 step() 流启动瞬态（最关键）

**现象**：35 s 流式数据整体逐帧 RMS 均匀、零丢帧，捕获指标正常
（PRN 27 指标 41.6），但**前 ~6 s 跟踪无法锁定**（CN0 仅 11 dB-Hz），
而同一文件的 14~20 s / 29~35 s 段锁定 CN0 40+。

**根因**：流启动初期射频前端校准/USB 缓冲建立期的相位不连续，幅度
看不出异常但载波相位已坏。

**对策**：`WarmupMs`（默认 10 s）丢弃流启动瞬态后再采集，已固化进
`plutoGnssFrontEnd.m`（[0.17.1]）。

### 3.3 卫星信号随时间是变量

同一颗 PRN 27，6 分钟内捕获指标从 **97.5（20:43）** 降到 **9.4（20:49）**
（约 10 dB），跟踪从锁定 44.9 dB-Hz 变为完全锁不上；21:02 的采集还遇到
8.9 s 处强尖峰（峰值/RMS 11.7）。低仰角卫星受建筑物/树木遮挡或干扰时会
快速衰落——**天线高度与开阔视野是关键**，正式采集前建议先做 6 s 快测确认
锁定（C/N0 > 35）再上长采集。

> 附：导出脚本曾因文件名以 `_` 开头（MATLAB 标识符不允许）报
> “文本字符无效”，与信号无关。

## 4. 实测结果（2026-08-17）

### 4.1 6 s 快测（20:57）

```text
检测到 1 颗：PRN 27（指标 39.9，+500 Hz）
跟踪锁定：CN0 45.6 dB-Hz，位同步 3 ms，284 bit
```

### 4.2 35 s 长采集（20:58，取 3~35 s 干净段 32 s）

```text
[ACQ] 检测到 1 颗：PRN 27（+500 Hz）
[TRK] 锁定，CN0 44.5~44.7 dB-Hz，位同步 11 ms，1584 bit
[SF]  SF1~SF4 连续子帧（TOW 22181~22184，6 s 单位），奇偶校验全过
[EPH] Week=384，IODE/IODC=22，Toc=Toe=136784，TGD=2.33e-09，
      Af0=5.08e-07，SqrtA=5153.67，Ecc=0.014365，i0=0.302461，
      Omega0=-0.321347，omega=0.286939，OmegaDot=-2.77e-09 等全部字段
结论: PASS
```

**时间校验**：子帧 TOW 22181（6 s 单位）= 20:58:06 CST，与采集时刻
20:58:15 吻合；GPS Week 384 = 实际周 2432 的 10-bit 广播值（2026-08 正确）。

### 4.3 数据导出

`data/prn27_navdata_20260817.txt`：1584 bit 解调流 + 4 子帧原始 300 bit
（含 10 个 30-bit 原始字与 8 个 24-bit 数据字）+ 星历 29 字段。

## 5. 复现

```matlab
addpath(genpath('GNSS-SDR-IN-MATLAB/matlab'));

% 1) 6 s 快测（先确认信号锁定）
cd('GNSS-SDR-IN-MATLAB/matlab/frontend')
plutoGnssFrontEnd('DurationMs', 6000, 'GainMode', 'Manual', 'GainDb', 50)

% 2) 35 s 长采集（自动丢弃 10 s 启动瞬态）
plutoGnssFrontEnd('DurationMs', 35000, 'GainMode', 'Manual', 'GainDb', 50)

% 3) 处理：取 3~35 s 干净段
d = load('GNSS-SDR-IN-MATLAB/matlab/frontend/data/pluto_gnss_<时间戳>.mat');
seg = d.data(7.5e6:87.5e6);
acq = acquisition(seg, d.p.fs);
trk = tracking(seg, d.p.fs, acq);
sf  = gnssSubframeDecode(trk(1).bits);
eph = gnssEphDecode(sf.subframes);
```

## 6. 结论与下一步

- **真实卫星全链路 PASS**：采集 → 捕获 → 跟踪 → 位同步 → 子帧同步 →
  电文/星历解码，全部打通
- 本次仅 1 颗可见星（PRN 27），**定位需 ≥4 颗**；待卫星仰角/数量合适时
  复用 M4.2 定位链路做真实多星定位
- 注意事项：
  - 强信号下捕获层可能出现互相关伪峰（CN0 45.7 时 21 颗越门限），
    须按已知 PRN/注入列表选择跟踪对象
  - 定量测量前确认无干扰尖峰，必要时做泄漏/瞬态对照
  - 天线位置/高度直接影响结果，采集前先快测锁定

---

## 附录 A（2026-08-17 后续）

21:02 的第二次长采集（已带 WarmupMs）因卫星衰落（指标 ~15）与 8.9 s 处
干扰尖峰未能锁定——验证了 §3.3：**信号条件决定成败，代码链路已稳定**。
