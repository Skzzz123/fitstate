import SwiftUI

/// 视觉方向 A：暖中性。米白底 + 墨绿/琥珀，长时间看不累。
enum Theme {
    static let background = Color(red: 0.984, green: 0.980, blue: 0.969)
    static let card = Color.white
    static let cardBorder = Color(red: 0.933, green: 0.913, blue: 0.866)
    static let hairline = Color(red: 0.945, green: 0.925, blue: 0.882)
    static let ink = Color(red: 0.078, green: 0.090, blue: 0.118)
    static let body = Color(red: 0.227, green: 0.259, blue: 0.337)
    static let muted = Color(red: 0.486, green: 0.478, blue: 0.447)

    static let primary = Color(red: 0.184, green: 0.435, blue: 0.369)
    static let good = Color(red: 0.310, green: 0.565, blue: 0.467)
    static let warn = Color(red: 0.788, green: 0.482, blue: 0.247)
    static let poor = Color(red: 0.753, green: 0.439, blue: 0.290)
    static let rose = Color(red: 0.690, green: 0.388, blue: 0.404)

    static func tierColor(_ tier: ReadinessTier) -> Color {
        switch tier {
        case .excellent: return primary
        case .good: return good
        case .average: return warn
        case .poor: return poor
        case .rest: return rose
        }
    }

    static func scoreColor(_ score: Double) -> Color {
        tierColor(ReadinessTier.from(score: score))
    }

    /// 分档底色（浅）
    static func tierTint(_ tier: ReadinessTier) -> Color {
        tierColor(tier).opacity(0.10)
    }
}

/// 统一的卡片容器
struct CardBackground: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 18) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

/// 章节标题
struct SectionTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
