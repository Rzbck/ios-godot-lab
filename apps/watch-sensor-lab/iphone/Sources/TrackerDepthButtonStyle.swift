import SwiftUI

struct TrackerDepthButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .offset(y: configuration.isPressed ? 1.5 : 0)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(
                .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}
