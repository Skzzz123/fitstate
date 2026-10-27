# 状态 · 健身准备度 App

只给自己用的 iOS App：从 Apple Watch 同步进「健康」的**睡眠分期、HRV、静息心率**，
用你自己的 30 天基线做对照，算出今天的准备度分数和训练建议。

- 纯本地：无账号、无网络、无追踪，数据全在 iPhone 里
- 只读：只申请读取权限，永远不会往「健康」写入任何东西
- 小组件：主屏小尺寸 / 中尺寸，长按可刷新

> **这是一个纯技术仓库**：没有编译好的 App，只有源码和一条 CI 流水线。
> 你的电脑上不需要装 Xcode。

---

## 一、现在走到哪了

| 环节 | 状态 |
|---|---|
| 源码（20+ 个 Swift 文件）、评分引擎、界面、小组件 | ✅ 完成，静态校验 `PASS` |
| 云端 macOS 编译（GitHub Actions） | ✅ 跑通，每次 push 自动出 ipa |
| App 装进 iPhone、能打开 | ✅ 已验证 |
| 图标 | ✅ 换成你给的像素图（1024×1024，无透明通道） |
| HealthKit 权限 | ⏳ **卡在 Apple 侧授权**，见第二节 |

HealthKit 这项能力必须由 **Apple 在门户里给 App ID 授权**，任何第三方签名工具都做不到。
Apple 官方能力矩阵
（<https://developer.apple.com/help/account/reference/supported-capabilities-ios/>）
上 HealthKit 与 App Groups 在「Apple Developer（免费）」那一列**也是 ✅**，
表注里唯一的限制只有 MapKit 导航和地理文件上传——也就是说**免费档是支持的**，
只是「谁来点这个开关」没有现成工具。

已排除的路径（都实测过）：

- 把 entitlement 写进 ipa 签名 + 自造 `embedded.mobileprovision` → ❌ 装上仍报缺失
- 免费账号在门户手工勾能力 → ❌ `identifiers/list` 返回 *Access Unavailable — only for developers enrolled in a developer program*
- Sideloadly 免费版 → ❌ 二进制里根本没有 capability 名，只解析描述文件的 4 个键；能力清单来自 Patreon 认证的 `/caps` 接口
- 只订阅 Patreon → ❌ 官方更新说明写明要 **Patreon + $99 会员**双条件

**结论与解法**：能力是挂在 **App ID** 上的。我们直接调 Apple 门户的接口
（fastlane/spaceship 开源实现里的真实端点），给免费个人团队的 App ID 开启
HealthKit 与 App Groups，再自己申请证书和描述文件、自己签名 —— **全程 0 元**。

---

## 二、免费路线：开工三步

### 第 1 步：生成一个「App 专用密码」

打开 <https://appleid.apple.com/account/manage> 登录你的 Apple ID →
「登录和安全」→「App 专用密码」→「+」→ 名称随便填（比如 `FitState CI`）→ 生成。

会得到一串形如 `xxxx-xxxx-xxxx-xxxx` 的密码。

> 为什么用它：它免二次验证，可以直接被自动化程序用来登录开发者门户；
> 而且只授权「App 专用密码」这一项，随时可以在这里吊销，不影响你其它用途。

### 第 2 步：填两个仓库密钥

仓库 **Settings → Secrets and variables → Actions → New repository secret**，加两个：

| Secret 名 | 内容 |
|---|---|
| `APPLE_ID` | 你的 Apple ID 邮箱（`1512027523@qq.com`） |
| `APP_SPECIFIC_PASSWORD` | 第 1 步生成的 App 专用密码 |

> 密码只进 GitHub 的加密密钥库，不进仓库、不进日志。
> 私钥也只在 CI 内部流转，不会作为制品上传。

### 第 3 步：跑流水线

Actions → **Build iOS App** → **Run workflow**，`sign_mode` 选 **`portal`**，其余输入：

