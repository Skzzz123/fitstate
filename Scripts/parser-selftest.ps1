$ErrorActionPreference = 'Stop'

# HealthTextParser 的逻辑镜像（PowerShell 版），用于本机验证解析规则。
# 对应 Swift 源码：Sources/App/Services/HealthTextParser.swift

function Get-Moments {
    param([string]$Text)

    $now = Get-Date
    $matches = New-Object System.Collections.ArrayList

    # A: 2026-10-27 23:15:00 / 2026年10月27日 23:15
    $reA = [regex]'(?<y>\d{4})\s*[-/.年]\s*(?<mo>\d{1,2})\s*[-/.月]\s*(?<d>\d{1,2})\s*日?(?:\s*[T,，\-–—]?\s*(?<h>\d{1,2}):(?<mi>\d{2})(?::(?<s>\d{2}))?)?'
    foreach ($m in $reA.Matches($Text)) {
        $hasTime = $m.Groups['h'].Success
        [void]$matches.Add([pscustomobject]@{
            Start = $m.Index; End = $m.Index + $m.Length
            Y = [int]$m.Groups['y'].Value; Mo = [int]$m.Groups['mo'].Value; D = [int]$m.Groups['d'].Value
            H = if ($hasTime) { [int]$m.Groups['h'].Value } else { 0 }
            Mi = if ($hasTime) { [int]$m.Groups['mi'].Value } else { 0 }
            S = if ($hasTime -and $m.Groups['s'].Success) { [int]$m.Groups['s'].Value } else { 0 }
            TimeOnly = $false
        })
    }

    # B: 10月27日 23:15
    $reB = [regex]'(?<mo>\d{1,2})\s*月\s*(?<d>\d{1,2})\s*日(?:\s*[T,，\-–—]?\s*(?<h>\d{1,2}):(?<mi>\d{2})(?::(?<s>\d{2}))?)?'
    foreach ($m in $reB.Matches($Text)) {
        $overlap = $false
        foreach ($k in $matches) { if (-not ($m.Index + $m.Length -le $k.Start -or $m.Index -ge $k.End)) { $overlap = $true; break } }
        if ($overlap) { continue }
        $hasTime = $m.Groups['h'].Success
        [void]$matches.Add([pscustomobject]@{
            Start = $m.Index; End = $m.Index + $m.Length
            Y = $now.Year; Mo = [int]$m.Groups['mo'].Value; D = [int]$m.Groups['d'].Value
            H = if ($hasTime) { [int]$m.Groups['h'].Value } else { 0 }
            Mi = if ($hasTime) { [int]$m.Groups['mi'].Value } else { 0 }
            S = if ($hasTime -and $m.Groups['s'].Success) { [int]$m.Groups['s'].Value } else { 0 }
            TimeOnly = $false
        })
    }

    # C: 08:00:00
    $reC = [regex]'(?<![\d:])(\d{1,2}):(\d{2})(?::(\d{2}))?(?![\d:])'
    foreach ($m in $reC.Matches($Text)) {
        $overlap = $false
        foreach ($k in $matches) { if (-not ($m.Index + $m.Length -le $k.Start -or $m.Index -ge $k.End)) { $overlap = $true; break } }
        if ($overlap) { continue }
        [void]$matches.Add([pscustomobject]@{
            Start = $m.Index; End = $m.Index + $m.Length
            Y = $now.Year; Mo = 1; D = 1
            H = [int]$m.Groups[1].Value; Mi = [int]$m.Groups[2].Value
            S = if ($m.Groups[3].Success) { [int]$m.Groups[3].Value } else { 0 }
            TimeOnly = $true
        })
    }

    # 合并：时间单独出现且紧挨着只有日期的片段
    $ordered = @($matches | Sort-Object Start)
    $combined = New-Object System.Collections.ArrayList
    foreach ($m in $ordered) {
        if ($combined.Count -gt 0) {
            $prev = $combined[$combined.Count - 1]
            if ($m.TimeOnly -and -not $prev.TimeOnly -and ($m.Start - $prev.End) -le 3) {
                $prev.H = $m.H; $prev.Mi = $m.Mi; $prev.S = $m.S
                $prev.TimeOnly = $false; $prev.End = $m.End
                continue
            }
        }
        [void]$combined.Add([pscustomobject]@{
            Start = $m.Start; End = $m.End; Y = $m.Y; Mo = $m.Mo; D = $m.D
            H = $m.H; Mi = $m.Mi; S = $m.S; TimeOnly = $m.TimeOnly
        })
    }

    # 抹掉日期片段
    $cleaned = $Text
    for ($i = $combined.Count - 1; $i -ge 0; $i--) {
        $c = $combined[$i]
        $cleaned = $cleaned.Substring(0, $c.Start) + ' ' + $cleaned.Substring($c.End)
    }

    return [pscustomobject]@{ Moments = @($combined); Cleaned = $cleaned }
}

