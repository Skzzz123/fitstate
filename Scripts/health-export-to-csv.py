#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把「健康」App 导出的 export.xml 转成 FitState 能吃的 CSV。

为什么要这个
------------
免费账号拿不到 HealthKit 能力，App 只能靠「快捷指令」一天一天攒数据，
攒够 7 天才有基线、30 天基线才稳 —— 但「健康」App 里其实**已经有 30 天历史**。
「健康 → 头像 → 导出所有健康数据」就能拿到完整历史（export.xml）。

本脚本的口径**和 App 内 HealthKit 直读完全一致**（对齐 Sources/App/Services/HealthKitService.swift）：
  - 睡眠归属：前一天 16:00 → 当天 20:00 这个「夜里」算作**醒来的那一天**
  - 深睡 / REM / 核心 / 未分期 时长各自累加，睡眠总时长 = 这四项之和
  - 在床：InBed 样本时长累加
  - HRV：优先取夜里窗口的中位数，取不到再退回当天所有样本的中位数
  - 静息心率：当天所有样本的平均值

输出：fitstate-import.csv
表头固定为：日期,HRV(ms),静息心率(bpm),睡眠时长(min),深睡(min),REM(min),在床(min)
（这个表头正是 Sources/App/Services/ImportedHealthStore.swift 认的）

用法：
    python health-export-to-csv.py <export.xml 或 export.zip> [-o 输出.csv] [--days N]