| 输入 | 填什么 |
|---|---|
| `sign_mode` | `portal` |
| `app_group_id` | `group.com.god.fitstate`（门户里注册时的名字，见下） |
| `app_group_runtime_id` | 同上 |
| `team_id` | `97792VH57A` |
| `final_bundle_id` | `com.god.fitstate` |
| `device_udid` | `00008140-00166C2636D2801C` |

流水线会依次做完：

1. `gem install fastlane` → 载入 spaceship（已验证可用）
2. `ruby Scripts/apple-portal.rb`：
   - 登录门户，列出你名下所有 App ID
   - 找到（或创建）`com.god.fitstate` 与 `com.god.fitstate.widget` 两个 App ID
   - **给主 App 开启 HealthKit**、给两个都开启 **App Groups**
   - 注册 App Group、注册设备 UDID
   - 申请开发证书 + 开发描述文件（描述文件里就带上了 healthkit 与 app groups）
3. 未签名构建（和现在一样）
4. `bash Scripts/sign-ipa.sh`：**用上面申请到的证书和描述文件正签**，
   entitlements 直接从描述文件里取
5. **硬闸门**：签名里没有 `com.apple.developer.healthkit` 就直接失败，
   不会给你一个「看着装上了其实没权限」的包
6. 打包成 `FitState.ipa` 上传为制品 **FitState-ipa**

> 想先看脚本干了什么，可以直接读仓库里的 `Scripts/apple-portal.rb`，
> 里面每一步都有中文注释和 `[portal]` 前缀的日志。

---

## 三、装机（正签包不要用 Sideloadly）

**Sideloadly 一定会用自己的 App ID 和证书重签**，那 HealthKit / App Groups 能力就又没了。
正签包要用「不重签」的工具装：

| 工具 | 说明 |
|---|---|
| **go-ios**（推荐，已下载到本机） | 命令行直装，不重签。`ios install --path FitState.ipa` |
| Apple Configurator 2 / Apple Devices | 把 ipa 拖到设备上即可 |
| iMazing | Apps → Install App |

装完手机上要**信任一次**开发者证书：

> 「设置 → 通用 → VPN 与设备管理」→ 点你的 Apple ID → **信任**

### 自由载包（`sign_mode=adhoc`）仍然用 Sideloadly

该模式只能验证界面跑不跑得起来，**没有 HealthKit 能力**，打开会报 entitlement 缺失。

---

## 四、编译与下载

**自动触发**：任何一次改动 `Sources/**`、`project.yml` 或 workflow 本身的 push，
都会自动跑一次编译（`adhoc` 模式）。编译完在 Actions 运行页底部 **Artifacts** 区域
下载 **FitState-ipa**，解压得到 `FitState.ipa`。

**手动触发**：Actions → 左边选 **Build iOS App** → 右边 **Run workflow**。

### 三种签名模式

| 模式 | 干什么 | 能不能用 HealthKit |
|---|---|---|
| `adhoc` | 未签名构建 + ad-hoc 签名 + 自造描述文件 | ❌ 仅验证 UI |
| `portal` | **门户直开能力 + 自签（免费，0 元）** | ✅ |
| `apple` | App Store Connect API Key + 正规签名（需 $99 会员） | ✅，且证书有效期 1 年 |

### `portal` 模式的校验点

- 主程序二进制、小组件扩展、小组件二进制必须都在
- 最终 ipa 不得小于 50 KB
- 描述文件里必须有 `com.apple.developer.healthkit`
- 描述文件里必须有 `com.apple.security.application-groups`
- 描述文件的 `ProvisionedDevices` 里必须有你的设备 UDID
- 最终签名的 entitlements 里必须有 `com.apple.developer.healthkit`

---

## 五、建议的冒烟测试顺序

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

## 七、证书有效期

免费个人团队的证书 **7 天到期**（这是 Apple 的规则，跟用什么工具无关）。
到期后重跑一次 `portal` 模式流水线、重新装一次即可，数据不会丢。

