$ErrorActionPreference = 'Stop'
$root = 'D:\minimax working\fitstate'
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Info($m) { Write-Output "  $m" }

# ---------------------------------------------------------------- 1. 目录与工程定义
Write-Output "`n=== 1. 工程结构 ==="
$required = @(
  'project.yml',
  '.github\workflows\build-ios.yml',
  'README.md',
  'Sources\App\Info.plist',
  'Sources\App\FitState.entitlements',
  'Sources\Widget\Info.plist',
  'Sources\Widget\FitStateWidget.entitlements',
  'Sources\Shared\AppGroup.swift',
  'Sources\Shared\FitStateSnapshot.swift',
  'Sources\Shared\SnapshotStore.swift'
)
foreach ($r in $required) {
  if (-not (Test-Path (Join-Path $root $r))) { $errors.Add("缺失文件: $r") }
}
Info "必需文件检查完毕"

$swift = Get-ChildItem -Path (Join-Path $root 'Sources') -Filter '*.swift' -Recurse
Info "Swift 源文件: $($swift.Count) 个"

# ---------------------------------------------------------------- 2. 括号配平
Write-Output "`n=== 2. 括号配平 ==="
foreach ($f in $swift) {
  $text = Get-Content $f.FullName -Raw -Encoding UTF8
  # 粗略剔除字符串与注释，避免误判
  $stripped = [regex]::Replace($text, '(?s)/\*.*?\*/', '')
  $stripped = [regex]::Replace($stripped, '(?m)//.*$', '')
  $stripped = [regex]::Replace($stripped, '(?s)"(?:\\.|[^"\\])*"', '""')
  $stripped = [regex]::Replace($stripped, "(?s)'(?:\\.|[^'\\])*'", "''")
  foreach ($pair in @(@('{','}'), @('(',')'), @('[',']'))) {
    $o = ([regex]::Matches($stripped, [regex]::Escape($pair[0]))).Count
    $c = ([regex]::Matches($stripped, [regex]::Escape($pair[1]))).Count
    if ($o -ne $c) { $errors.Add("括号不配平 $($pair[0])$($pair[1]) in $($f.Name): $o vs $c") }
  }
}
Info "括号配平检查完毕"

# ---------------------------------------------------------------- 3. 类型声明表
Write-Output "`n=== 3. 类型声明与跨 target 冲突 ==="
$declRe = '(?m)^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+|open\s+|final\s+)*(struct|class|enum|actor|protocol)\s+([A-Za-z_]\w*)'
$typeOwner = @{}
foreach ($f in $swift) {
  $text = Get-Content $f.FullName -Raw -Encoding UTF8
  foreach ($m in [regex]::Matches($text, $declRe)) {
    $name = $m.Groups[2].Value
    $rel = $f.FullName.Substring($root.Length + 1)
    if ($typeOwner.ContainsKey($name)) {
      $errors.Add("重复类型定义 `$name` : $($typeOwner[$name]) 与 $rel")
    } else {
      $typeOwner[$name] = $rel
    }
  }
}
Info "声明类型: $($typeOwner.Count) 个"

# target 归属：App = App+Shared, Widget = Widget+Shared
function Get-TargetFiles($kind) {
  if ($kind -eq 'app') {
    return $swift | Where-Object { $_.FullName -match '\\Sources\\(App|Shared)\\' }
  } else {
    return $swift | Where-Object { $_.FullName -match '\\Sources\\(Widget|Shared)\\' }
  }
}
foreach ($kind in @('app','widget')) {
  $set = @{}
  foreach ($f in (Get-TargetFiles $kind)) {
    $text = Get-Content $f.FullName -Raw -Encoding UTF8
    foreach ($m in [regex]::Matches($text, $declRe)) {
      $n = $m.Groups[2].Value
      if ($set.ContainsKey($n)) { $errors.Add("[$kind target] 类型重复: $n") }
      $set[$n] = $true
    }
  }
  Info "$kind target 内类型无冲突（$($set.Count) 个）"
}

