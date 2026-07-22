# Mac AMD GPU Info — 交接文档 (ONBOARDING)

> 目的：让你在**另一台机器的全新会话**中，仅凭此文档就能快速接手本项目。原"当前待办问题"（RX 550 / `0x67FF` 信息识别不全）已在 `v1.1.1` 修复（第 6 节）；`v1.2.0` 新增**多显卡切换**（第 7 节）；`v1.2.1` 顶栏改为**两行样式**（第 8 节）；`v1.3.0` 新增**自动检查更新**（第 9 节）。

---

## 1. 项目是什么

macOS 下没有 GPU-Z，本项目是面向 **Intel Mac（含黑苹果）+ AMD 独显** 的「GPU 信息查看 + 传感器实时监控」桌面应用（对标 GPU-Z + 腾讯柠檬状态栏）。纯 **只读、无需 root、不改系统设置**（仅在检查更新时访问 GitHub Releases）。

- 仓库：`git@github.com:ljzxzxl/mac-amd-gpu-info.git`（分支 `main`，默认推送 `origin`）
- 已发布：`v1.0.0`（信息 + 传感器），`v1.1.0`（新增状态栏），`v1.1.1`（RX 550 `0x67FF` 识别修复），`v1.2.0`（多显卡切换），`v1.2.1`（顶栏两行样式），`v1.3.0`（自动检查更新）
- 语言/UI：Swift + AppKit（无 SwiftUI、无 Storyboard，纯代码构建）

### 背景结论（重要）
「macOS + AMD 显卡」这一组合**本质只存在于 Intel Mac（真机或黑苹果）**。Apple Silicon 不支持独立/外接 AMD GPU（统一内存架构，且已移除第三方 GPU 驱动）。所以本应用是 Intel 定位；我们仍编译**通用二进制**只是为了在任何 Mac 上都能原生启动（在 Apple Silicon 上会显示"无 AMD 显卡"）。

---

## 2. 构建与运行（关键约束）

- **只需 Xcode Command Line Tools，不需要完整 Xcode。**
- **不要用 `swift build`**：仅装 CLT 的机器上 `swift build` 会因 `xcrun --show-sdk-platform-path` 不可用而失败。项目改用 `swiftc` 直接编译。
- 单一可执行模块（所有 `.swift` 同属一个 target），文件之间**无需 import**。

```bash
bash scripts/build-app.sh      # 生成 build/MacAMDGPUInfo.app（通用二进制 x86_64+arm64）
open build/MacAMDGPUInfo.app    # 运行；首次打开若报开发者验证，右键→打开
bash packaging/make-dmg.sh      # 生成 dist/ 下 DMG + SHA256
```

- `build-app.sh`：对 `x86_64` 和 `arm64` 各编译一次，再 `lipo -create` 合并为通用二进制；并用 `sips`+`iconutil` 由 `Resources/AppIcon.png` 生成 `AppIcon.icns`；最后 ad-hoc 签名。
- **发布**：推送 `v*` tag 触发 `.github/workflows/build.yml`（运行器 **`macos-latest`**，`permissions: contents: write`），产出 DMG 并发 GitHub Release。

---

## 3. 源码结构（Sources/mac-amd-gpu-info/）

