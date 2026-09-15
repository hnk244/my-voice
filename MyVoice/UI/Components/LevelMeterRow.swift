import SwiftUI

/// Horizontal VU-style level meter.
struct LevelMeterRow: View {
    let label: String
    let level: Float     // 0…1
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 44, alignment: .leading)
                .font(.caption)
                .foregroundColor(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 14)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(meterGradient(for: color))
                        .frame(width: geo.size.width * CGFloat(level), height: 14)
                        .animation(.linear(duration: 0.05), value: level)
                }
            }
            .frame(height: 14)
        }
    }

    private func meterGradient(for baseColor: Color) -> LinearGradient {
        LinearGradient(
            colors: [baseColor, baseColor.opacity(0.6)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// Volume slider with label + percentage.
struct LabeledSlider: View {
    let label: String
    @Binding var value: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Slider(value: $value, in: 0...1)
                .tint(Theme.accent)
        }
    }
}
