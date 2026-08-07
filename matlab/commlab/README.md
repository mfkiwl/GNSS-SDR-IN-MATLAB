# 通信原理实验平台（CommLab）

一个基于 MATLAB `uifigure` 的交互式调制解调演示程序，用于通信原理课程实验。

## 功能

- **调制方式**：AM、FM、ASK、QAM（4/16/64，含星座图）、FSK
- **复用方式**：TDM 时分复用、FDM 频分复用
- **可视化**：
  - 时域波形（基带 + 已调/复用信号）
  - 已调信号频谱（归一化）
  - 解调对比（原始 vs 还原）
  - QAM 星座图 / TDM 帧结构 / FDM 频谱分配 / 包络·瞬时频率视图
- **交互功能**：
  - 调制方式下拉切换，参数自动显示/隐藏
  - 载波频率、基带频率、采样率、仿真时长、调制度、调频指数、QAM 阶数、FSK 频偏等参数调节
  - 高斯白噪声叠加（SNR 滑杆 -10 ~ 40 dB）
  - 波形播放/暂停动画
  - 解调演示（输出相关系数 / 误比特率 / 误符号率）
  - 一键导出截图（PNG）
  - 重置参数

## 运行方法

在 MATLAB 命令窗口执行：

```matlab
cd('D:\suchang\program\Pluto SDR\CommLab')
CommLab
```

或直接：

```matlab
run('D:\suchang\program\Pluto SDR\CommLab\CommLab.m')
```

## 文件说明

| 文件 | 说明 |
|---|---|
| `CommLab.m` | GUI 主程序 |
| `genSignal.m` | 调制/复用信号生成（核心算法） |
| `demodSignal.m` | 解调/分接（核心算法） |
| `defaultParams.m` | 默认参数 |
| `runCommLabTests.m` | 单元测试（无噪声/带噪声/GUI 冒烟） |

## 测试

```matlab
cd('D:\suchang\program\Pluto SDR\CommLab')
runCommLabTests
```

## 技术要点

- AM：包络检波（Hilbert 变换 + 低通）
- FM：鉴频（瞬时频率提取）
- ASK：包络 + 门限判决
- FSK：连续相位 FSK，相关判决
- QAM：正交相干解调 + Gray 映射，星座图显示收发符号
- TDM：交替采样帧 + 分接
- FDM：多载波频带复用 + 带通滤波分离