function Get-DurationBetween {
    param($A, $B)

    $secA = $A.H * 3600 + $A.Mi * 60 + $A.S
    $secB = $B.H * 3600 + $B.Mi * 60 + $B.S

    if ($A.TimeOnly -and $B.TimeOnly) {
        $d = $secB - $secA
        if ($d -lt 0) { $d += 86400 }
        return $d
    }

    if ($B.TimeOnly) {
        $start = (Get-Date -Year $A.Y -Month $A.Mo -Day $A.D -Hour $A.H -Minute $A.Mi -Second $A.S)
        $end = (Get-Date -Year $A.Y -Month $A.Mo -Day $A.D -Hour $B.H -Minute $B.Mi -Second $B.S)
        $d = ($end - $start).TotalSeconds
        if ($d -lt 0) { $d += 86400 }
        return $d
    }

    if ($A.TimeOnly) {
        $start = (Get-Date -Year $B.Y -Month $B.Mo -Day $B.D -Hour $A.H -Minute $A.Mi -Second $A.S)
        $end = (Get-Date -Year $B.Y -Month $B.Mo -Day $B.D -Hour $B.H -Minute $B.Mi -Second $B.S)
        $d = ($end - $start).TotalSeconds
        if ($d -lt 0) { $d += 86400 }
        return $d
    }

    $start = (Get-Date -Year $A.Y -Month $A.Mo -Day $A.D -Hour $A.H -Minute $A.Mi -Second $A.S)
    $end = (Get-Date -Year $B.Y -Month $B.Mo -Day $B.D -Hour $B.H -Minute $B.Mi -Second $B.S)
    return ($end - $start).TotalSeconds
}

function Get-DurationFromText {
    param([string]$Text)
    $m = [regex]::Match($Text, '(\d+)\s*小时\s*(\d+)?\s*分?')
    if ($m.Success) {
        $h = [double]$m.Groups[1].Value
        $mi = if ($m.Groups[2].Success) { [double]$m.Groups[2].Value } else { 0 }
        return $h * 3600 + $mi * 60
    }
    $m = [regex]::Match($Text, '(\d+)\s*分(?:钟)?')
    if ($m.Success) { return [double]$m.Groups[1].Value * 60 }
    $m = [regex]::Match($Text, '(\d+)\s*秒')
    if ($m.Success) { return [double]$m.Groups[1].Value }
    return $null
}

$sleepKeywords = @(
    @('asleepdeep', 'deep'), @('asleeprem', 'rem'), @('asleepcore', 'core'),
    @('asleepunspecified', 'unspecified'), @('inbed', 'inBed'), @('awake', 'awake'),
    @('深睡', 'deep'), @('深度睡眠', 'deep'), @('快速眼动', 'rem'),
    @('核心睡眠', 'core'), @('未分期', 'unspecified'), @('在床', 'inBed'), @('清醒', 'awake')
)

function Get-SleepStage {
    param([string]$Raw)
    $v = $Raw.ToLowerInvariant()
    foreach ($kv in $sleepKeywords) {
        if ($v.Contains($kv[0])) { return $kv[1] }
    }
    $tokens = [regex]::Split($v, '[^a-z0-9]+') | Where-Object { $_ -ne '' }
    foreach ($t in @('deep', 'rem', 'core', 'awake', 'inbed', 'unspecified')) {
        if ($tokens -contains $t) { return $t }
    }
    return $null
}