| 文件 | 职责 |
|---|---|
| `main.swift` | 入口，`NSApplication` + AppDelegate |
| `AppDelegate.swift` | 生命周期、主菜单/关于(版本号从 Bundle 的 `CFBundleShortVersionString` 读取，勿硬编码)、Dock 图标、状态栏控制器、启动形态判定、**启动静默检查更新 + 菜单「检查更新…」** |
| `MainWindowController.swift` | `NSWindow` + `NSTabView`（信息/传感器/状态栏 三标签）、**窗口高度自适应**；启动枚举多卡并注入选中回调 |
| `GPUModels.swift` | `GPUInfo`（静态，含每卡唯一键 `registryID`/`pciLocation`）与 `GPUStats`（传感器）数据模型 |
| `GPUReader.swift` | **IOKit 读取核心**：多卡枚举 `readAllInfos()` + 按卡传感器 `readStats(pciRegistryID:)` + PCIe + Metal + 品牌兜底 |
| `GPUSelection.swift` | **多卡选中源单例**：卡列表 + 当前 `registryID`，联动信息页/传感器页/状态栏 |
| `VBIOSDecoder.swift` | 从 VBIOS 二进制抽取料号/ATOMBIOS/日期/板卡/子系统/颗粒厂商/品牌 |
| `DeviceDatabase.swift` | **device-id → 芯片规格**（系统读不到的着色器/位宽/die 等）；**子系统厂商 ID → AIB 品牌** |
| `InfoTabViewController.swift` | 信息页：GPU-Z 式版式，右键复制/hover 展开/导出；**底部「导出 VBIOS」右侧的显卡切换下拉框** |
| `SensorsTabViewController.swift` | 传感器页：顶部数值网格 + 六条曲线，**按选中卡刷新**、显存上限用该卡 `vramMB` |
| `SensorGraphView.swift` | 自绘折线图（环形缓冲、图例带含义备注、半透明填充） |
| `StatusBarMetric.swift` | 状态栏 8 指标定义（`abbr` 英文缩写 / `value` 带单位值 / `detailText` 明细） |
| `StatusBarSettings.swift` | 状态栏设置（UserDefaults + 变更通知） |
| `StatusBarController.swift` | `NSStatusItem` **两行样式模板图**刷新（上值下缩写 + 暗色分隔竖线）+ 下拉菜单（2s，含「检查更新…」）；**跟随选中卡**（回退首张） |
| `StatusBarTabViewController.swift` | 「状态栏」标签页：主开关 + 8 指标开关 + 自启动开关 |
| `LoginItem.swift` | `SMAppService` 登录自启动封装 |
| `Updater.swift` | **检查更新**：查询 GitHub `releases/latest`、语义版本比较、下载 DMG 到「下载」并 `NSWorkspace.open` 打开安装窗 |
| `UIComponents.swift` | `CopyableLabel`（右键复制）、`FlippedView`、`UI.label`/`UI.valueBox` 工厂 |

---

## 4. 数据来源（IOKit，务必理解）

- **传感器**：匹配 `IOServiceMatching("IOAccelerator")` → 过滤 IOClass 含 `AMDRadeon` 且含 `Accelerator`（覆盖 X4000/Polaris、X5000/Vega、X6000/Navi）→ 读属性 `PerformanceStatistics`（CFDictionary）。多卡下按每张 PCI 卡的 `registryID` 定位其 PCI 节点，再向下遍历 IOService 子树找到本卡 accelerator（见 `GPUReader.readStats(pciRegistryID:)`），避免多卡串号。
  - 常用键：`Temperature(C)`、`Core Clock(MHz)`、`Memory Clock(MHz)`、`GPU Activity(%)`、`Device Utilization %`、`Total Power(W)`、`Fan Speed(RPM)`、`Fan Speed(%)`、`inUseVidMemoryBytes`。
- **静态信息**：匹配 `IOServiceMatching("IOPCIDevice")` → 枚举所有 `model` 含 "Radeon" 的节点（`GPUReader.readAllInfos()`，支持多卡）→ `IORegistryEntryCreateCFProperties`。
  - 键：`model`（CFData 字符串）、`device-id`/`vendor-id`/`revision-id`（CFData，小端）、`VRAM,totalMB`（Int）、`IOPCIExpressLinkStatus`（Int，见下）、`ATY,bin_image`（CFData，**完整 VBIOS 二进制**，通常 64KB）、`compatible`（CFData，NUL 分隔的 `pciVVVV,DDDD` 令牌，首个即**子系统厂商 ID**）。
  - PCIe 解析：`IOPCIExpressLinkStatus` 低 4 位=速率(3=Gen3)，bit9:4=通道数。
  - **品牌兜底**：无 VBIOS 时（如 Navi），从 `compatible` 首个 `pciVVVV,DDDD` 取子系统厂商 ID，映射 AIB 品牌（`DeviceDatabase.aibBrand`，如 `0x1DA2`=Sapphire）。
