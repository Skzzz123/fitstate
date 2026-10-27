# 状态 · 健身准备度 App

只给自己用的 iOS App：从 Apple Watch 同步进「健康」的**睡眠分期、HRV、静息心率**，
用你自己的 30 天基线做对照，算出今天的准备度分数和训练建议。

- 纯本地：无账号、无网络、无追踪，数据全在 iPhone 里
- 只读：只申请读取权限，永远不会往「健康」写入任何东西
- 小组件：主屏小尺寸 / 中尺寸，长按可刷新

> **这是一个纯技术仓库**：没有编译好的 App，只有源码和一条 CI 流水线。
> 你的电脑上不需要装 Xcode。

---

## 一、你需要准备什么

| 项目 | 说明 |
|---|---|
| 一个 Apple 账号 | 免费的就够（免费账号的签名证书 7 天到期，需要每周续签一次） |
| 一个 GitHub 账号 | 用来跑云端编译（公开仓库免费不限量，私有仓库每月有 200 分钟 macOS 额度） |
| 一根数据线 | iPhone 首次装机时用 |
| Windows 上的三个工具 | Sideloadly + 官网版 iTunes + 官网版 iCloud（见第五步） |

**推荐**：先按本文跑通「免费账号 + Sideloadly」这条路，确认 App 好用之后再决定要不要升级。

---

## 二、把代码推上 GitHub

```powershell
cd "D:\minimax working\fitstate"
git init
git add .
git commit -m "feat: 状态 App 初始版本"
git branch -M main
git remote add origin https://github.com/<你的用户名>/fitstate.git
git push -u origin main
```

> 仓库设为 **Private** 时，GitHub 的 macOS 构建额度是每月 200 分钟（一次构建约 5 分钟，够用）。
> 但**私有仓库跑 macOS 任务需要绑一张卡**——把 Actions 的消费上限设成 $1 即可，实际不会扣费。
> 想完全避开绑卡，把仓库设为 Public 即可（Apple ID 密码等敏感信息本来也不在仓库里）。

---

## 三、Apple 账号：免费账号到底能做到哪一步

这是整条流程里唯一有门槛的地方，先把事实摆清楚（2026-10-27 实测）：

| 能力 | 免费 Apple 账号 | Apple Developer Program（$99/年） |
|---|---|---|
| HealthKit capability | ✅ 可以 | ✅ 可以 |
| App Groups | ✅ 可以 | ✅ 可以 |
| 门户里手动注册 App ID / App Group / 设备 | ❌ 进不去 | ✅ 可以 |
| Xcode Cloud 云编译 | ❌ | ✅ |
| TestFlight | ❌ | ✅ |
| 签名证书有效期 | **7 天** | 1 年 |

「HealthKit 免费账号可以用」不是猜测——来自 Apple 官方能力矩阵
<https://developer.apple.com/help/account/reference/supported-capabilities-ios/>，
HealthKit 那一行在 ADP / ADEP / Apple Developer（免费）三列全是 ✅。

但是**免费账号进不了「证书、标识符和描述文件」**：访问
<https://developer.apple.com/account/resources/identifiers/list> 会直接被挡回来——
> Access Unavailable — This resource is only for developers enrolled in a developer program

所以下面 3.1 的「手动建 App ID」这条路，免费账号走不通。

### 3.1 路线 A：免费账号（本文默认，先跑通再说）

免费账号靠**签名工具自动建 App ID**。Xcode 的自动签名（Personal Team）和 Sideloadly
走的是同一套 Apple 接口：签名的那一刻自动创建 App ID，并带上 App 声明的 capability。
所以免费账号装得上、HealthKit 也能授权，代价只有证书 7 天到期。

具体操作：

1. **不用碰开发者门户**，直接跳到第四步编译。
2. 编译时 App Group ID 先用占位值 `group.com.god.fitstate`；
   真正生效的组名在签名阶段由工具补上 Team ID 前缀。