# ---------------------------------------------------------------- 3b. 重载签名等价检查
Write-Output "`n=== 3b. 重载签名等价检查（typealias 重复声明） ==="
$funcRe = '(?m)^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+|static\s+|class\s+|final\s+|mutating\s+|nonmutating\s+|override\s+|convenience\s+|required\s+|weak\s+|lazy\s+)*func\s+([A-Za-z_]\w*)\s*(\([^)]*\))'
$ownerRe = '(?m)^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+|final\s+)*(?:struct|class|enum|actor|extension|protocol)\s+([A-Za-z_]\w*)'
foreach ($f in $swift) {
  $text = Get-Content $f.FullName -Raw -Encoding UTF8

  # 同一个类型里的同名同参函数才是真的重复声明（typealias 陷阱）。
  # 不同类型里各有一个 perform() 是完全合法的，所以必须按「所属类型」分组。
  $owners = @()
  foreach ($m in [regex]::Matches($text, $ownerRe)) {
    $owners += [pscustomobject]@{ Index = $m.Index; Name = $m.Groups[1].Value }
  }

  $byKey = @{}
  foreach ($m in [regex]::Matches($text, $funcRe)) {
    $owner = '<文件级>'
    foreach ($o in $owners) {
      if ($o.Index -lt $m.Index) { $owner = $o.Name } else { break }
    }
    $name = $m.Groups[1].Value
    $params = ($m.Groups[2].Value -replace '\s+', '')
    $key = "$owner|$name"
    if (-not $byKey.ContainsKey($key)) { $byKey[$key] = @() }
    $byKey[$key] += $params
  }
  foreach ($key in $byKey.Keys) {
    $list = $byKey[$key]
    if ($list.Count -lt 2) { continue }
    for ($i = 0; $i -lt $list.Count; $i++) {
      for ($j = $i + 1; $j -lt $list.Count; $j++) {
        $a = $list[$i] -replace 'TimeInterval', 'Double'
        $b = $list[$j] -replace 'TimeInterval', 'Double'
        if ($a -eq $b) {
          $errors.Add("重载签名等价（typealias 导致重复声明）: func $name $($list[$i])  ($($f.Name))")
        }
      }
    }
  }
}
Info "重载等价检查完毕"

# ---------------------------------------------------------------- 4. 成员交叉引用
Write-Output "`n=== 4. Type.member 引用检查 ==="
$memberCache = @{}
function Get-Members($name) {
  if ($memberCache.ContainsKey($name)) { return $memberCache[$name] }
  $members = New-Object System.Collections.Generic.HashSet[string]
  $rel = $typeOwner[$name]
  if ($rel) {
    $text = Get-Content (Join-Path $root $rel) -Raw -Encoding UTF8
    $m = [regex]::Match($text, $declRe.Replace('\(\?m\)\^', '') + '')
    # 定位声明位置后截取该类型的花括号体
    $idx = $text.IndexOf($name)
    if ($idx -ge 0) {
      $brace = $text.IndexOf('{', $idx)
      if ($brace -ge 0) {
        $depth = 0; $i = $brace
        while ($i -lt $text.Length) {
          if ($text[$i] -eq '{') { $depth++ }
          elseif ($text[$i] -eq '}') { $depth--; if ($depth -eq 0) { break } }
          $i++
        }
        $body = $text.Substring($brace, $i - $brace)
        foreach ($mm in [regex]::Matches($body, '(?m)^\s*(?:@\w+\s+)*(?:public\s+|internal\s+|private\s+|fileprivate\s+|static\s+|class\s+|final\s+|mutating\s+|nonmutating\s+|override\s+|convenience\s+|required\s+|weak\s+|lazy\s+)*(?:func|var|let|case|init|typealias)\s+`?([A-Za-z_]\w*)')) {
          [void]$members.Add($mm.Groups[1].Value)
        }
      }
    }
  }
  $memberCache[$name] = $members
  return $members
}

$knownTypes = $typeOwner.Keys
$checkedRefs = 0
foreach ($f in $swift) {
  $text = Get-Content $f.FullName -Raw -Encoding UTF8
  foreach ($m in [regex]::Matches($text, '\b([A-Z][A-Za-z0-9_]*)\.([a-z][A-Za-z0-9_]*)')) {
    $type = $m.Groups[1].Value
    $member = $m.Groups[2].Value
    if ($knownTypes -notcontains $type) { continue }
    if ($member -eq 'self') { continue }
    $checkedRefs++
    $members = Get-Members $type
    if ($members.Count -gt 0 -and -not $members.Contains($member)) {
      $warnings.Add("可能不存在的成员: $type.$member  ($($f.Name))")
    }
  }
}
Info "检查了 $checkedRefs 处 Type.member 引用"