function Test-HRVUnit { param([string]$u) $u = $u.ToLowerInvariant().Replace(' ', ''); return $u.Contains('毫秒') -or $u -eq 'ms' -or $u.StartsWith('ms') -or $u.Contains('millisecond') }
function Test-RHRUnit { param([string]$u) $u = $u.ToLowerInvariant().Replace(' ', ''); return $u.Contains('次/分') -or $u.Contains('次每分') -or $u.Contains('次／分') -or $u.Contains('拍/分') -or $u.Contains('bpm') -or $u.Contains('count/min') -or $u.Contains('beats/min') }
function Test-HRVName { param([string]$t) $t = $t.ToLowerInvariant(); return $t.Contains('心率变异性') -or $t.Contains('heart rate variability') -or $t.Contains('sdnn') -or $t.Contains('hrv') }
function Test-RHRName { param([string]$t) $t = $t.ToLowerInvariant(); return $t.Contains('静息心率') -or $t.Contains('resting heart rate') -or $t.Contains('rhr') }
function Test-SleepName { param([string]$t) $t = $t.ToLowerInvariant(); return $t.Contains('睡眠分析') -or $t.Contains('sleep analysis') }

$unitRe = [regex]'(\d+(?:\.\d+)?)\s*(毫秒|ms|MS|次每分|次/分|次／分|拍/分|bpm|BPM|count/min)'
$valueRe = [regex]'(?<![\d:.\-])\d+(?:\.\d+)?(?![\d:.\-])'

function Invoke-Parse {
    param([string]$Text, [string]$Hint = 'unknown')

    $o = [pscustomobject]@{
        Samples = @(); Unrecognized = @()
        Hrv = @(); Rhr = @()
        SleepTotal = 0.0; SleepDeep = 0.0; SleepRem = 0.0; SleepCore = 0.0
        SleepUnspec = 0.0; SleepAwake = 0.0; SleepInBed = 0.0; SleepCount = 0
    }
    $Text = $Text.Trim()
    if (-not $Text) { return $o }

    foreach ($lineRaw in ($Text -split "`r?`n")) {
        $line = $lineRaw.Trim()
        if (-not $line) { continue }

        $isSleepChannel = ($Hint -eq 'sleep') -or (Test-SleepName $line)

        if ($isSleepChannel) {
            $hits = New-Object System.Collections.ArrayList
            $low = $line.ToLowerInvariant()
            foreach ($kv in $sleepKeywords) {
                $idx = 0
                while ($true) {
                    $pos = $low.IndexOf($kv[0], $idx)
                    if ($pos -lt 0) { break }
                    [void]$hits.Add([pscustomobject]@{ Start = $pos; End = $pos + $kv[0].Length; Stage = $kv[1]; Len = $kv[0].Length })
                    $idx = $pos + 1
                }
            }
            $unique = New-Object System.Collections.ArrayList
            foreach ($h in ($hits | Sort-Object Len -Descending)) {
                $overlap = $false
                foreach ($u in $unique) { if (-not ($h.End -le $u.Start -or $h.Start -ge $u.End)) { $overlap = $true; break } }
                if (-not $overlap) { [void]$unique.Add($h) }
            }
            $ordered = @($unique | Sort-Object Start)

            if ($ordered.Count -gt 0) {
                for ($i = 0; $i -lt $ordered.Count; $i++) {
                    $segStart = if ($i -eq 0) { 0 } else { $ordered[$i - 1].End }
                    $segEnd = if ($i + 1 -lt $ordered.Count) { $ordered[$i + 1].Start } else { $line.Length }
                    $piece = $line.Substring($segStart, $segEnd - $segStart)
                    $mom = Get-Moments $piece
                    if ($mom.Moments.Count -ge 2) {
                        $dur = Get-DurationBetween $mom.Moments[0] $mom.Moments[1]
                    } else {
                        $dur = Get-DurationFromText $mom.Cleaned
                    }
                    Add-SleepSample $o $ordered[$i].Stage $dur $piece
                }
                continue
            }
            else {
                $mom = Get-Moments $line
                if ($mom.Moments.Count -ge 2) {
                    for ($i = 0; $i -lt $mom.Moments.Count - 1; $i++) {
                        $dur = Get-DurationBetween $mom.Moments[$i] $mom.Moments[$i + 1]
                        if ($dur -gt 0) { Add-SleepSample $o 'unspecified' $dur $line }
                    }
                    continue
                }
            }
        }

        # 数值通道：先找「数值 + 单位」
        $hits = @()
        foreach ($m in $unitRe.Matches($line)) {
            $unit = $m.Groups[2].Value.ToLowerInvariant()
            $val = [double]$m.Groups[1].Value
            if (Test-HRVUnit $unit) { $hits += , @('hrv', $val) }
            elseif (Test-RHRUnit $unit) { $hits += , @('rhr', $val) }
        }
        if ($hits.Count -gt 0) {
            foreach ($h in $hits) {
                if ($h[0] -eq 'hrv') { $o.Hrv += $h[1] } else { $o.Rhr += $h[1] }
                $o.Samples += $h[0]
            }
            continue
        }

        # 兜底
        $mom = Get-Moments $line
        $stage = Get-SleepStage $line
        if ($stage) {
            if ($mom.Moments.Count -ge 2) { $dur = Get-DurationBetween $mom.Moments[0] $mom.Moments[1] }
            else { $dur = Get-DurationFromText $mom.Cleaned }
            Add-SleepSample $o $stage $dur $line
            continue
        }
        $m = $unitRe.Match($line)
        if ($m.Success) { continue }

        $kind = 'unknown'
        if (Test-HRVName $line) { $kind = 'hrv' }
        elseif (Test-RHRName $line) { $kind = 'rhr' }
        elseif (Test-SleepName $line) { $kind = 'sleep' }
        elseif ($Hint -eq 'hrv' -or $Hint -eq 'rhr') { $kind = $Hint }

        if ($kind -eq 'hrv' -or $kind -eq 'rhr') {
            $values = @($valueRe.Matches($mom.Cleaned) | ForEach-Object { [double]$_.Value })
            if ($values.Count -eq 0) { $o.Unrecognized += $line }
            else {
                foreach ($v in $values) {
                    if ($kind -eq 'hrv') { $o.Hrv += $v } else { $o.Rhr += $v }
                    $o.Samples += $kind
                }
            }
            continue
        }
        if ($kind -eq 'sleep') {
            if ($mom.Moments.Count -ge 2) {
                $dur = Get-DurationBetween $mom.Moments[0] $mom.Moments[1]
                Add-SleepSample $o 'unspecified' $dur $line
            } else {
                Add-SleepSample $o 'unspecified' (Get-DurationFromText $mom.Cleaned) $line
            }
            continue
        }
        $o.Unrecognized += $line
    }

    if ($o.Samples.Count -eq 0 -and $o.Hrv.Count -eq 0 -and $o.Rhr.Count -eq 0) {
        $values = @($valueRe.Matches($Text) | ForEach-Object { [double]$_.Value })
        if ($values.Count -gt 0) {
            if ($Hint -eq 'hrv') { $o.Hrv = $values }
            elseif ($Hint -eq 'rhr') { $o.Rhr = $values }
            else { $o.Unrecognized += $Text }
        } else { $o.Unrecognized += $Text }
    }

    return $o
}

