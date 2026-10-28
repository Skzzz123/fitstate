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
| 自签流水线（解描述文件 → 提 entitlements → codesign → 校验） | ✅ CI 用假证书完整跑通，签名里 healthkit + app groups 都在 |
| **数据入口（0 元路线）** | ✅ **App Intent +「快捷指令」已实现**，不需要任何 Apple 能力 |
| 快捷指令输出解析 | ✅ 多格式容错（JSON / 纯文本 / 中英文），分通道归类，跨零点时长正确 |
| 输出格式自助排查 | ✅ 回执自带「每通道收了多少字 + 原文摘要」；App 里留最近一次原文，一键复制 |
| HealthKit 直接读取 | ❌ **免费账号拿不到**，门户被官方硬锁（见下） |
| 主屏小组件 | ⚠️ 需要 App Group，免费账号暂时拿不到（$99 路线有） |

### 免费账号为什么拿不到 HealthKit（实测结论）

2026-10-28 用真实登录态在浏览器里实测了开发者门户：

```
developer.apple.com/account/resources/identifiers/list
→ "Access Unavailable
   This resource is only for developers enrolled in a developer program
   or members of an organization's team in a developer program."
```

这是 Apple 对**免费 Apple Account** 的硬限制，不是我们脚本的问题。
配套证据也齐：

- 侧载包（免费账号签出来的）描述文件里 **既没有 `com.apple.developer.healthkit`，
  也没有 `com.apple.security.application-groups`** —— 能力压根没进包
- 缺 HealthKit entitlement 的包一碰 `HKHealthStore` 就会被系统杀掉，
  所以 App 现在会先读自己的描述文件判断能力，没有就**完全不碰 HealthKit**
  （`Sources/App/Services/HealthKitAvailability.swift`）

Apple 官方能力矩阵
（<https://developer.apple.com/help/account/reference/supported-capabilities-ios/>）
上 HealthKit 与 App Groups 在「Apple Developer（免费）」那一列确实也是 ✅，
但表头那句话才是关键：**"The capabilities available to an iOS provisioning
profile depend on your program membership."** —— 免费账号拿不到描述文件，
自然也拿不到能力。

### 那 0 元怎么用？—— 快捷指令 + App Intent

**App Intent 不需要任何能力**（不需要 HealthKit、不需要 App Groups、不需要推送），
而 iOS 自带的「快捷指令」能读「健康」App。于是：

```
「快捷指令」动作「查找健康记录」×3（HRV / 静息心率 / 睡眠分析）
        ↓
App Intent「记录今日健康数据」  →  本地 JSON
                                    ↓
                        基线 + 评分引擎（同一套）
                                    ↓
                            分数 / 建议 / 趋势 / 导出
```

- 快捷指令还能配**个人自动化**（每天早上 7:00 自动跑），等于自动更新
- App Intent 在后台执行，不拉起 App，不联网，没有账号
- 数据只写在这台 iPhone 的沙盒里

**三个「原始数据」参数是分通道的** —— HRV 那一路只会被当成 HRV，
静息心率那一路只会被当成静息心率。所以即使输出里一个单位名都没有，
App 也能正确归类；HRV 取**中位数**、静息心率取**平均**，
跟 HealthKit 直读的口径完全一致。

「查找健康记录」的输出格式没有公开文档，所以还做了两件事：
- **多格式容错解析器**（`HealthTextParser.swift`）：JSON 数组 / 纯文本 /
  中文英文都认，跨零点的睡眠时段（23:30 → 06:45）也算得对
- **粘贴自检台**（App 内「设置 → 快捷指令喂数据 → 打开粘贴自检」）：
  把输出粘进去，立刻看到解析结果和**没认出来的原文**，不用靠猜

实现见 `Sources/App/Services/HealthIntents.swift`、
`Sources/App/Services/HealthTextParser.swift` 与
`Sources/App/Services/ManualHealthStore.swift`，操作步骤见第十二节。

### 小组件：为什么它需要 App Group

