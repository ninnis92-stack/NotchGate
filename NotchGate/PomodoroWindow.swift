import AppKit
import SwiftUI

struct PomodoroWindowView: View {
    static let panelSize = CGSize(width: 280, height: 340)

    @Environment(PomodoroService.self) private var service
    @Environment(ThemeManager.self) private var theme
    @State private var durationDraft = ""
    @State private var dragOrigin: CGPoint?
    @State private var appeared = false
    @FocusState private var editingTime: Bool

    var body: some View {
        let motion = NotchAnimationManager.shared
        VStack(spacing: 16) {
            Text("Pomodoro")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            PomodoroAnalogClock(
                progress: service.justFinished ? 1 : service.progress,
                accent: service.justFinished ? Color(red: 0.45, green: 0.92, blue: 0.62) : theme.accent
            )
            .frame(width: 148, height: 148)
            if service.justFinished {
                Text("Countdown complete")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.45, green: 0.92, blue: 0.62))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            } else if service.isActive {
                Text(service.display)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
            } else {
                TextField("25:00", text: $durationDraft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .focused($editingTime)
                    .onSubmit {
                        service.applyDuration(durationDraft)
                        durationDraft = service.display
                        editingTime = false
                    }
            }
            HStack(spacing: 12) {
                Button {
                    if service.isActive {
                        service.pause()
                        durationDraft = service.display
                    } else {
                        if editingTime {
                            service.applyDuration(durationDraft)
                            editingTime = false
                        }
                        service.startTimer()
                    }
                } label: {
                    Label(service.isActive ? "Pause" : "Play", systemImage: service.isActive ? "pause.fill" : "play.fill")
                }
                .buttonStyle(PomodoroControlStyle())
                Button {
                    service.stop()
                    durationDraft = service.display
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(PomodoroControlStyle())
            }
            .controlSize(.small)
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 50)
        .animation(motion.appearAnimation, value: appeared)
        .animation(motion.fadeAnimation, value: service.justFinished)
        .animation(motion.fadeAnimation, value: service.isActive)
        .gesture(windowDrag)
        .onAppear {
            durationDraft = service.display
            appeared = true
        }
        .onChange(of: service.display) { _, value in
            if !editingTime { durationDraft = value }
        }
    }

    private var windowDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard let window = NSApp.windows.first(where: { $0.title == "Pomodoro" }) else { return }
                if dragOrigin == nil {
                    dragOrigin = window.frame.origin
                }
                guard let start = dragOrigin else { return }
                window.setFrameOrigin(NSPoint(
                    x: start.x + value.translation.width,
                    y: start.y - value.translation.height
                ))
            }
            .onEnded { _ in
                dragOrigin = nil
                PomodoroWindowManager.shared.persistPosition()
            }
    }
}

private struct PomodoroControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverScaleButtonShell(configuration: configuration)
    }
}

private struct HoverScaleButtonShell: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(hovering ? Color.black : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(hovering ? Color.white : Color.white.opacity(0.12))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : (hovering ? 1.1 : 1))
            .animation(NotchAnimationManager.shared.hoverAnimation, value: hovering)
            .animation(NotchAnimationManager.shared.hoverAnimation, value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

private struct PomodoroAnalogClock: View {
    var progress: Double
    var accent: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 3)
            ForEach(0..<12, id: \.self) { hour in
                Capsule()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 2, height: 10)
                    .offset(y: -62)
                    .rotationEffect(.degrees(Double(hour) / 12 * 360))
            }
            Capsule()
                .fill(accent)
                .frame(width: 3, height: 54)
                .offset(y: -27)
                .rotationEffect(.degrees(progress * 360))
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)
        }
        .animation(.linear(duration: 0.2), value: progress)
        .animation(NotchAnimationManager.shared.fadeAnimation, value: accent)
    }
}