3. **Team ID 从哪来**：签名工具给免费个人团队生成 id 时，规则是
   `<原 bundle id>.<TeamID>`（Xcode 也是这个规则）。所以装完之后看
   Sideloadly 实际装上去的 bundle id 就知道了——
   本机实测是 `com.god.fitstate.97792VH57A`，那 **Team ID 就是 `97792VH57A`**，
   对应的 App Group 是 `group.97792VH57A.com.god.fitstate`。
   > 注意：Windows 证书库里**看不到**这个 Team ID。Sideloadly 只在门户侧
   > 临时建证书，不往本机证书库写，所以别指望从证书主体里翻。
4. 编译时把 `app_group_runtime_id` 传成 `group.<TeamID>.com.god.fitstate`
   重新出包、重新安装即可。App 里的 `AppGroup.swift` 还会在运行时
   自动探测（从自己的 bundle id 里认出 Team ID），即使参数填错也能兜底。

### 3.2 路线 B：付费账号（$99/年，更省心）

如果实测发现免费档走不通，或者你不想每 7 天续签一次：

1. <https://developer.apple.com/programs/> 加入 Apple Developer Program
2. 门户 → **Identifiers** → `+` → **App IDs** → **Explicit** →
   Bundle ID 填 `com.god.fitstate` → Capabilities 勾上 **HealthKit** 和 **App Groups**
   → App Group 填 `group.<你的TeamID>.com.god.fitstate` → Register
3. **Identifiers** → **Devices** → `+` 注册 iPhone 的 UDID
   （iPhone 用 Safari 打开 <https://udid.tech>，页面上方直接显示）
4. **证书** 页建一个 Apple Development 证书并导出 `.p12`
5. 把 p12 与密码放进仓库的 Actions **Secrets**（`P12_BASE64` / `P12_PASSWORD`），
   CI 就能产出**正式签名**的 .ipa，一年内不用重签
6. 更进一步：开通 **Xcode Cloud**，push 完自动出包，连手动下载都省了

---

## 四、编译出 .ipa

### 4.1 方式 A：GitHub Actions（本文默认）

仓库：**https://github.com/Skzzz123/fitstate**（public，macOS runner 免费不限量）

**自动触发**：任何一次改动 `Sources/**`、`project.yml` 或 workflow 本身的 push，
都会自动跑一次编译。编译完在 Actions 运行页底部 **Artifacts** 区域下载 **FitState-ipa**，
解压得到 `FitState.ipa`。

**手动触发**：Actions → 左边选 **Build iOS App** → 右边 **Run workflow**，
有两个输入：

| 输入 | 含义 | 免费账号填什么 |
|---|---|---|
| `app_group_id` | 编译时**向 Apple 声明**的组（写进 entitlements） | 保持默认 `group.com.god.fitstate` |
| `app_group_runtime_id` | 运行时**真正去查容器**的组（写进 Info.plist） | `group.<你的TeamID>.com.god.fitstate` |

> 想让以后每次 push 都自动用上你的 App Group ID：
> 仓库 **Settings → Secrets and variables → Actions** 里加一个 **Variables**（不是 Secrets），
> 名字叫 `APP_GROUP_ID`（声明用）和 `APP_GROUP_RUNTIME_ID`（运行时用），值填你的 App Group ID。

### 4.2 这条流水线具体做了什么（以及为什么）

1. 选 runner 上最新的 Xcode（当前是 Xcode 26.3 / iOS 26.2 SDK）
2. `brew install xcodegen` → `xcodegen generate --spec project.yml` 生成工程
3. **未签名构建**：
   > Xcode 26+ 明确禁止用 ad-hoc 身份签 iOS 设备包
   > （`Ad Hoc code signing is not allowed with SDK 'iOS 26.2'`），
   > 所以这里先出无签名产物。
4. **手动 ad-hoc 签名**：用 `codesign --force --sign - --entitlements ...` 给主程序和
   小组件扩展分别盖上 ad-hoc 签名，并把 HealthKit / App Group 的 entitlements 真正写进二进制。
   **这一步很关键**——Sideloadly 重新签名时会读原包里的 entitlements，
   没有它就会丢能力，装上后读不到健康数据。
5. **三重校验**（防止再产出空壳 ipa）：主程序二进制、小组件扩展、小组件二进制必须都在，
   且最终 ipa 不得小于 50 KB。任何一项不满足直接让流水线失败。