主 App 和小组件是两个进程，沙盒互相看不见，**唯一官方的共享通道就是 App Group**
（`UserDefaults(suiteName:)` 也一样）。免费账号拿不到 App Group，
所以免费路线下小组件暂时显示不了真实分数——这是 Apple 的限制，
不是代码能绕过去的。想让小组件也工作，只剩两条路：

1. 付 $99 加入 Apple Developer Program（`sign_mode=apple`，证书 1 年，HealthKit + App Groups 全有）
2. 拿到能用的 App 专用密码后走 `sign_mode=portal`，脚本会在免费团队上试开
   App Group（能否开成功取决于 Apple 后端对免费团队的策略，本仓库尚未实测成功）

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
| `app_group_id` | `group.97792VH57A.com.god.fitstate`（免费团队必须带 Team ID 前缀；脚本会自动纠正写法） |
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

- 主程序二进制、小小组件扩展、小组件二进制必须都在
- 最终 ipa 不得小于 50 KB
- 描述文件里必须有 `com.apple.developer.healthkit`
- 描述文件里必须有 `com.apple.security.application-groups`
- 描述文件的 `ProvisionedDevices` 里必须有你的设备 UDID
- 最终签名的 entitlements 里必须有 `com.apple.developer.healthkit`

### 静态校验（`Scripts/validate.ps1`）

本机没有 Mac，Swift 代码只能靠云端编译验证 —— 一次往返好几分钟。
所以校验器除了常规检查（结构、括号配平、类型重名、import 匹配、
Info.plist 键、YAML），还做了五件别人得等 xcodebuild 才发现的事：

| 检查项 | 典型报错 |
|---|---|
| 9. ViewBuilder 里的 Void 语句 | `type '()' cannot conform to 'View'` |
| 10. Swift 保留字当标识符 | `'case' label can only appear inside a 'switch' statement` |
| 11. **解析器逻辑自测** | 跨零点算成负数、多值取错、无单位归错类 |
| 12. **Intent 字面量参数** | `cannot convert value of type 'String' to expected argument type 'IntentDialog'` |
| 13. **健康导出转换器自测** | 导出转 CSV 算错一天，基线就偏 |

第 9、10、12 条都做过**反向验证**（故意写一段坏代码，确认校验器能精准定位到那一行），
避免「规则本身是坏的」这种更隐蔽的问题。

第 12 条查的是 `.result(dialog:)` 的参数 —— `IntentDialog` 只认字符串字面量，
写成 `"a" + b` 类型就变了，编译期才炸。这条就是踩过一次之后补上的。

第 11 条跑的是 `Scripts/parser-selftest.ps1` —— 一份与 Swift 解析器等价的
逻辑镜像（PowerShell），18 条断言覆盖最容易悄悄算错的地方（含 2 条合并规则、
5 条文本参数防护）。
本机没有 Swift 工具链时，改完解析规则先跑它，秒出结果，不用等 CI。

```powershell
# 完整静态校验（含解析器自测）
powershell -NoProfile -ExecutionPolicy Bypass -File "Scripts\validate.ps1"

# 只跑解析器自测
powershell -NoProfile -ExecutionPolicy Bypass -File "Scripts\parser-selftest.ps1"
```

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

## 八、CSV 导入（零能力依赖，**现在的主路径**）

App 有一条**完全不需要任何 Apple 能力**的路：从 CSV 读数据。
它现在是主力 —— 因为免费账号拿不到 HealthKit，HealthKit 直读这条路是死的。

- 把 CSV 放进 App 的「文件」目录：
  - iPhone：「文件」App → 我的 iPhone → 状态
  - Windows：iTunes 的文件共享，拖进「状态」这个 App
- 文件名固定：`fitstate-import.csv`
- 列：`日期,HRV(ms),静息心率(bpm),睡眠时长(min),深睡(min),REM(min),在床(min)`
- 日期形如 `2026-10-27`，时长单位是分钟

