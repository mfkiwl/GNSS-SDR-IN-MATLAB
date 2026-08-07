# M4 星历解析 + 卫星位置计算验证报告

> **日期**：2026-08-07
> **结论**：**PASS** —— 子帧比特 → 星历 26/26 字段（与官方 RINEX 量化容差
> 内一致）→ 卫星 ECEF 位置（32 星整周期对径比 0.9963±0.0041）
> **产物**：`data/gnss_eph_decode_20260807_183432.mat`

---

## 1. 目标

M4 核心第一步：从接收到的导航电文子帧（1/2/3）**解析完整广播星历**，
并由星历**计算卫星 ECEF 位置**（定位解算的前置）。数据来源延续 M3.5 的
官方 RINEX 星历 + MathWorks 官方编码链路，在 Synthetic 闭环中端到端验证。

## 2. 新增模块

### 2.1 `gnssEphDecode.m` —— 子帧比特 → 星历字段

输入 `gnssSubframeDecode` 输出的子帧（dataWords 逻辑位），按 IS-GPS-200
位宽/缩放/有符号性提取 26 个字段（与官方 `HelperGPSLNAVDataDecode` 完全
一致）：

| 子帧 | 字段 |
|---|---|
| 1 | Week, URA, SVHealth, IODC, TGD, Toc, Af0/Af1/Af2 |
| 2 | IODE, Crs, DeltaN, M0, Cuc, Ecc, Cus, SqrtA, Toe, FitIntervalFlag, AODO |
| 3 | Cic, Omega0, Cis, i0, Crc, omega, OmegaDot, IDOT |

要点：Ecc/sqrtA/Toe/Toc 无符号，其余二补码有符号；角度/速率为半周
（semi-circle）自然单位，与 RINEX 直接可比。

### 2.2 `satellitePosition.m` —— 星历 → ECEF 位置

IS-GPS-200L §20.3.3.4：开普勒方程迭代解偏近点角（10 次牛顿迭代，
1e-12 收敛）→ 真近点角/纬度辐角 → 谐波摄动修正（Cuc/Cus/Crc/Crs/
Cic/Cis）→ 升交点经度（含地球自转 WE=7.2921151467e-5）→ ECEF。
同时返回卫星钟差 Δtsv（af0+af1·dt+af2·dt²+相对论项
F·e·√A·sinE）。

## 3. 验证结果（2026-08-07）

### 阶段 A：确定性解码（官方比特直解）

```text
[A] 字段 26/26 通过
[A] 卫星位置: r=2.6421e+07 m (PASS)，60 s 位移=349.1 km (PASS)
[CONST] 32 星半径 2.6509e+07±2.0e+05 m (PASS)，
        整周期对径比 0.9963±0.0041 (PASS)
```

### 阶段 B：完整合成闭环（TX 900 位 → 捕获 → 跟踪 → 解码）

```text
合成信号 24.0 s（60000000 采样）
捕获: metric=125.5 doppler=+1200.0 Hz 领先度=30.5
跟踪: lock=1 CN0=43.9 dB-Hz 误码=0/1185
[B] 字段 26/26 通过
[B] 卫星位置: r=2.6421e+07 m (PASS)，60 s 位移=349.1 km (PASS)
```

## 4. 关键结论与踩坑

1. **ECEF 60 s 位移可达 349 km（物理正确）**：轨道运动 ~231 km/60 s 与
   地球自转视运动（≤1925 m/s）叠加；最初按惯性速度设 [180,300] km 门限
   误判，放宽到 [100,400] km 并附加轨道半径稳定性（60 s 内 <5 km）。
2. **整周期对径检查（ECEF 下的强校验）**：GPS 轨道周期 T≈43084 s ≈
   半个恒星日，一个周期后地球恰好自转 ~180°，ECEF 位置对径（≈2r）。
   这是对开普勒传播 + ECEF 坐标旋转的独立物理验证（32 星 0.9963±0.0041）。
3. **避免跨拟合区间外推**：PRN 13/32 在各自 Toe 外 4 h 处曾出现 663 km
   "近星"伪像（超出 2 h 拟合区间，星历误差被放大）；星座校验改为在每星
   自身 Toe 处计算。
4. **字段回绕沿用 M3.5 结论**：M0/Omega0/omega 等超范围值按 ICD 字段
   位宽二补码回绕，比对须按字段范围取模（物理等效）。

## 5. 复现

```matlab
addpath('D:\13_MCP\GNSS');
addpath('D:\tools\matlab2022b\examples\satcom\main');
verifyGnssEphDecode                     % 阶段 A + B（Synthetic，~1 min）
verifyGnssEphDecode('FullLoop', false)  % 仅阶段 A（快速）
```

## 6. 下一步（M4 定位）

- **多星 TX**：Synthetic 模式叠加 4+ 颗卫星（不同 PRN/码相位/多普勒），
  多通道捕获+跟踪
- **伪距**：由捕获码相位 + 跟踪精化 + 电文 TOW 构建观测方程
- **最小二乘定位**：ECEF 解算，与注入真值对比
- **GUI**：uifigure 天空图/频谱/C-N0/解码电文/位置
