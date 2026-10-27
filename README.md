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

## 三、在开发者门户做一次性设置（约 10 分钟）

这一步**不能跳过**：HealthKit 和 App Groups 是两项 capability，必须在 App ID 上启用，
否则 App 装上了也读不到数据。

### 3.1 拿到你的 Team ID

1. 打开 <https://developer.apple.com/account> → 点「Membership details」（或任意 App ID 页面）
2. 复制右上角的 **Team ID**（10 位大写字母数字，例如 `ABCDE12345`）

### 3.2 注册 App ID

1. 左侧 **Identifiers** → 右上角 `+` → 选 **App IDs**
2. Description 填 `FitState`
3. 选 **Explicit**（不用 Wildcard），Bundle ID 填：

   ```
   com.god.fitstate
   ```

4. 在 Capabilities 里打开这两项：
   - ✅ **HealthKit**
   - ✅ **App Groups**（并点 `+` 新建一个组，名字见下）
5. 继续 → Register

> App Group 的名字必须以你的 Team ID 开头：
> `group.<你的TeamID>.com.god.fitstate`
> 例如 Team ID 是 `ABCDE12345`，就填 `group.ABCDE12345.com.god.fitstate`

### 3.3 注册你的 iPhone

1. **Identifiers** → 左侧 **Devices** → `+`
2. 在 **iPhone 上用 Safari 打开 <https://udid.tech>**，页面上方会显示你的 UDID，复制
3. 粘贴 UDID，Name 填 `我的 iPhone` → Register

### 3.4 记下 App Group ID

把 `group.<你的TeamID>.com.god.fitstate` 记下来。后面编译时要用到它。

---

## 四、编译出 .ipa

### 方式 A：GitHub Actions（推荐）

1. 打开仓库 → **Actions** → 左边选 **Build iOS App** → 右边点 **Run workflow**
2. 在 `app_group_id` 里填第三步记下的 App Group ID（或者用默认的 `group.com.god.fitstate` 先试）
3. 等 3–6 分钟，绿色的 **Build unsigned .ipa** 跑完
4. 在这次运行的页面底部 **Artifacts** 区域下载 **FitState-ipa**
5. 解压后拿到 `FitState.ipa`

> 想让以后每次 push 都自动编译、并且省掉填 App Group ID 的麻烦：
> 在仓库 **Settings → Secrets and variables → Actions** 里加一个 **Variables**（不是 Secrets），
> 名字叫 `APP_GROUP_ID`，值填你的 App Group ID。

### 方式 B：以后买了 Mac（可选）

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open FitState.xcodeproj
```

---

## 五、在 Windows 上装到 iPhone

### 5.1 装三个工具

1. **Sideloadly**：<https://sideloadly.io> → 下载 Windows 版
2. **iTunes（官网版，不是 Microsoft Store 版）**：<https://www.apple.com/itunes>
   - Windows 电脑上如果装过 Microsoft Store 版 iTunes，先卸载
3. **iCloud（官网版）**：<https://www.apple.com/icloud> → 往下滑找「Windows 版 iCloud」

> **为什么强调官网版**：Microsoft Store 版 iTunes 的驱动版本老，Sideloadly 经常认不到手机。
> 装完 iTunes 后重启一次电脑。

### 5.2 用数据线连接

- iPhone 用数据线连电脑，解锁
- 手机上弹「信任此电脑吗？」→ **信任**
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
A：小组件靠 App Group 共享数据。先确认 App Group ID 和第三步注册的是同一个：
- 编译时传的 `app_group_id` 必须等于门户里建的组名
- 门户里的 App ID 必须勾选了 App Groups 并挂上了那个组
- 改完重新编译、重新安装，然后**打开一次 App**

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
