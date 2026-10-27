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
| **Apple Developer Program 会员（$99/年）** | **必需**。HealthKit 和 App Groups 这两项能力，只能靠付费团队在门户里给 App ID 授权（详见第三节） |
| 一个 GitHub 账号 | 跑云端 macOS 编译。仓库设为 Public 则免费不限量 |
| 一根数据线 | iPhone 首次装机时用 |
| Windows 上的装机工具 | 正签包用 **Apple Configurator 2 / Apple Devices / iMazing**；免费侧载包用 Sideloadly（见第五节） |

**为什么必须是付费会员**（2026-10-27 ~ 10-28 实测，结论已推翻本仓库早期版本的乐观判断）：

Apple 官方能力矩阵 <https://developer.apple.com/help/account/reference/supported-capabilities-ios/>
上，HealthKit 与 App Groups 在「Apple Developer（免费）」那一列**也是 ✅**，
表注里唯一的限制只有 MapKit 导航和地理文件上传。**但矩阵说的是「能力受支持」，
真正开权限的那一步，免费账号走不通**：

| 尝试过的路径 | 结果 |
|---|---|
| 把 `com.apple.developer.healthkit` 写进 ipa 签名 + 自造 `embedded.mobileprovision` | ❌ 装上后仍报 `Missing com.apple.developer.healthkit entitlement.` |
| 免费账号在开发者门户里勾选 App ID 能力 | ❌ `developer.apple.com/account/resources/identifiers/list` 返回 *Access Unavailable — This resource is only for developers enrolled in a developer program* |
| Sideloadly 免费版 | ❌ 它的二进制里**根本没有** capability 名，只解析描述文件里的 4 个键；能力清单来自 Patreon 认证的 `/caps` 接口，而官方更新说明写明该特性**需要 Patreon + $99 会员**双条件 |
| 单独订阅 Patreon | ❌ 同上，仍然要求 $99 |

**结论：HealthKit 这条路只有一个可靠入口 —— 加入 Apple Developer Program。**

---

## 二、把代码推上 GitHub

```powershell
cd "D:\minimax working\fitstate"
git init
git add .
git commit -m "feat: 状态 App 初始版本"
git branch -M main
git remote add origin https://github.com/<你的用户名>/fitstate.git
git push -u main
```

> 仓库设为 **Private** 时，GitHub 的 macOS 构建额度是每月 200 分钟（一次构建约 5 分钟，够用）。
> 但**私有仓库跑 macOS 任务需要绑一张卡**——把 Actions 的消费上限设成 $1 即可，实际不会扣费。
> 想完全避开绑卡，把仓库设为 Public 即可（Apple ID 密码等敏感信息本来也不在仓库里）。

---

## 三、Apple Developer Program 开通手册

> 这一节全是**你**要做的操作（付款、身份证验证、创建密钥），
> 剩下的门户配置、CI 出包、装机我来做。

### 3.1 加入开发者计划

1. 打开 <https://developer.apple.com/programs/> → 点「加入 Apple Developer Program」
2. 用你的 Apple ID 登录（**密码和双重验证码由你本人输入**）
3. 填个人/公司信息 → 同意 Apple 的付费协议 → **付款 $99**
4. 按提示做**身份验证**（上传身份证件、可能要求自拍）
   → 审核通过后账户页会出现「标识符 / 证书 / 描述文件」入口

> 审核通常几分钟到几天。期间可以先把代码和 CI 准备好（第四节已经就绪）。

### 3.2 注册 App ID 与能力（登录门户后我协助你点）

门户 → **Identifiers** → `+` → **App IDs** → **Explicit**：

| 项 | 填什么 |
|---|---|
| Description | `FitState` |
| Bundle ID | `com.god.fitstate` |
| Capabilities | 勾 **HealthKit**、勾 **App Groups**（并在下方填 `group.com.god.fitstate`） |

然后**再注册第二个 App ID**（小组件扩展要用）：

| 项 | 填什么 |
|---|---|
| Description | `FitState Widget` |
| Bundle ID | `com.god.fitstate.widget` |
| Capabilities | 勾 **App Groups**，填 `group.com.god.fitstate` |

### 3.3 注册设备

门户 → **Identifiers** → **Devices** → `+`：

| 项 | 填什么 |
|---|---|
| Platform | iOS |
| Device Name | 你的 iPhone 型号 |
| Device ID (UDID) | `00008140-00166C2636D2801C` |

> UDID 也可以在 iPhone 上用 Safari 打开 <https://udid.tech> 直接看到。
> **这一步不能漏**：开发描述文件必须列进目标设备，否则装不上。

### 3.4 创建 App Store Connect API Key

App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API** → `+`：

| 项 | 填什么 |
|---|---|
| Name | `FitState CI` |
| Access | **App Store Connect** |
| Role | **Admin**（只有 Admin 能创建证书/描述文件） |