# ---------------------------------------------------------------- 5. 未声明标识符
Write-Output "`n=== 5. 未声明的大写标识符 ==="
$system = @(
 'SwiftUI','Foundation','HealthKit','WidgetKit','AppIntents','Charts','UIKit','Combine','Darwin','Dispatch','MainActor','ObservableObject','EnvironmentObject','Published','State','StateObject','Binding','View','Text','Image','Button','VStack','HStack','ZStack','Spacer','ScrollView','ForEach','LazyVStack','LazyHStack','Section','Group','Divider','ProgressView','Slider','Picker','Toggle','TextField','SecureField','List','NavigationStack','NavigationLink','NavigationSplitView','TabView','Alert','Sheet','Color','Font','Angle','Edge','Alignment','Namespace','GeometryReader','Canvas','TimelineView','Gauge','Label','LabeledContent','Menu','ShareLink','Date','DateFormatter','Calendar','TimeZone','Locale','UUID','URL','Data','String','Int','Double','Bool','Array','Dictionary','Set','Optional','Result','Task','Actor','MainActor','Any','AnyObject','Void','Error','Equatable','Codable','Hashable','Identifiable','Comparable','Sendable','TimeInterval','DispatchQueue','Locale','ObjectIdentifier','Mirror','Regex','Duration','Clock','ContinuousClock','IndexPath','Range','ClosedRange','StrideThrough','Sequence','Collection','RandomAccessCollection','Formatter','NumberFormatter','Measurement','Unit','URLSession','FileManager','Bundle','UserDefaults','NotificationCenter','JSONEncoder','JSONDecoder','DateFormatter','IndexSet','FileHandle','Process','Timer','RunLoop','Locale','CFBundle','HKHealthStore','HKObjectType','HKQuantityType','HKCategoryType','HKCategoryValueSleepAnalysis','HKQuantitySample','HKCategorySample','HKSample','HKWorkout','HKQuery','HKSampleQueryDescriptor','HKQuantityQueryDescriptor','HKStatisticsCollectionQuery','HKUnit','SortDescriptor','HKAuthorizationRequestStatus','BGTaskScheduler','BGAppRefreshTask','BGAppRefreshTaskRequest','WidgetCenter','TimelineProvider','Timeline','TimelineEntry','WidgetBundle','WidgetConfiguration','StaticConfiguration','AppIntent','IntentResult','LocalizedStringResource','LocalizedStringResource','View','XCTAssert','Notification','Shape','StrokeStyle','Font','Mark','Chart','ChartBuilder','AxisMarks','AxisValueLabel','AxisGridLine','DateComponents','Calendar','Stat','NSNumber','NSPredicate','AnyCancellable','Set','URLSession','TabView','Scene','App','WindowGroup','AnyView','PreviewProvider','Binding','StringProtocol','Substring','StaticString','Mirror','Unicode','UnicodeScalar','Unicode','ClosedRange','FloatingPoint','Numeric','Strideable','ExpressibleByIntegerLiteral','ExpressibleByFloatLiteral','ExpressibleByStringLiteral','CaseIterable','RawRepresentable','TextOutputStream','Encodable','Decodable','CodingKey','Decoder','Encoder','CustomStringConvertible','LosslessStringConvertible','Comparable','Equatable','AnyHashable','Hasher','CodingUserInfoKey','Scanner','Index','String','Character','Substring','Array','Set','Dictionary','Optional','Never','Void','AnyObject','Any','Self','Type','Metatype','Unmanaged','UnsafePointer','UnsafeMutablePointer','MemoryLayout','Stride','UnsafeMutableBufferPointer','UnsafeBufferPointer','Manifold'
'BackgroundTasks','LocalizedError','ViewModifier','Content','ViewBuilder','RoundedRectangle','LineMark','PointMark','AreaMark','BarMark','AxisMarks','AxisValueLabel','AxisGridLine','Chart','ChartBuilder','Context','Shape','StrokeStyle','Mark','Font','Text','Scene','App','WindowGroup','AnyView','SceneStorage','AppStorage','Environment','EnvironmentValues','WidgetFamily','WidgetConfiguration','WidgetCenter','TimelineProvider','Timeline','TimelineEntry','WidgetBundle','StaticConfiguration','AppIntent','IntentResult','LocalizedStringResource','BGTaskScheduler','BGAppRefreshTask','BGAppRefreshTaskRequest','TabView','Picker','ShareLink','Label','Menu','Gauge','Canvas','Divider','Section','Group','Spacer','ProgressView','Slider','Toggle','TextField','SecureField','List','NavigationStack','NavigationLink','GeometryReader','ForEach','LazyVStack','LazyHStack','ZStack','VStack','HStack','Button','Image','Text','Color','Font','Edge','Angle','Alignment','Namespace','View','State','Binding','StateObject','EnvironmentObject','ObservableObject','Published','Task','Actor','MainActor','Int','Double','Bool','String','Date','Data','URL','UUID','Array','Dictionary','Set','Optional','Result','Error','Void','Any','AnyObject','Equatable','Hashable','Codable','Identifiable','Comparable','Sendable','TimeInterval','Calendar','TimeZone','Locale','Bundle','FileManager','UserDefaults','JSONEncoder','JSONDecoder','NotificationCenter','DispatchQueue','Timer','Process','HKHealthStore','HKObjectType','HKQuantityType','HKCategoryType','HKCategoryValueSleepAnalysis','HKQuantitySample','HKCategorySample','HKSample','HKWorkout','HKQuery','HKSampleQueryDescriptor','HKQuantityQueryDescriptor','HKUnit','SortDescriptor','HKAuthorizationRequestStatus','UIApplication','UIImage','UIColor','CFBundle','NSError','NSPredicate','Notification'
) | Sort-Object -Unique

