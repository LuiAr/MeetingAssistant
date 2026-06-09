import SwiftUI

struct AppGradientBackground: View {
  var body: some View {
    LinearGradient(
      colors: [
        Color(red: 0.73, green: 0.82, blue: 0.94),
        Color(red: 0.93, green: 0.80, blue: 0.78),
        Color(red: 0.93, green: 0.80, blue: 0.78),
        Color(red: 1.00, green: 0.90, blue: 0.68)
      ],
      startPoint: .topTrailing,
      endPoint: .bottomLeading
    )
    .ignoresSafeArea()
  }
}
