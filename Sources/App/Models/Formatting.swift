import Foundation

enum Fmt {
    /// "7h52m"
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 { return "\(minutes)m" }
        return "\(hours)h\(String(format: "%02d", minutes))m"
    }

    /// "42ms" / "57 bpm"
    static func ms(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0fms", value)
    }

    static func bpm(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f bpm", value)
    }

    /// "8.7%"
    static func percent(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", value * 100)
    }

    /// "+8.7%" / "-8.7%"
    static func signedPercent(_ value: Double, digits: Int = 1) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "−" : "")
        return sign + String(format: "%.\(digits)f%%", abs(value) * 100)
    }

    /// "2026-10-27"
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// "10月27日 周一"
    static func friendlyDay(_ date: Date, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let weekday = ["日", "一", "二", "三", "四", "五", "六"][calendar.component(.weekday, from: date) - 1]
        return "\(month)月\(day)日 周\(weekday)"
    }

    /// "2026-10-27 08:15:30"
    static func dateTime(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let hour = parts.hour, let minute = parts.minute, let second = parts.second else {
            return ""
        }
        return String(format: "%04d-%02d-%02d %02d:%02d:%02d", year, month, day, hour, minute, second)
    }
}