$used = New-Object System.Collections.Generic.HashSet[string]
foreach ($f in $swift) {
  $text = Get-Content $f.FullName -Raw -Encoding UTF8
  $noStr = [regex]::Replace($text, '(?s)"(?:\\.|[^"\\])*"', '""')
  $noStr = [regex]::Replace($noStr, '(?s)/\*.*?\*/', '')
  $noStr = [regex]::Replace($noStr, '(?m)//.*$', '')
  foreach ($m in [regex]::Matches($noStr, '\b([A-Z][A-Za-z0-9_]{2,})\b')) {
    [void]$used.Add($m.Groups[1].Value)
  }
}
$unknown = @()
foreach ($u in $used) {
  if ($typeOwner.ContainsKey($u)) { continue }
  if ($system -contains $u) { continue }
  if ($u -match '^(NS|UI|CG|CF|CA|CI|AV|MK|WK|SF|CT|CM|IN)[A-Z]') { continue }
  $unknown += $u
}
if ($unknown.Count -gt 0) {
  $warnings.Add("未在源码中声明的大写标识符（可能是系统类型或笔误）: " + ($unknown -join ', '))
}
Info "使用到 $($used.Count) 个大写标识符"

# ---------------------------------------------------------------- 6. import 检查
Write-Output "`n=== 6. import 与 API 使用匹配 ==="
foreach ($f in $swift) {
  $text = Get-Content $f.FullName -Raw -Encoding UTF8
  $code = [regex]::Replace($text, '(?s)/\*.*?\*/', '')
  $code = [regex]::Replace($code, '(?m)//.*$', '')
  $code = [regex]::Replace($code, '(?s)"(?:\\.|[^"\\])*"', '""')
  $needs = @()
  if ($code -match '\bHK(HealthStore|ObjectType|QuantityType|CategoryType|QuantitySample|CategorySample|Workout|Query|SampleQueryDescriptor|QuantityQueryDescriptor|Unit|Sample)\b') { $needs += 'HealthKit' }
  if ($code -match '\b(Chart|LineMark|PointMark|BarMark|AreaMark|AxisMarks)\b') { $needs += 'Charts' }
  if ($code -match '\bWidgetCenter|TimelineProvider|WidgetBundle|StaticConfiguration\b') { $needs += 'WidgetKit' }
  if ($code -match '\bAppIntent\b|\bIntentResult\b') { $needs += 'AppIntents' }
  if ($code -match '\bBGTaskScheduler\b|\bBGAppRefreshTask\b') { $needs += 'BackgroundTasks' }
  if ($code -match '\bUIApplication\b') { $needs += 'UIKit' }
  foreach ($n in $needs) {
    if ($text -notmatch "import\s+$n\b") { $errors.Add("$($f.Name) 使用了 $n 但缺少 import") }
  }
}
Info "import 检查完毕"