数据可以用「快捷指令」的「查找健康记录」动作取（快捷指令本身有 HealthKit 权限），
再写成 CSV。App 会把 CSV 喂给**同一套**基线与评分引擎，今日页、趋势页照常出结果
（小组件仍然需要 App Groups 能力才能拿到数据）。

### 30 天历史一次性补齐（推荐）

快捷指令一天存一天，**攒够 7 天才有基线、30 天基线才稳**。
但「健康」App 里其实已经有 30 天历史 —— 导出来就行：

1. iPhone：「健康」→ 右上角头像 → **「导出所有健康数据」** → 得到一个 zip
2. 把 zip 弄到电脑上（微信「文件传输助手」/邮件都行）
3. 电脑上跑转换器（纯标准库，不用装任何东西）：

   ```bash
   python Scripts/health-export-to-csv.py export.zip -o fitstate-import.csv
   ```

4. 把 `fitstate-import.csv` 放进 App 的「文件」目录（同上：iPhone 上「文件」App →
   我的 iPhone → 状态；或 Windows 上 iTunes 拖进去）
5. 回 App 下拉刷新 → 基线立刻可用

转换器的口径**和 App 内 HealthKit 直读完全一致**（对齐 `HealthKitService.swift`）：

| 指标 | 规则 |
|---|---|
| 睡眠归属 | 前一天 16:00 → 当天 20:00 这个「夜里」算作**醒来的那一天** |
| 睡眠总时长 | 深睡 + REM + 核心 + 未分期（各自分段时长累加） |
| 在床 | 有 `InBed` 分段就用它；Apple Watch 不写 InBed 时用「总睡眠 + 清醒」 |
| HRV | 优先取夜里窗口的**中位数**，取不到再退回当天所有样本的中位数 |
| 静息心率 | 当天所有样本的**平均值** |

> 「在床」这一条踩过坑：早先只累加 InBed，而 Apple Watch 的导出里 **InBed 几乎为 0**，
> 于是睡眠效率的分母是 0，效率项恒定落在兜底值 70 上，基线里的效率分是假的。
> 现在没有 InBed 就用「总睡眠 + 清醒」，和直读口径一致 —— 效率是真算出来的。

### 三个来源怎么合（`DataMerger.swift`）

CSV 和快捷指令的数据**逐字段**合并，优先级 **HealthKit > 快捷指令 > CSV**。

**为什么不能「按天整条去重」**：同一天里，不同来源覆盖的指标并不一样。
快捷指令那次跑，HRV 和静息心率通了，但睡眠通道只拿到分期名、没有时长，
于是快捷指令写下来的这一天是「有 HRV、有心率、但睡眠 = 0」。
如果按整天取一条，CSV 里那天的睡眠（时长、深睡、REM 全都有）就会被整条丢掉 ——
结果是**今天明明有睡眠数据，App 却显示睡眠 0 分钟**，睡眠那 35% 权重直接消失。

规则：
- **逐字段**取：优先级高的来源有值就用它的，没有才用低优先级的；
- **睡眠四项整组处理**（总时长 / 深睡 / REM / 在床），绝不拆开混搭 ——
  拿 A 来源的时长配 B 来源的深睡，算出来的「修复性睡眠比例」是假的。

### 基线窗口口径（`Baseline.swift`）

算任意一天，基线都只取「**那一天之前**」的 N 天（滚动 30 天，中位数 + 25/75 分位带）：

- 算今天 → 基线 = 前 30 天（不含今天）
- 算历史某天 → 基线 = 那一天之前的 30 天，**绝不把后来的数据算进过去**

早先取的是「除当天外所有天的最后 30 天」，历史点的基线里混进了未来数据，
趋势图会失真，而且同一条曲线里今天和历史点用的不是同一把尺子。

