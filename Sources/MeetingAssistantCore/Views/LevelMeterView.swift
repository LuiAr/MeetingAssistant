import SwiftUI

struct LevelMeterView: View {
  var title: String
  var level: Float

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)

      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 3)
            .fill(.quaternary)

          RoundedRectangle(cornerRadius: 3)
            .fill(level > 0.72 ? .red : .green)
            .frame(width: geometry.size.width * CGFloat(max(0, min(1, level))))
        }
      }
      .frame(width: 180, height: 8)
      .accessibilityLabel("\(title) level")
      .accessibilityValue("\(Int(level * 100)) percent")
    }
  }
}

