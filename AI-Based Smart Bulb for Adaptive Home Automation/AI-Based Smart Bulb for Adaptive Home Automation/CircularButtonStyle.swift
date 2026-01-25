import SwiftUI

struct CircularIconButtonStyle: ButtonStyle {
    var backgroundColor: Color = .blue
    var foregroundColor: Color = .white
    var size: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(backgroundColor.opacity(configuration.isPressed ? 0.6 : 0.8))
            .foregroundColor(foregroundColor)
            .clipShape(Circle())
            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