> 转换器有回归测试：`Scripts/validate.ps1` 第 13 条会用样例导出跑一遍，
> 输出必须逐行一致才通过。

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
│   ├── validate.ps1                  # 静态校验（13 项，含 Swift 编译期错误预检）
│   ├── health-export-to-csv.py       # 「健康」App 导出 → FitState CSV（30 天历史补齐）
│   └── parser-selftest.ps1           # 解析器 + 合并规则 + 文本参数防护逻辑自测（21 条断言，无 Mac 也能跑）
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
│   │   ├── Services/
│   │   │   ├── HealthKitService.swift      # 直读「健康」App（需要 HealthKit 能力）
│   │   │   ├── HealthKitAvailability.swift # 能力守卫：没能力就完全不碰 HealthKit
│   │   │   ├── HealthIntents.swift         # App Intent 入口（0 元路线）
│   │   │   ├── HealthTextParser.swift     # 快捷指令输出的多格式解析器
│   │   │   ├── NumericSampleParser.swift   # 文本抽数值 + 中位数/平均
│   │   │   ├── IntentValueParser.swift     # 数值参数（文本框）→ 安全数值，认不出就拒
│   │   │   ├── IntentPayloadStore.swift    # 最近一次收到的原文留档（排查用）
│   │   │   ├── ManualHealthStore.swift     # 手动数据源本地 JSON 存储
│   │   │   ├── ImportedHealthStore.swift   # CSV 兜底导入
│   │   │   ├── BaselineEngine.swift / ScoringEngine.swift / InsightEngine.swift
│   │   │   └── AppState.swift             # 数据源合并（HealthKit > 快捷指令 > CSV）
│   │   └── Views/                    # 今日 / 趋势 / 设置 / 粘贴自检
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

---

## 十二、快捷指令操作步骤（0 元路线）

App 里有两个可用的 App Intent：

| 动作名 | 参数 | 适合 |
|---|---|---|
| **记录今日健康数据** | 睡眠分析原始数据、HRV原始数据、静息心率原始数据（都可空）+ 数字兜底参数 + 日期 | **推荐**，把「查找健康记录」的输出整包丢进去 |
| **用一行文本记录健康数据** | 一行文本：`HRV,静息心率,睡眠时长,深睡,REM,在床[,日期]` | 已经在快捷指令里算好了单值 |

> **关键**：三个「原始数据」参数是**分通道**的 ——
> HRV 那一路只会被当成 HRV，静息心率那一路只会被当成静息心率。
> 所以即使输出里一个单位名都没有，App 也能正确归类。
> HRV 取**中位数**、静息心率取**平均**，跟 HealthKit 直读口径完全一致。

### 手工跑一次（先验证通不通）

1. 打开「快捷指令」→ 右上「+」→ 搜索「查找健康记录」
2. 选 **心率变异性 (SDNN)**
   → 排序方式 **结束日期 / 最近的排最前**（别用「值」排序，那是随机取）
   → 开始日期 **今天**
3. 再加一个「查找健康记录」→ 选 **静息心率**
   → 排序方式 **结束日期 / 最近的排最前**，开始日期 **今天**
4. 再加一个「查找健康记录」→ 选 **睡眠分析**
   → 开始日期 **昨天**（昨晚 22 点入睡的样本开始日期是昨天，
   填「今天」会把整晚漏掉，睡眠时长直接算成 0）
5. 每个「查找健康记录」后面各加一个 **组合文本**，把它的输出接进去
   → ❗ **只有睡眠那个「组合文本」的类型要改成 JSON**。
     睡眠样本的**短文本只有分期名**（REM / Core / Deep / Awake，一行一个），
     **不带起止时间** —— App 只能知道「昨晚有几个 REM」，算不出任何时长。
     换成 JSON 后每条记录都带 `startDate` / `endDate`，时长、分期才算得出来。
   → HRV 和静息心率那两个**保持短文本**（它们要的正是纯数值，一行一个数）
   → ❗ **后面不要加「从文本获取数字」**。那一步会把文本变成一列数字，
     睡眠的分期关键词（深睡 / REM / 在床）和起止时间就全丢了，
     App 只能算出一堆乱七八糟的时长。**App 自己会认分期、算总时长**，
     你不需要先求和。正确链路就两步：`查找 → 合并文本 → 运行 App`