# ---------------------------------------------------------------- 7. Info.plist 键
Write-Output "`n=== 7. Info.plist 键 ==="
$appPlist = Get-Content (Join-Path $root 'Sources\App\Info.plist') -Raw -Encoding UTF8
$wPlist  = Get-Content (Join-Path $root 'Sources\Widget\Info.plist') -Raw -Encoding UTF8
foreach ($k in @('NSHealthShareUsageDescription','BGTaskSchedulerPermittedIdentifiers','AppGroupIdentifier','CFBundleDisplayName','CFBundleURLTypes','UIBackgroundModes')) {
  if ($appPlist -notmatch [regex]::Escape($k)) { $errors.Add("App Info.plist 缺少 $k") }
}
foreach ($k in @('NSExtensionPointIdentifier','AppGroupIdentifier')) {
  if ($wPlist -notmatch [regex]::Escape($k)) { $errors.Add("Widget Info.plist 缺少 $k") }
}
if ($wPlist -notmatch 'com\.apple\.widgetkit-extension') { $errors.Add("Widget Info.plist 缺少 widgetkit-extension 标识") }
$appEnt = Get-Content (Join-Path $root 'Sources\App\FitState.entitlements') -Raw -Encoding UTF8
if ($appEnt -notmatch 'com\.apple\.developer\.healthkit') { $errors.Add("App entitlements 缺少 healthkit") }
if ($appEnt -notmatch 'com\.apple\.security\.application-groups') { $errors.Add("App entitlements 缺少 application-groups") }
$wEnt = Get-Content (Join-Path $root 'Sources\Widget\FitStateWidget.entitlements') -Raw -Encoding UTF8
if ($wEnt -notmatch 'com\.apple\.security\.application-groups') { $errors.Add("Widget entitlements 缺少 application-groups") }
Info "Info.plist / entitlements 检查完毕"

# ---------------------------------------------------------------- 8. YAML 基础检查
Write-Output "`n=== 8. YAML 检查 ==="
foreach ($y in @('project.yml', '.github\workflows\build-ios.yml')) {
  $lines = Get-Content (Join-Path $root $y)
  $lineNo = 0
  foreach ($l in $lines) {
    $lineNo++
    if ($l -match "`t") { $errors.Add("$y 第 $lineNo 行含 Tab（YAML 不允许）") }
  }
  if ($y -eq 'project.yml') {
    $txt = $lines -join "`n"
    foreach ($k in @('FitState:','FitStateWidget:','INFOPLIST_FILE','CODE_SIGN_ENTITLEMENTS','APP_GROUP_ID','embed: true','app-extension','application')) {
      if ($txt -notmatch [regex]::Escape($k)) { $errors.Add("project.yml 缺少 $k") }
    }
  } else {
    $txt = $lines -join "`n"
    foreach ($k in @('runs-on: macos','xcodegen generate','xcodebuild','upload-artifact','zip -qry')) {
      if ($txt -notmatch [regex]::Escape($k)) { $errors.Add("workflow 缺少 $k") }
    }
  }
}
Info "YAML 检查完毕"

# ---------------------------------------------------------------- 汇总
Write-Output "`n================ 结果 ================"
if ($errors.Count -eq 0) {
  Write-Output "PASS: 无错误"
} else {
  Write-Output "ERRORS ($($errors.Count)):"
  $errors | ForEach-Object { Write-Output "  [E] $_" }
}
if ($warnings.Count -gt 0) {
  Write-Output ""
  Write-Output "WARNINGS ($($warnings.Count)):"
  $warnings | ForEach-Object { Write-Output "  [W] $_" }
}
Write-Output ""
