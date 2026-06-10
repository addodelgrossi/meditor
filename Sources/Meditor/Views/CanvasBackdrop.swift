import SwiftUI

struct CanvasBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 24
            let color = colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.045)
            for x in stride(from: 0, through: size.width, by: spacing) {
                for y in stride(from: 0, through: size.height, by: spacing) {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)),
                        with: .color(color)
                    )
                }
            }
        }
        .background(.background)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