function Add-SleepSample {
    param($O, [string]$Stage, $Duration, [string]$Raw)
    if ($null -eq $Duration -or $Duration -le 0) { $O.Unrecognized += $Raw; return }
    $O.SleepCount++
    switch ($Stage) {
        'deep' { $O.SleepDeep += $Duration; $O.SleepTotal += $Duration }
        'rem' { $O.SleepRem += $Duration; $O.SleepTotal += $Duration }
        'core' { $O.SleepCore += $Duration; $O.SleepTotal += $Duration }
        'unspecified' { $O.SleepUnspec += $Duration; $O.SleepTotal += $Duration }
        'awake' { $O.SleepAwake += $Duration }
        'inBed' { $O.SleepInBed += $Duration }
    }
    $O.Samples += 'sleep'
}

function Get-Median { param($v) if ($v.Count -eq 0) { return $null }; $s = @($v | Sort-Object); $mid = [int][math]::Floor($s.Count / 2); if ($s.Count % 2 -eq 1) { return $s[$mid] }; return ($s[$mid - 1] + $s[$mid]) / 2 }
function Get-Average { param($v) if ($v.Count -eq 0) { return $null }; return ($v | Measure-Object -Average).Average }

# ---------- cases ----------
$pass = 0; $fail = 0
function Assert-Case {
    param([string]$Name, [scriptblock]$Body)
    try {
        $r = & $Body
        if ($r[0]) { $script:pass++; Write-Output ("PASS | $Name | " + $r[1]) }
        else { $script:fail++; Write-Output ("FAIL | $Name | " + $r[1]) }
    } catch {
        $script:fail++; Write-Output ("FAIL | $Name | EXCEPTION " + $_.Exception.Message)
    }
}

