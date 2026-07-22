# Mac AMD GPU Info

macOS 上没有 GPU-Z，本工具面向 **Intel Mac（含黑苹果）+ AMD 独显**，用一个窗口查看显卡的完整信息与基础实时监控。数据全部来自系统 IOKit，**只读、无需 root、不修改任何系统设置**（仅在检查更新时访问 GitHub）。

## 功能

**信息页**
- 型号 / 品牌 / 芯片 / 架构 / 制程
- Device / Vendor / Revision ID、PCIe 链路（代数 × 通道）
- 显存容量 / 类型 / 颗粒厂商 / 位宽
- 规格（流处理器 / TMU / ROP / 计算单元 / 额定频率 / die / 晶体管，来自内置机型库）
- VBIOS 料号 / ATOMBIOS 版本 / 构建日期 / 板卡标识 / 子系统串，并可**一键导出 VBIOS 二进制**
- 系统版本 / Metal 支持 / 驱动

**传感器页**
- 每秒刷新：温度、核心/显存频率、GPU 活跃度、设备占用、功耗、风扇转速、显存占用
- 温度与 GPU 活跃度历史折线图

**检查更新**
- 启动时静默检查 GitHub Releases；应用菜单与状态栏菜单均有「检查更新…」
- 发现新版可一键下载 DMG 并自动打开安装窗口，把 App 拖入「应用程序」替换即可

## 兼容性

- Intel Mac + AMD 独显（`AMDRadeonX4000` 家族，如 RX 580 及同类 Polaris/后续卡）
- macOS 11 及以上
- 未检测到 AMD 独显时给出提示，不崩溃

## 已知边界（macOS 限制）

- 核心/分路电压、VRM 遥测、PerfCap 原因：macOS 不暴露，无法显示
- 着色器/ROP/die 等芯片规格系统读不到，由内置机型库提供；未收录型号显示"未知"

## 构建

只需 Xcode Command Line Tools：

```bash
bash scripts/build-app.sh      # 生成 build/MacAMDGPUInfo.app
open build/MacAMDGPUInfo.app
```

首次打开若提示无法验证开发者，在 Finder 里右键 App → 打开。

## 打包 DMG

```bash
bash scripts/build-app.sh
bash packaging/make-dmg.sh     # 生成 dist/MacAMDGPUInfo-<版本>.dmg + SHA256
```

推送 tag（如 `v0.1.0`）会触发 GitHub Actions 自动构建并发布 Release。

## 许可证

MIT，见 `LICENSE`。