- **Navi/RDNA 的数据限制**：Navi 卡（如 RX 5700 XT `0x731F`）的 `IOPCIDevice` **不含 `ATY,bin_image`**，故料号/ATOMBIOS/日期/板卡/子系统/颗粒厂商 无数据源、VBIOS 无法导出——属 macOS 固有限制，非缺陷。规格靠机型库补、品牌靠子系统厂商 ID 补。Polaris（如 RX 550）才公开 VBIOS。
- **端口常量**：用 `kIOMasterPortDefault`（兼容 macOS 11；`kIOMainPortDefault` 需 macOS 12+，会导致最低系统 11 编译报错）。
- **VBIOS 字节 → 字符串**：`VBIOSDecoder.asciiRuns()` 提取可打印 ASCII 片段（等价 `strings`），再正则/关键字匹配。

---

## 5. 踩过的坑（避免重犯）

- **CI 曾产出 arm64-only**：`macos-latest` 是 Apple Silicon，`swiftc` 默认只编宿主架构 → Intel 机器显示禁止符号无法运行。**必须保持通用二进制**（build-app.sh 已处理）。
- **`NSTextView` 空白**：作为 documentView 时必须设 `frame` 和 `textContainer.containerSize` 宽度，否则容器宽 0、不渲染。（现信息页已改用自绘表单，非 NSTextView。）
- **hover 气泡**：值/标签要 `isSelectable = true` + `allowsExpansionToolTips = true` 才有"即时、好看"的截断展开气泡；单纯 `toolTip` 有延迟且样式差。
- **窗口自适应高度**：用 `tabView.contentRect` 实测标签条装饰高度（chrome），不能拍脑袋估。
- **按钮锚定**：贴底的按钮用 `.maxYMargin`（不是 `.minYMargin`）。
- **登录启动判定**：AppKit 无官方标志，现用 `NSApp.isActive` 启发式（仅在"状态栏+自启动"都开时影响启动形态）。若不稳，可改独立登录助手。
- **accelerator 家族别写死**：传感器 accelerator 类名随 GPU 代际不同（Polaris=`AMDRadeonX4000_*`、Vega=`AMDRadeonX5000_*`、Navi=`AMDRadeonX6000_*`）。曾只匹配 `AMDRadeonX4000` 导致 Navi 传感器全空；现改判 `含 AMDRadeon 且含 Accelerator`。
- **多卡配对别按 device-id**：两张同型号卡 device-id 相同会串号。以 PCI 节点 `registryID` 为唯一键，读传感器时从该 PCI 节点向下遍历 IOService 子树定位它自己的 accelerator（`GPUReader.readStats(pciRegistryID:)`）。

---

## 6. 【已修复 v1.1.1】RX 550 (0x67FF) 信息识别不全

Sapphire RX 550（`device-id 0x67FF`，`revision 0xFF`）此前部分字段缺失。已在**本机**（该卡即开发机显卡）通过 `ioreg` 导出真实 VBIOS 校准并修复，实测字段齐全。

### 真实取证结论（本机 ioreg + strings）

| 项 | 真实值 |
|---|---|
| model / device-id / revision | AMD Radeon RX 550 / `0x67FF` / `0xFF` |
| 料号 | `113-34830M4-U02`（末段 `U02` 字母开头 → 旧正则 `\d{3}` 命中失败根因） |
| 板卡标识 | `POLARIS21`（全大写 → 旧大小写敏感匹配失败根因） |
| 子系统 | `SAPPHIRE_POLARIS21_3E348030_NEW_GD5_4G_MICRON` |
| 显存 | GDDR5（含 `GD5`）、128-bit（256Mx32 ×4 = 4GB）、Micron |
| 芯片串 | `P21 XT`（Polaris 21）、ATOMBIOS VER015.050.002.001.000000、日期 04/19/17 |

### 已落地的修复