点「创建」后立刻**下载 `AuthKey_XXXXXXXXXX.p8`**（只下这一次，Apple 不会再给）。
页面上同时显示 **Key ID** 和 **Issuer ID**。

把这三个值作为**仓库 Secrets** 加进去（Settings → Secrets and variables → Actions → New repository secret）：

| Secret 名 | 内容 |
|---|---|
| `ADP_KEY_P8_B64` | `AuthKey_XXXX.p8` 那个文件的 **base64** 编码 |
| `ADP_KEY_ID` | 页面上显示的 Key ID |
| `ADP_ISSUER_ID` | 页面上显示的 Issuer ID |

> base64 可以在 Windows 上这样生成：
> ```powershell
> [Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\Downloads\AuthKey_XXXX.p8"))
> ```

### 3.5 Team ID 从哪来

Team ID 是 10 位大写字母数字，**免费个人团队和付费团队是同一个**，本机实测是：

```
97792VH57A
```

CI 里默认已经填好了，不用改。

---

## 四、编译出 .ipa

### 4.1 流水线输入

Actions → 左边选 **Build iOS App** → 右边 **Run workflow**，有六个输入：

| 输入 | 含义 | 本项目填什么 |
|---|---|---|
| `sign_mode` | **签名模式**：`apple` = 正规签名（装机用）；`adhoc` = 免费侧载（只能验证 UI） | `apple` |
| `app_group_id` | 门户里注册的 App Group（写进 entitlements） | `group.com.god.fitstate` |
| `app_group_runtime_id` | 运行时真正去查容器的组（写进 Info.plist） | `group.com.god.fitstate` |
| `team_id` | 你的 Team ID | `97792VH57A` |
| `final_bundle_id` | 最终装到手机上的 bundle id（正签模式就是 `com.god.fitstate`） | `com.god.fitstate` |
| `device_udid` | 目标设备 UDID | `00008140-00166C2636D2801C` |

> `apple` 模式下 `app_group_id` 与 `app_group_runtime_id` 相同（都是门户里注册的那个组）。
> `adhoc` 模式下两者不同，因为签名工具会自己加 Team ID 前缀。

### 4.2 `apple` 模式具体做了什么

1. 选 runner 上最新的 Xcode → `brew install xcodegen` → `xcodegen generate --spec project.yml`
2. 把 `ADP_KEY_P8_B64` 解成 `AuthKey_<KeyID>.p8`
3. `xcodebuild ... -allowProvisioningUpdates -authenticationKeyPath ...`：
   - Xcode 用 API Key 去门户自动建 **App ID**、**开发证书**、**描述文件**
   - 描述文件里带 `com.apple.developer.healthkit = true` 和 `com.apple.security.application-groups`
   - 产出的 `.app` 自带 Apple 签的 `embedded.mobileprovision`
4. **三重硬闸门**（任何一条不满足就让流水线失败，不让你拿到一个「看着装上了其实没权限」的包）：
   - 描述文件的 Entitlements 里必须有 `com.apple.developer.healthkit`
   - 描述文件的 Entitlements 里必须有 `com.apple.security.application-groups`
   - 描述文件的 `ProvisionedDevices` 里必须有你的设备 UDID
5. 校验主程序二进制、小组件扩展、小组件二进制都在，且 ipa ≥ 50 KB
6. 打成 `FitState.ipa` 上传为制品 **FitState-ipa**（保留 30 天）

### 4.3 `adhoc` 模式（免费侧载，仅供验证 UI）

未签名构建 → `codesign --force --sign -` 盖 ad-hoc 签名 → 自造一份 CMS 外壳的
`embedded.mobileprovision` 骗签名工具。**这个模式出来的包没有 HealthKit 能力**，
装上会报 entitlement 缺失。它存在的意义只是「App 能不能装上、界面跑不跑得起来」。

