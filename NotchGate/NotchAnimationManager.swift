import SwiftUI

@Observable
@MainActor
final class NotchAnimationManager {
    static let shared = NotchAnimationManager()

    var isHovering = false
    var isExpanding = false
    var isContracting = false

    private init() {}

    var speed: Double {
        max(NotchCustomization.shared.animationSpeed, 0.5)
    }

    var enabled: Bool {
        NotchCustomization.shared.enableAnimations
    }

    var expandDuration: TimeInterval {
        enabled ? 0.3 / speed : 0
    }

    var fadeDuration: TimeInterval {
        enabled ? 0.2 / speed : 0
    }

    var hoverDuration: TimeInterval {
        enabled ? 0.2 / speed : 0
    }

    var expandAnimation: Animation {
        enabled ? .easeInOut(duration: expandDuration) : .linear(duration: 0)
    }

    var fadeAnimation: Animation {
        enabled ? .easeInOut(duration: fadeDuration) : .linear(duration: 0)
    }

    var hoverAnimation: Animation {
        enabled ? .easeInOut(duration: hoverDuration) : .linear(duration: 0)
    }

    var appearAnimation: Animation {
        enabled ? .easeOut(duration: expandDuration) : .linear(duration: 0)
    }

    var springAnimation: Animation {
        enabled
            ? .spring(response: 0.5 / speed, dampingFraction: 0.7)
            : .linear(duration: 0)
    }

    func applyHoverEffect() {
        isHovering = true
    }

    func applyExpandAnimation() {
        isExpanding = true
        isContracting = false
        isHovering = true
    }

    func applyContractAnimation() {
        isContracting = true
        isExpanding = false
        isHovering = false
    }
}

struct HoverScaleButtonStyle: ButtonStyle {
    var idle: CGFloat = 1
    var hover: CGFloat = 1.1

    func makeBody(configuration: Configuration) -> some View {
        HoverScaleButton(configuration: configuration, idle: idle, hover: hover)
    }
}

private struct HoverScaleButton: View {
    let configuration: ButtonStyleConfiguration
    var idle: CGFloat
    var hover: CGFloat
    @State private var hovering = false

    var body: some View {
        let motion = NotchAnimationManager.shared
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : (hovering ? hover : idle))
            .animation(motion.hoverAnimation, value: hovering)
            .animation(motion.hoverAnimation, value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}