1. **`DeviceDatabase` 新增 `0x67FF`**（Polaris 21 / RX 550：GCN 4.0、14nm、512 SP、8 CU、32 TMU、16 ROP、128-bit、GDDR5、额定 1183/1750 MHz、123mm²/3.0B）。
   > 注：0x67FF 坊间有 512/640 SP 两版，VBIOS 铭牌 `P21 XT` 不含使能 CU 数，SP/CU/TMU 取典型 512 SP 作"型号参考值"；如遇 640 SP 实机仅需调这三个数值。
2. **`VBIOSDecoder` 增强**：
   - 板卡标识匹配改**大小写不敏感**（命中 `POLARIS21`，展示保留原始大小写）；
   - 料号正则末段由 `\d{3}` 放宽为 `[0-9A-Za-z]{2,}`（兼容 `113-34830M4-U02`），仍保留 `1\d{2}-` 前缀避免误匹配日期；
   - `VBIOSInfo` 新增 `memoryType`，按 GDDR6/GDDR5(GD5)/HBM2/HBM 关键字推断。
3. **`GPUReader.readInfo()` 显存类型兜底**：机型库未命中 `vramType` 时用 VBIOS 推断值兜底。
4. 已确认对现有 RX 580（`0x67DF`）无回归；版本升至 `v1.1.1`。

### 排错手法留存（获取该卡真实 VBIOS 字符串）
```bash
ioreg -rw0 -c IOPCIDevice | grep -o '"ATY,bin_image" = <[0-9a-f]*>' | head -1 \
| sed 's/.*<//;s/>//' | xxd -r -p | strings -n 4 \
| grep -iE "113-|polaris|gddr|micron|[0-9]{2}/[0-9]{2}/[0-9]{2}"
```
或用应用「信息」页的 **导出 VBIOS…** 存出 `.rom` 再分析。新增其它显卡时，据此看清真实"料号/板卡标识"格式再调库/正则。

---

## 7. 【v1.2.0】多显卡支持

本机双 AMD 独显（Sapphire RX 550 / Polaris `0x67FF` + Sapphire RX 5700 XT / Navi 10 `0x731F`）。像 GPU-Z 一样在**信息页底部、`导出 VBIOS…` 按钮右侧**放显卡下拉框，切换后信息页 / 传感器页 / 状态栏随所选卡刷新。

### 架构
- 每张卡以其 `IOPCIDevice` 的稳定 `registryID` 为唯一键（避免同型号卡串号）。
- `GPUReader.readAllInfos()` 枚举所有 Radeon 卡；`readStats(pciRegistryID:)` 用 `IORegistryEntryIDMatching` 定位该 PCI 节点，再向下遍历 IOService 子树找到它自己的 accelerator（`acceleratorStats(under:)`）。
- `GPUSelection.shared` 保存卡列表 + 当前 `registryID`，作为信息页/传感器页/状态栏共同的选中源。
- `InfoTabViewController` 承载下拉框（`configureGPUs`/`onSelectGPU`），下拉**仅显示型号**，仅当出现同名型号时才追加 ` @pci位置`。

### 实测（双卡端到端）
| 卡 | 位置 | device-id | 芯片 | 显存 | 驱动家族 | 品牌来源 | 传感器 |
|---|---|---|---|---|---|---|---|
| RX 550 | 1:0:0 | 0x67FF | Polaris 21 | 4096MB | AMDRadeonX4000 | VBIOS | ✅ |
| RX 5700 XT | 6:0:0 | 0x731F | Navi 10 | 8176MB | AMDRadeonX6000 | 子系统厂商 `0x1DA2` | ✅ |

### 注意
- Navi 无 `ATY,bin_image`：BIOS 栏（料号/日期/板卡/子系统）、颗粒厂商 无数据、VBIOS 不可导出；导出按钮禁用并有 hover 说明。这不是缺陷。
- 状态栏可在主窗口未开时运行：此时 `GPUSelection` 列表为空，`readSelectedStats()` 回退首张卡。

---

## 8. 【v1.2.1】顶栏两行样式

参照 gpu-fan-monitor 的两行菜单栏效果，把状态栏从"单行并排文本"改为**两行列**：每个开启的指标一列，**上=带单位数值、下=英文缩写**。