### 4.4 以后买了 Mac（可选）

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open FitState.xcodeproj
```

---

## 五、在 Windows 上装到 iPhone

### 5.1 正签包（`apple` 模式产物）

**⚠️ 不要用 Sideloadly 装正签包。** Sideloadly 一定会用自己的 App ID 和证书重新签名，
会把 `HealthKit` / `App Groups` 能力又抹掉，等于白折腾。Sideloadly 的二进制里也确认过：
它没有「导入自有证书/描述文件」的入口。

用下面任意一个工具装（都是免费的）：

| 工具 | 怎么装 |
|---|---|
| **Apple Configurator 2**（Windows） | 装好后连上 iPhone → 左侧选中设备 → 把 `FitState.ipa` **直接拖到设备上** → 等进度条走完 |
| **Apple Devices**（Microsoft Store） | 同上，拖 ipa 到设备 |
| **iMazing**（Windows） | Apps → Install App → 选 `FitState.ipa` → 选设备 → Install |

装完后手机会要求**信任开发者证书**（一次性）：

> 「设置 → 通用 → VPN 与设备管理」→ 点你的 Apple ID（`1512027523@qq.com`）→ **信任**

### 5.2 免费侧载包（`adhoc` 模式产物）

1. 把 `FitState.ipa` 拖进 Sideloadly 窗口（**注意**：Sideloadly 的拖放区点了不弹文件框，
   要用命令行 `sideloadly.exe "<ipa 路径>"` 才会加载）
2. **Apple account** 填你的 Apple ID（邮箱）
3. 确认设备选对，点 **Start**
4. 可能会要求输入密码或 Apple 发的双重验证码 → 照填

### 5.3 打开 App

1. iOS 16 及以上：第一次会提示需要**开发者模式**
   → 「设置 → 隐私与安全性 → 开发者模式」→ 打开 → 按提示重启手机
2. 打开 App → 点「去授权」→ 在系统弹窗里允许读取
   （睡眠分析含分期、HRV、静息心率、训练记录）
3. 出现**授权面板**就是成功标志——免费侧载那条路上这个面板从来就没出现过

---

## 六、建议的冒烟测试顺序

别一上来就折腾小组件，按这个顺序来，每步都能独立判断成败：

1. **App 能不能装上并打开** → 装完先别管数据
2. **App 能不能读到数据** → 授权后「今日」页应该出现真实数字（哪怕只有睡眠时长）
3. **分数对不对** → 连续戴表 3 天以上，分数会从「基线建立中」变成稳定值
4. **小组件能不能显示** → 加到桌面，**先在 App 里打开一次**（App 每次启动都会把今日状态写进共享容器）
5. **小组件能不能刷新** → 长按小组件 → 刷新（会拉起 App，App 重算后回写）

第 4 步不显示的话，看文末「小组件一直显示打开 App 完成授权」那条。

---

## 七、添加主屏小组件

1. 长按 iPhone 桌面空白处 → 左上角 `+`
2. 搜「状态」→ 选小尺寸（155×155）或中尺寸（329×155）
3. 桌面出现后，等 App 打开过一次就会显示今日分数

---

## 八、证书有效期

| 模式 | 有效期 | 到期怎么办 |
|---|---|---|
| `apple`（正签） | 开发证书 **1 年**，描述文件跟证书走 | 到期前重新跑一次 `apple` 模式流水线装回去；App 内的数据不受影响 |
| `adhoc`（免费侧载） | **7 天** | Sideloadly 开着就能自动续签；或手动再点一次 Start |

---

## 九、常见问题

**Q：App 打开了但显示「数据不足，还算不出今天的分数」**
A：九成是权限没给。检查「设置 → 隐私与安全性 → 健康 → 状态」，把开关全部打开。
另外确认昨晚戴了表并且开了睡眠监测。

**Q：还是报 `Missing com.apple.developer.healthkit entitlement.`**
A：说明装上去的包**不是正签包**。只有 `sign_mode=apple` 的产物才有这个能力；
如果你是用 Sideloadly 装的，它重新签名时已经把这项抹掉了 —— 用第五节 5.1 的方法装。

**Q：小组件一直显示「打开 App 完成授权」**
A：小组件靠 App Group 共享数据。先打开 App → 设置页最下面，看 **共享容器** 那一行：

- 显示「可用」→ App Group 是好的，问题在 App 还没刷新过；**打开一次 App** 让它写快照即可。
- 显示「不可用」→ App Group ID 对不上。正签模式下应该是 `group.com.god.fitstate`，
  和门户里注册的那个组名一模一样。

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

## 十、项目结构

```
fitstate/
├── project.yml                       # XcodeGen 工程定义（target / 权限 / 构建设置）
├── .github/workflows/build-ios.yml   # 云端编译，双签名模式
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

## 十一、评分算法速查

| 维度 | 权重 | 公式 |
|---|---|---|
| HRV (SDNN) | 40% | `z = ln(今日 ÷ 基线) ÷ ln(1.15)`，`分 = clamp(50 + 22z, 0, 100)` |
| 睡眠 | 35% | `0.45×时长分 + 0.25×效率分 + 0.30×分期分` |
| 静息心率 | 25% | `z = (基线 − 今日) ÷ (0.03×基线)`，`分 = clamp(50 + 18z, 0, 100)` |

总分 = 各维度按权重加权（缺失项剔除后重新归一化）。
分档：85+ 极佳 / 70–84 良好 / 55–69 一般 / 40–54 欠佳 / <40 建议休息。

基线：滚动 30 天窗口 + **中位数**（抗离群值）+ 25–75 分位带；至少 7 天有效数据才给结论。
每一天都用「留一法」基线（算这天时基线不含这天），口径全程一致。