> 花钱的 `$99` 会员模式证书有效期 1 年，基本不用管。如果你想省心，等这条免费路线
> 验证通过之后再决定要不要升级。

---

## 八、保底方案：CSV 导入（零能力依赖）

万一 HealthKit 那条路最终走不通，App 还有一条**完全不需要任何 Apple 能力**的路：
从 CSV 读数据。

- 把 CSV 放进 App 的「文件」目录：
  - iPhone：「文件」App → 我的 iPhone → 状态
  - Windows：iTunes 的文件共享，拖进「状态」这个 App
- 文件名固定：`fitstate-import.csv`
- 列：`日期,HRV(ms),静息心率(bpm),睡眠时长(min),深睡(min),REM(min),在床(min)`
- 日期形如 `2026-10-27`，时长单位是分钟

数据可以用「快捷指令」的「查找健康记录」动作取（快捷指令本身有 HealthKit 权限），
再写成 CSV。App 会把 CSV 喂给**同一套**基线与评分引擎，今日页、趋势页照常出结果
（小组件仍然需要 App Groups 能力才能拿到数据）。

设置页里可以一键复制模板，也可以随时点「重新读取」。

---

## 九、常见问题

**Q：App 打开了但显示「数据不足，还算不出今天的分数」**
A：九成是权限没给。检查「设置 → 隐私与安全性 → 健康 → 状态」，把开关全部打开。
另外确认昨晚戴了表并且开了睡眠监测。

**Q：还是报 `Missing com.apple.developer.healthkit entitlement.`**
A：说明装上去的包不是正签包。只有 `portal`（或 `apple`）模式的产物才有这个能力；
如果你是用 Sideloadly 装的，它重新签名时已经把这项抹掉了 —— 按第三节换工具装。

**Q：小组件一直显示「打开 App 完成授权」**
A：小组件靠 App Group 共享数据。先打开 App → 设置页最下面，看 **共享容器** 那一行：

- 显示「可用」→ App Group 是好的，问题在 App 还没刷新过；**打开一次 App** 让它写快照即可。
- 显示「不可用」→ App Group ID 对不上。核对门户里注册的那个组名，
  和编译时的 `app_group_id` 是否完全一致。

> App 里「设置 → 关于」会直接显示当前生效的 App Group 和 Bundle ID，
> 截图这两行就能一眼看出问题在哪。

**Q：没有睡眠分期（深睡/REM 都是 0）**
A：Apple Watch 需要 watchOS 9 或更高才会写睡眠分期。另外确认「设置 → 通用 → 锁定屏幕」里
「Apple Watch 自动开启睡眠监测」是打开的。

**Q：HRV 一直是空**
A：Apple Watch 默认在睡觉时测 HRV，而且只在「自动检测心率异常」相关的设置开启时才有较完整数据。
在 Watch 的「设置 → 睡眠」里确认开了睡眠追踪。另外 HRV 是**夜间**为主，白天几乎不测。

**Q：能改成我自己的图标和名字吗**
A：可以。图标在 `Sources/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
（1024×1024、不能带透明通道），名称在 `Sources/App/Info.plist` 的 `CFBundleDisplayName`。

---

## 十、项目结构

```
fitstate/
├── project.yml                       # XcodeGen 工程定义（target / 权限 / 构建设置）
├── .github/workflows/
│   ├── build-ios.yml                 # 主流水线：adhoc / portal / apple 三种签名模式
│   └── toolchain-check.yml           #  spaceship 工具链自检
├── Scripts/
│   ├── apple-portal.rb               # 门户直开能力 + 申请证书与描述文件
│   ├── sign-ipa.sh                   # 用自有证书 + 描述文件正签
│   └── validate.ps1                  # 静态校验
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
│   │   ├── Services/                 # HealthKitService / ImportedHealthStore / BaselineEngine / ScoringEngine / InsightEngine
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