Assert-Case 'sleep en stages + start/end' {
    $text = "asleepDeep, 2026-10-26 23:00:00, 2026-10-26 23:30:00`nasleepREM, 2026-10-26 23:30:00, 2026-10-27 01:00:00`nasleepCore, 2026-10-27 01:00:00, 2026-10-27 05:00:00"
    $o = Invoke-Parse $text 'sleep'
    if ($o.SleepCount -ne 3) { return @($false, "expected 3 got $($o.SleepCount)") }
    $deep = [math]::Round($o.SleepDeep / 60); $rem = [math]::Round($o.SleepRem / 60)
    $core = [math]::Round($o.SleepCore / 60); $total = [math]::Round($o.SleepTotal / 60)
    if ($deep -ne 30 -or $rem -ne 90 -or $core -ne 240 -or $total -ne 360) { return @($false, "deep $deep rem $rem core $core total $total") }
    return @($true, "deep 30 / rem 90 / core 240 / total 360")
}

Assert-Case 'sleep across midnight 23:30 -> 06:45' {
    $o = Invoke-Parse 'asleepCore, 23:30, 06:45' 'sleep'
    if ($o.SleepCount -ne 1) { return @($false, "expected 1 got $($o.SleepCount)") }
    $m = [math]::Round($o.SleepTotal / 60)
    if ($m -ne 435) { return @($false, "got $m expected 435") }
    return @($true, "435 min")
}

Assert-Case 'sleep zh stages' {
    $text = "深睡, 2026-10-26 23:00:00, 2026-10-26 23:40:00`n快速眼动, 2026-10-26 23:40:00, 2026-10-27 01:10:00`n清醒, 2026-10-27 01:10:00, 2026-10-27 01:20:00"
    $o = Invoke-Parse $text 'sleep'
    $deep = [math]::Round($o.SleepDeep / 60); $rem = [math]::Round($o.SleepRem / 60); $awake = [math]::Round($o.SleepAwake / 60)
    if ($deep -ne 40 -or $rem -ne 90 -or $awake -ne 10) { return @($false, "deep $deep rem $rem awake $awake") }
    return @($true, "deep 40 / rem 90 / awake 10")
}

Assert-Case 'sleep no stage keyword -> pair by time' {
    $o = Invoke-Parse '2026-10-26 23:00:00, 2026-10-27 02:00:00, 2026-10-27 06:00:00' 'sleep'
    $total = [math]::Round($o.SleepTotal / 60)
    if ($total -ne 420) { return @($false, "got $total expected 420") }
    return @($true, "420 min")
}

Assert-Case 'HRV multi -> median' {
    $o = Invoke-Parse '40 毫秒, 48 毫秒, 52 毫秒, 200 毫秒' 'hrv'
    if ($o.Hrv.Count -ne 4) { return @($false, "got $($o.Hrv.Count) values") }
    $m = Get-Median $o.Hrv
    if ($m -ne 50) { return @($false, "median $m expected 50") }
    return @($true, "4 values, median 50")
}

Assert-Case 'HRV no unit -> by channel' {
    $o = Invoke-Parse '40, 48, 52' 'hrv'
    if ($o.Hrv.Count -ne 3) { return @($false, "got $($o.Hrv.Count) values") }
    if ($o.Rhr.Count -gt 0) { return @($false, "$($o.Rhr.Count) misrouted to RHR") }
    $m = Get-Median $o.Hrv
    if ($m -ne 48) { return @($false, "median $m expected 48") }
    return @($true, "3 values, median 48")
}

Assert-Case 'RHR multi -> average' {
    $o = Invoke-Parse '52 次/分, 56 次/分, 60 次/分' 'rhr'
    $a = Get-Average $o.Rhr
    if ($o.Rhr.Count -ne 3 -or [math]::Round($a) -ne 56) { return @($false, "$($o.Rhr.Count) values avg $a") }
    return @($true, "3 values, avg 56")
}