"""

import argparse
import csv
import os
import statistics
import sys
import zipfile
from datetime import datetime, timedelta, timezone
import xml.etree.ElementTree as ET

HRV_TYPE = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
RHR_TYPE = "HKQuantityTypeIdentifierRestingHeartRate"
SLEEP_TYPE = "HKCategoryTypeIdentifierSleepAnalysis"

STAGE_MAP = {
    "HKCategoryValueSleepAnalysisAsleepDeep": "deep",
    "HKCategoryValueSleepAnalysisAsleepREM": "rem",
    "HKCategoryValueSleepAnalysisAsleepCore": "core",
    "HKCategoryValueSleepAnalysisAsleepUnspecified": "unspec",
    "HKCategoryValueSleepAnalysisAsleep": "unspec",
    "HKCategoryValueSleepAnalysisAwake": "awake",
    "HKCategoryValueSleepAnalysisInBed": "inbed",
}

HEADER = ["日期", "HRV(ms)", "静息心率(bpm)", "睡眠时长(min)", "深睡(min)", "REM(min)", "在床(min)"]


def parse_dt(text):
    """'2026-10-27 22:30:00 +0800' -> aware datetime"""
    if not text:
        return None
    text = text.strip()
    for fmt in ("%Y-%m-%d %H:%M:%S %z", "%Y-%m-%d %H:%M:%S"):
        try:
            dt = datetime.strptime(text, fmt)
            if dt.tzinfo is None:
                dt = dt.astimezone()
            return dt
        except ValueError:
            continue
    return None


def resolve_xml(path):
    """输入可以是 export.xml，也可以是 export.zip（自动解开）"""
    if path.lower().endswith(".zip"):
        out_dir = path + "_unzipped"
        os.makedirs(out_dir, exist_ok=True)
        with zipfile.ZipFile(path) as zf:
            zf.extractall(out_dir)
        for name in ("export.xml",):
            candidate = os.path.join(out_dir, name)
            if os.path.exists(candidate):
                return candidate
        for root, _dirs, files in os.walk(out_dir):
            for f in files:
                if f.lower() == "export.xml":
                    return os.path.join(root, f)
        raise SystemExit("压缩包里没找到 export.xml")
    return path


def collect(xml_path):
    """流式解析，只留我们关心的三类记录"""
    hrv = []        # (start, end, value_ms)
    rhr = []        # (start, end, value)
    sleep = []      # (start, end, stage)
    offsets = set()

    context = ET.iterparse(xml_path, events=("end",))
    for _event, elem in context:
        if elem.tag != "Record":
            continue
        rtype = elem.get("type")
        if rtype in (HRV_TYPE, RHR_TYPE, SLEEP_TYPE):
            start = parse_dt(elem.get("startDate"))
            end = parse_dt(elem.get("endDate"))
            if start is None:
                elem.clear()
                continue
            if end is None:
                end = start
            if start.utcoffset() is not None:
                offsets.add(start.utcoffset())

            if rtype == HRV_TYPE:
                raw = elem.get("value")
                unit = (elem.get("unit") or "s").lower()
                try:
                    val = float(raw)
                except (TypeError, ValueError):
                    val = None
                if val is not None:
                    if unit in ("s", "sec", "second", "seconds"):
                        val *= 1000.0
                    hrv.append((start, end, val))
            elif rtype == RHR_TYPE:
                try:
                    rhr.append((start, end, float(elem.get("value"))))
                except (TypeError, ValueError):
                    pass
            else:
                stage = STAGE_MAP.get(elem.get("value"))
                if stage:
                    sleep.append((start, end, stage))
        elem.clear()

    return hrv, rhr, sleep, offsets


def median(values):
    vals = [v for v in values if v > 0]
    if not vals:
        return None
    return statistics.median(vals)


def mean(values):
    vals = [v for v in values if v > 0]
    if not vals:
        return None
    return sum(vals) / len(vals)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input", help="export.xml 或 export.zip")
    ap.add_argument("-o", "--output", default="fitstate-import.csv")
    ap.add_argument("--days", type=int, default=0, help="只保留最近 N 天（0 = 全部）")
    args = ap.parse_args()

    xml_path = resolve_xml(args.input)
    hrv, rhr, sleep, offsets = collect(xml_path)

    if not hrv and not rhr and not sleep:
        raise SystemExit("没读到 HRV / 静息心率 / 睡眠记录，检查一下是不是「健康」的导出文件")

    tz = timezone(offsets.pop()) if len(offsets) == 1 else timezone(timedelta(hours=8))
    if len(offsets) > 1:
        print("提示：导出里出现了多个时区偏移，按 %s 处理" % tz)

    # 所有涉及到的日期
    days = set()
    for start, _end, _v in hrv + rhr:
        days.add(start.date())
    for start, _end, _s in sleep:
        days.add(start.date())
        days.add((start + timedelta(days=1)).date())

    days = sorted(days)
    if args.days > 0:
        days = days[-args.days:]

    rows = []
    for day in days:
        midnight = datetime(day.year, day.month, day.day, tzinfo=tz)
        next_midnight = midnight + timedelta(days=1)
        night_start = midnight - timedelta(hours=8)   # 前一天 16:00
        night_end = midnight + timedelta(hours=20)    # 当天 20:00

        # 睡眠：夜里窗口
        deep = rem = core = unspec = inbed = awake = 0.0
        for start, end, stage in sleep:
            if not (night_start <= start < night_end):
                continue
            dur = (end - start).total_seconds()
            if dur <= 0:
                continue
            if stage == "deep":
                deep += dur
            elif stage == "rem":
                rem += dur
            elif stage == "core":
                core += dur
            elif stage == "unspec":
                unspec += dur
            elif stage == "inbed":
                inbed += dur
            elif stage == "awake":
                awake += dur
        total_sleep = deep + rem + core + unspec

        # HRV：先夜里窗口的中位数，取不到退回当天
        night_hrv = [v for s, _e, v in hrv if night_start <= s < night_end]
        day_hrv = [v for s, _e, v in hrv if midnight <= s < next_midnight]
        hrv_value = median(night_hrv)
        if hrv_value is None:
            hrv_value = median(day_hrv)

        # 静息心率：当天平均
        day_rhr = [v for s, _e, v in rhr if midnight <= s < next_midnight]
        rhr_value = mean(day_rhr)

        if hrv_value is None and rhr_value is None and total_sleep <= 0:
            continue

        rows.append([
            day.strftime("%Y-%m-%d"),
            "" if hrv_value is None else "%.1f" % hrv_value,
            "" if rhr_value is None else "%.1f" % rhr_value,
            "%.0f" % (total_sleep / 60.0),
            "%.0f" % (deep / 60.0),
            "%.0f" % (rem / 60.0),
            "%.0f" % (inbed / 60.0),
        ])

    with open(args.output, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(HEADER)
        writer.writerows(rows)

    with_sleep = sum(1 for r in rows if float(r[3]) > 0)
    with_hrv = sum(1 for r in rows if r[1] != "")
    with_rhr = sum(1 for r in rows if r[2] != "")
    print("原始记录：HRV %d / 静息心率 %d / 睡眠分段 %d" % (len(hrv), len(rhr), len(sleep)))
    print("输出 %d 天 → %s" % (len(rows), os.path.abspath(args.output)))
    print("  含 HRV %d 天 / 含静息心率 %d 天 / 含睡眠 %d 天" % (with_hrv, with_rhr, with_sleep))
    if rows:
        print("  日期范围 %s ~ %s" % (rows[0][0], rows[-1][0]))
    print("下一步：把 %s 放到 iPhone 上「我的 iPhone → 状态」这个 App 的文件目录里" % args.output)


if __name__ == "__main__":
    main()