### 4.3 方式 B：以后买了 Mac（可选）

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open FitState.xcodeproj
```

---

## 五、在 Windows 上装到 iPhone

### 5.1 装工具

| 工具 | 装到哪 | 说明 |
|---|---|---|
| **Sideloadly** | `%LOCALAPPDATA%\Sideloadly\` | 免管理员权限，装完就有 `sideloadly.exe` 和后台守护 `sideloadlydaemon.exe` |
| **iTunes（官网版）** | `C:\Program Files\iTunes\` | **必须官网版**。Microsoft Store 版驱动老，Sideloadly 经常认不到手机 |
| **iCloud（官网版）** | 可选 | 侧载本身用不到。想在 Windows 上同步 Apple 账号再装 |

**静默安装命令**（管理员 PowerShell）：

```powershell
Start-Process -FilePath .\iTunesSetup.exe -ArgumentList '/quiet','/norestart' -Verb RunAs -Wait
Start-Process -FilePath .\SideloadlySetup64.exe -ArgumentList '/S' -Verb RunAs -Wait
```

> **踩过的坑**：给 Apple 安装器传 `/log "D:\某个带空格的路径\log.txt"` 会报 **1622**
> （打不开安装日志文件）——`/log` 的路径不要带空格。
> iCloud 装完报 **1603** 是正常的：它要求重启。侧载不依赖 iCloud，可以先忽略。

> Sideloadly 自带设备通信层（`sideloadlydaemon.exe`），**不装「Apple 移动设备支持」也能连手机**，
> 不用特意去补这个组件。

### 5.2 用数据线连接

- iPhone 用数据线连电脑，**保持解锁状态**
- 手机上会弹「**信任此电脑吗？**」→ 点**信任** → 输入锁屏密码
  （不点信任的话，Sideloadly 的设备下拉框会是空的）
- Windows 设备管理器里应该能看到 `iPhone (Composite Parent)`
- Sideloadly 顶部设备下拉框里应该能看到你的 iPhone

### 5.3 签名并安装

1. 把 `FitState.ipa` 拖进 Sideloadly 窗口
2. **Apple account** 填你的 Apple ID（邮箱）
3. 确认设备选对，点 **Start**
4. 可能会要求输入密码或 Apple 发的双重验证码 → 照填
5. 装好后手机桌面出现「状态」图标

### 5.4 打开 App

1. iOS 16 及以上：第一次会提示需要**开发者模式**
   → 「设置 → 隐私与安全性 → 开发者模式」→ 打开 → 按提示重启手机
2. 如果提示「不受信任的开发者」：
   → 「设置 → 通用 → VPN 与设备管理」→ 点你的 Apple ID → **信任**
3. 打开 App → 点「去授权」→ 在系统弹窗里允许读取
   （睡眠分析含分期、HRV、静息心率、训练记录）

---

## 五点五、建议的冒烟测试顺序

别一上来就折腾小组件，按这个顺序来，每步都能独立判断成败：

1. **App 能不能装上并打开** → 装完先别管数据
2. **App 能不能读到数据** → 授权后「今日」页应该出现真实数字（哪怕只有睡眠时长）
3. **分数对不对** → 连续戴表 3 天以上，分数会从「基线建立中」变成稳定值
4. **小组件能不能显示** → 加到桌面，**先在 App 里打开一次**（App 每次启动都会把今日状态写进共享容器）
5. **小组件能不能刷新** → 长按小组件 → 刷新（会拉起 App，App 重算后回写）

第 4 步不显示的话，看文末「小组件一直显示打开 App 完成授权」那条。

---

## 六、添加主屏小组件

1. 长按 iPhone 桌面空白处 → 左上角 `+`
2. 搜「状态」→ 选小尺寸（155×155）或中尺寸（329×155）
3. 桌面出现后，等 App 打开过一次就会显示今日分数

---

## 七、每周要做的事

**免费 Apple ID 的签名证书 7 天到期**，到期后 App 打不开，需要重新签一次。

Sideloadly 可以自动处理：让它在后台运行，手机和电脑在同一个 WiFi 下，它会在到期前自动续签。
只要电脑开着、手机连着网，基本不用管。

如果哪天 App 打不开了（比如电脑关了好几天），手动再做一次 **Sideloadly → Start** 就行，数据不会丢。

---

## 八、常见问题

**Q：App 打开了但显示「数据不足，还算不出今天的分数」**
A：九成是权限没给。检查「设置 → 隐私与安全性 → 健康 → 状态」，把开关全部打开。
另外确认昨晚戴了表并且开了睡眠监测。

**Q：小组件一直显示「打开 App 完成授权」**
A：小组件靠 App Group 共享数据。先打开 App → 设置页最下面，看 **共享容器** 那一行：

- 显示「可用」→ App Group 是好的，问题在 App 还没刷新过；**打开一次 App** 让它写快照即可。
- 显示「不可用」→ App Group ID 对不上。核对两处：
  - 编译时 `app_group_runtime_id` 传的是 `group.<你的TeamID>.com.god.fitstate`
  - 你的 Team ID 就是签名工具改写后 bundle id 的最后一段
    （例如装上去是 `com.god.fitstate.97792VH57A` → Team ID 是 `97792VH57A`）
- 改完重新编译、重新安装，然后**打开一次 App**。

> App 里「设置 → 关于」会直接显示当前生效的 App Group 和 Bundle ID，
> 截图这两行就能一眼看出问题在哪。

**Q：没有睡眠分期（深睡/REM 都是 0）**
A：Apple Watch 需要 watchOS 9 或更高才会写睡眠分期。另外确认「设置 → 通用 → 锁定屏幕」里
「Apple Watch 自动开启睡眠监测」是打开的。

**Q：HRV 一直是空**
A：Apple Watch 默认在睡觉时测 HRV，而且只在「自动检测心率异常」相关的设置开启时才有较完整数据。
在 Watch 的「设置 → 睡眠」里确认开了睡眠追踪。另外 HRV 是**夜间**为主，白天几乎不测。

**Q：能改成我自己的图标和名字吗**
A：可以。改 `Sources/App/Assets.xcassets/AppIcon.appiconset/` 里的图标，
名称在 `Sources/App/Info.plist` 的 `CFBundleDisplayName`。

---

## 九、项目结构

```
fitstate/
├── project.yml                       # XcodeGen 工程定义（target / 权限 / 构建设置）
├── .github/workflows/build-ios.yml   # 云端编译，产出未签名 .ipa
├── Sources/
│   ├── Shared/                       # 主 App 与小组件共用
│   │   ├── AppGroup.swift            #   App Group 容器
│   │   ├── FitStateSnapshot.swift    #   共享快照模型
│   │   └── SnapshotStore.swift        #   快照读写
│   ├── App/
│   │   ├── FitStateApp.swift         # 入口 + 后台刷新
│   │   ├── Info.plist
│   │   ├── FitState.entitlements     # HealthKit + App Group
│   │   ├── Models/                   # DailyMetrics / Baseline / ScoreBreakdown
│   │   ├── Services/                 # HealthKitService / BaselineEngine / ScoringEngine / InsightEngine
│   │   └── Views/                    # 今日 / 趋势 / 设置
│   └── Widget/                       # WidgetKit 扩展
└── README.md
```

---

## 十、评分算法速查

| 维度 | 权重 | 公式 |
|---|---|---|
| HRV (SDNN) | 40% | `z = ln(今日 ÷ 基线) ÷ ln(1.15)`，`分 = clamp(50 + 22z, 0, 100)` |
| 睡眠 | 35% | `0.45×时长分 + 0.25×效率分 + 0.30×分期分` |
| 静息心率 | 25% | `z = (基线 − 今日) ÷ (0.03×基线)`，`分 = clamp(50 + 18z, 0, 100)` |

总分 = 各维度按权重加权（缺失项剔除后重新归一化）。
分档：85+ 极佳 / 70–84 良好 / 55–69 一般 / 40–54 欠佳 / <40 建议休息。

基线：滚动 30 天窗口 + **中位数**（抗离群值）+ 25–75 分位带；至少 7 天有效数据才给结论。
每一天都用「留一法」基线（算这天时基线不含这天），口径全程一致。