Assert-Case 'three channels mixed' {
    $text = "心率变异性, 48 毫秒`n静息心率, 54 次/分`nasleepDeep, 2026-10-26 23:00:00, 2026-10-26 23:40:00"
    $o = Invoke-Parse $text 'unknown'
    if ($o.Hrv.Count -ne 1 -or $o.Rhr.Count -ne 1 -or $o.SleepCount -ne 1) { return @($false, "hrv $($o.Hrv.Count) rhr $($o.Rhr.Count) sleep $($o.SleepCount)") }
    return @($true, "one each")
}

Assert-Case 'in-bed segment' {
    $o = Invoke-Parse '在床, 2026-10-26 22:50:00, 2026-10-27 06:45:00' 'sleep'
    $inbed = [math]::Round($o.SleepInBed / 60)
    if ($inbed -ne 475) { return @($false, "inbed $inbed expected 475") }
    return @($true, "475 min")
}

Assert-Case 'unrecognized does not pollute' {
    $o = Invoke-Parse '这是一段完全无关的文字' 'hrv'
    if ($o.Hrv.Count -gt 0) { return @($false, "got $($o.Hrv.Count) values") }
    if ($o.Unrecognized.Count -eq 0) { return @($false, "nothing recorded as unrecognized") }
    return @($true, "$($o.Unrecognized.Count) unrecognized")
}

Assert-Case 'zero-duration segment not counted' {
    $o = Invoke-Parse 'asleepDeep, 2026-10-26 23:00:00, 2026-10-26 23:00:00' 'sleep'
    if ($o.SleepCount -ne 0) { return @($false, "counted $($o.SleepCount)") }
    return @($true, "0 segments")
}

# --- merge rule (mirrors ManualHealthStore.merged) ---
function Merge-Record($new, $old) {
    if ($null -eq $old) { return $new }
    if ($null -eq $new.Hrv) { $new.Hrv = $old.Hrv }
    if ($null -eq $new.Rhr) { $new.Rhr = $old.Rhr }
    if ($new.SleepTotal -le 0 -and $old.SleepTotal -gt 0) {
        $new.SleepTotal = $old.SleepTotal
        $new.SleepDeep = $old.SleepDeep
        $new.SleepRem = $old.SleepRem
        $new.SleepInBed = $old.SleepInBed
    }
    return $new
}

function New-Rec($hrv, $rhr, $total, $deep, $rem, $inbed) {
    return [pscustomobject]@{
        Hrv = $hrv; Rhr = $rhr
        SleepTotal = $total; SleepDeep = $deep; SleepRem = $rem; SleepInBed = $inbed
    }
}

Assert-Case 'merge: new without sleep keeps old' {
    $old = New-Rec 48 54 28800 5400 7200 30600
    $new = New-Rec 50 $null 0 0 0 0
    $o = Merge-Record $new $old
    if ($o.SleepTotal -ne 28800 -or $o.SleepDeep -ne 5400 -or $o.SleepRem -ne 7200 -or $o.SleepInBed -ne 30600) {
        return @($false, "sleep overwritten to $($o.SleepTotal)")
    }
    if ($o.Rhr -ne 54) { return @($false, "rhr lost") }
    if ($o.Hrv -ne 50) { return @($false, "hrv not updated") }
    return @($true, "sleep kept 480 min / rhr kept 54 / hrv updated 50")
}

Assert-Case 'merge: new with sleep replaces whole group' {
    $old = New-Rec 48 54 28800 5400 7200 30600
    $new = New-Rec $null 56 25200 3600 5400 27000
    $o = Merge-Record $new $old
    if ($o.SleepTotal -ne 25200 -or $o.SleepDeep -ne 3600 -or $o.SleepRem -ne 5400 -or $o.SleepInBed -ne 27000) {
        return @($false, "sleep group not replaced")
    }
    if ($o.Hrv -ne 48) { return @($false, "hrv lost") }
    if ($o.Rhr -ne 56) { return @($false, "rhr not updated") }
    return @($true, "sleep group replaced 420 min / hrv kept 48 / rhr updated 56")
}

Write-Output "=============================================================="
Write-Output "TOTAL | $pass/$($pass + $fail) passed"
if ($fail -gt 0) { exit 1 }
