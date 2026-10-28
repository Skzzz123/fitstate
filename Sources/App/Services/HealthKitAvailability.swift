import Foundation

/// 判断这个安装包到底有没有 HealthKit 能力。
///
/// 为什么必须判断
/// --------------
/// 缺少 `com.apple.developer.healthkit` entitlement 的 App 一旦碰 HealthKit，
/// 系统会直接把它杀掉（"Missing com.apple.developer.healthkit entitlement."）。
/// 免费个人团队签出来的包正是这种情况，所以必须完全绕开 HealthKit，
/// 改走「快捷指令 → App Intent」这条不需要任何能力的数据入口。
///
/// 判据
/// ----
/// 看 App 内嵌的描述文件（embedded.mobileprovision）里有没有这项能力。
/// 描述文件是 CMS 封装，但里面的 plist 是明文，直接扫字节就能找到这项字符串。
/// 这比读代码签名更可靠，也不依赖任何私有 API。
enum HealthKitAvailability {

    /// 这个包里有没有 HealthKit 能力。
    static let isEnabled: Bool = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1) else {
            // 没有描述文件（例如某些侧载工具会剥掉它）→ 一律当作没有能力，
            // 宁可少一个数据源，也不要让 App 崩在启动路径上。
            return false
        }
        return text.contains("com.apple.developer.healthkit")
    }()

    /// 给用户看的解释文案。
    static var reasonText: String {
        isEnabled
            ? "这个包带 HealthKit 能力，直接读「健康」App。"
            : "这个包没有 HealthKit 能力（免费账号拿不到），数据由「快捷指令」喂进来。"
    }
}