- 缩写映射（`StatusBarMetric.abbr`）：`TEMP / FAN / PWR / ACT / UTIL / VRAM / CORE / MEM`。
- 数值行（`StatusBarMetric.value`）带单位：`77°C / 1360 / 156W / 12% / 31% / 899M / 1266 / 1750`（风扇/核心/显存单位过长，靠缩写标签表达）。
- **渲染**：`StatusBarController.makeStackedImage()` 把各列绘成一张与菜单栏等高的**模板图**（`isTemplate=true`），竖直方向按总高精确居中，避免多行文字被基线顶偏。值 11pt 等宽数字半粗、缩写 7pt，列间距 `colGap=6`。
- **分隔竖线**：相邻列间画 1px 竖线；因模板图只按 alpha 取菜单栏色，用 `NSColor.black.withAlphaComponent(0.30)` 实现"比文字更暗"的分隔（想更深/更淡改这个 alpha；想更宽间距改 `colGap`）。

## 9. 【v1.3.0】自动检查更新

参照 charge-limit-helper 的"检查 Releases→提示→跳转下载"，并增强为"一键下载并打开安装窗"。全部用系统能力（`URLSession` + `NSWorkspace` + `NSAlert`），无第三方依赖、无 Sparkle。

- **数据源**：GitHub `https://api.github.com/repos/ljzxzxl/mac-amd-gpu-info/releases/latest`（公开免鉴权，请求需带 `User-Agent` 头）。取 `tag_name` / `assets[].browser_download_url`(.dmg) / `html_url`。
- **版本比较**：`Updater.isNewer`，去掉 tag 的 `v` 前缀后按 `.` 分段数值比较。当前版本取 `Bundle` 的 `CFBundleShortVersionString`。
- **时机**：`AppDelegate.applicationDidFinishLaunching` 启动**静默检查**（仅有新版才弹窗）；应用菜单与状态栏菜单的「检查更新…」为**手动检查**（有新版 / 已最新 / 失败 三态弹窗）。`isCheckingUpdate` 状态位防重复。
- **引导下载**：`Updater.downloadAndOpen` 用 `downloadTask` 存到 `~/Downloads` 后 `NSWorkspace.open(dmg)` 自动挂载弹出安装窗；无 dmg 资产或下载失败则打开 `html_url` 发行页兜底。
- **未做真·一键自动替换**：ad-hoc 未签名下替换运行中 App 有 Gatekeeper 隔离/自替换风险；采用"下载并打开 DMG 引导拖入"的稳健折中。
- **隐私**：仅检查更新时向 GitHub 发只读 GET，不上传任何数据；关于面板/README 表述已相应更新。
- **网络权限**：应用**非沙盒**，`URLSession` 出站请求无需额外 entitlement。

## 10. 验证清单（改完自检）

- `bash scripts/build-app.sh` 通过；`lipo -info` 显示 `x86_64 arm64`。
- `open` 后无崩溃；三标签页正常。
- 该 RX 550 机器上：芯片/规格/显存类型/位宽/料号/板卡标识 不再缺失。
- 现有 RX 580 机器上：字段无回归。
- 传感器六曲线正常刷新；状态栏开关/指标/自启动可用。
- **多卡**：下拉框列出全部卡；切换后信息页/传感器页/状态栏均正确切换、互不串号；Navi 卡传感器正常、品牌显示 AIB 厂商。
- **顶栏两行**：开启状态栏后每指标显示两行（上值下缩写）、列间有暗色竖线、整体竖直居中不溢出。
- **检查更新**：菜单/状态栏「检查更新…」三态正常；发现新版可下载并弹出安装窗（本机版本高于线上时，启动不弹更新属正常）。

## 11. 约定

- 提交信息用中文、说明动机；只改必要文件；不引入 SwiftUI/Xcode 依赖。
- 发布走 tag（`git tag -a vX.Y.Z -m "..." && git push origin vX.Y.Z`），CI 自动出 DMG Release。