6. 给三个「查找」都加上 **「值 是 任何内容」** 筛选条件（很容易漏），
   避免取到没有数值的空样本
7. 加一个 **运行 App** 动作 → 搜 FitState → 选「记录今日健康数据」
   → 三段组合文本分别接到 **「HRV原始数据」「静息心率原始数据」「睡眠分析原始数据」**
   → 接上后参数右边会变成**蓝色变量名**；还是灰色占位符就是没接上
   → 后面 6 个数值参数现在是**文本框**（不是数字框），**留空即可**；
     接错也只会忽略并在回执里说明，不会报错、更不会写脏数据
   → 「解析诊断」填 **1**（第一次跑带完整诊断）
8. 运行。快捷指令会回一句「已记录 2026-10-28，睡眠 452 分钟（深睡 86 / REM 121），今日状态分 78（良好）」
9. 回到 FitState App，下拉刷新就能看到分数

> **嫌步骤多就用「用一行文本记录健康数据」**：
> 前面的查找动作各自取到值后用「组合文本」拼成 `48,54,452,86,121,500`，
> 再喂给这个 App Intent，一个参数搞定。

### 同一天重复记录，不会把已有数据抹掉

快捷指令有**三条互相独立**的通道（HRV / 静息心率 / 睡眠）。任何一条偶发失败
——最常见的是「查找健康记录(睡眠分析)」当天返回空——如果直接整条覆盖，
这一天已经记好的数据就全被抹成 0，而 30 天基线是靠每天一条攒出来的，
**用户根本不会察觉**，只看到「今天睡眠 0 分钟」。

所以写入走的是**合并**（`ManualHealthStore.merged`）：

| 字段 | 规则 |
|---|---|
| HRV / 静息心率 | 新值有就用新值，没有就**保留旧值** |
| 睡眠四项（时长/深睡/REM/在床） | 新记录有睡眠就**整组**用新值；否则**整组**保留旧值（不混搭，避免时长和分期对不上） |

另外两条细节：

- **数值参数逐项优先**。填了「睡眠时长(分钟)=452」就以你填的为准，
  没填的「深睡 / REM / 在床」仍沿用原始文本通道解析出来的结果；
  填了但**认不出来**（时间戳、接错通道）就忽略，绝不当成数字写进去。
- **回执里的分数算的是刚写进去的那条记录**，不是「库里最后一条」——
  补记昨天时不会显示成今天的分。

### 排查：粘贴自检

「查找健康记录」的输出格式**没有公开文档**，不同 iOS 版本出来的东西可能不一样。
App 里有个自检工具能免去反复试错：

**设置 → 快捷指令喂数据 → 打开粘贴自检**

1. 选通道（睡眠分析 / 心率变异性 / 静息心率）
2. 把组合文本的输出复制进来，点「解析看看」
3. 直接看到 App 读出了什么：HRV 读到几个值、中位数多少；睡眠分成几段、
   深睡 REM 各多少分钟；以及**哪几段没认出来**（连原文一起显示）

同一屏还有「**跑一遍解析器自检**」按钮，会跑 22 条断言覆盖最容易悄悄算错的地方：

