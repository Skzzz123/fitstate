import SwiftUI

/// 分数环
struct ScoreRing: View {
    let score: Double?
    var size: CGFloat = 170
    var lineWidth: CGFloat = 13
    var caption: String? = nil

    private var progress: Double {
        guard let score else { return 0 }
        return max(0.001, min(1, score / 100))
    }

    private var tint: Color {
        guard let score else { return Theme.muted }
        return Theme.scoreColor(score)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.hairline, lineWidth: lineWidth)

            if score != nil {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.7), value: progress)
            }

            VStack(spacing: 2) {
                if let score {
                    Text(String(format: "%.0f", score))
                        .font(.system(size: size * 0.31, weight: .medium, design: .serif))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                } else {
                    Text("--")
                        .font(.system(size: size * 0.26, weight: .medium, design: .serif))
                        .foregroundStyle(Theme.muted)
                }
                if let caption {
                    Text(caption)
                        .font(.system(size: max(10, size * 0.072), weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// 进度条（维度得分）
struct ScoreBar: View {
    let value: Double
    var tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, value / 100)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}