| 用例 | 验证什么 |
|---|---|
| 睡眠英文分期 + 起止时间 | 深睡/REM/核心分别累加正确 |
| **睡眠跨零点（23:30 → 06:45）** | 跨午夜算 435 分，不是负数 |
| 睡眠中文分期 | 「深睡 / 快速眼动 / 清醒」认得出 |
| 睡眠无分期关键词 | 退化成按相邻时间点配对，总时长不丢 |
| **睡眠缺分期名** | 段内时间点两两配对，后半段时长不丢（原来会少算一半） |
| HRV 多值 | 取中位数（抗离群），不是取第一个 |
| **HRV 无单位** | 靠通道归类，不会被误判成静息心率 |
| 静息心率多值 | 取平均 |
| JSON 数组输出 | `{"Type":…,"Value":…}` 结构认得出 |
| **JSON 睡眠输出** | 分期名在 `value` 里也能认出（REM / Deep 不被记成「未分期」） |
| 三通道混在一段文本 | 各归各类，互不串台 |
| 在床分段 | 单独累加 |
| 认不出来的片段 | 进未识别列表，**不污染数据** |
| 时长 0 的分段 | 不计入统计 |
| **合并：新数据没睡眠** | 保留这一天**已有**的睡眠，不被抹成 0 |
| **合并：新数据有睡眠** | 整组替换（时长和分期对得上），HRV 等缺的项保留旧值 |
| 文本参数：纯数字 | 「452」「452 分钟」「48」直接认出来 |
| 文本参数：认不出就拒绝 | 「22:30」不会被当成 22 分钟 |
| 文本参数：接错通道拒绝 | 睡眠文本接到 HRV 上 → 忽略，不写脏数据 |
| 文本参数：单值接受、多值无单位拒绝 | 分不清是哪个指标时宁可不写 |
| **只有分期名的短文本** | 认得出来，并能提示「把组合文本改成 JSON」 |
| **参数里的 0** | 视为「没填」，不会把解析出来的睡眠时长覆盖成 0 |

> 这套断言不只跑在 App 里 —— `Scripts/validate.ps1` 之外，
> 还有一份等价逻辑镜像（`Scripts/parser-selftest.ps1`，PowerShell，21 条）
> 可以在没有 Mac 的机器上直接跑，改完解析规则先跑它再提交。
> 镜像也覆盖了 JSON 分支，所以两边行为是一致的。

快捷指令动作里还有个「**解析诊断（填1=详细回执）**」参数，填 1 时，
运行回执会附带完整诊断 —— 所有读到的值 + 没认出来的原文。

### 排查：回执自带诊断 + App 里留原文

**失败时的回执一定会报每个通道实收了多少字**：

```
没记上：睡眠数据没解析出来｜收到 睡眠1203字/HRV45字/心率12字｜睡眠原文：深度睡眠, 2026-10-27 22:30 …
```

- 「收到…字」= 快捷指令**真正送进来**的字符数 → 一眼看出是哪个通道空着
- 原文摘要 = 直接看到格式长什么样，不用猜

**App 里也留了一份原文**：「设置 → 快捷指令喂数据 → 最近一次收到的原文」，
显示快捷指令送进来的全部内容，一键复制。
（存在 `Application Support/FitState/fitstate-last-payload.json`，只留最近一次。）

### 为什么 6 个数值参数是文本框

原来是 `Double`。用户把「组合文本」的输出接上去时，
**快捷指令会在调用 App Intent 之前就抛「无法将文本转换为数字」而中止** ——
Intent 根本没被调起来，App 里一条数据都没有，回执也看不到。

现在这 6 个参数全是**文本框**，接什么都不报错。App 自己判断：

- 填了纯数字 → 直接用
- 填了带单位的一批样本 → 按这个通道取中位数 / 平均
- 认不出来（时间戳、别的东西、接错通道）→ **忽略**，并在回执里说明

宁可少写一条，也绝不让脏数据污染 30 天基线。

### 每天自动跑

「快捷指令」右上角 → **自动化** → 「新建自动化」→ 时间 **每天早上 7:00**
→ 依次选上面那些动作 → 打开「运行前询问」关掉。

这样每天早上 Apple Watch 的数据同步进「健康」之后，分数会自动更新。

### 数据存在哪

`Application Support/FitState/fitstate-manual.json`，只在这台 iPhone 上，
可在「设置 → 数据 → 生成 CSV」导出。卸载 App 会一起删掉。

### 快捷指令给不了的东西

- **训练记录**（走 HealthKit 的 workoutType，免费账号拿不到）—— 趋势里的训练标记会缺
- **小组件**（需要 App Group，免费账号拿不到）—— 小组件会显示「等待数据」
- **自动的 30 天基线**：基线是拿已有的历史数据算的，快捷指令喂了几天就有几天，
  满 7 天才开始出结论，满 30 天基线才稳
