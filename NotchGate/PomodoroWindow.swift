import AppKit
import SwiftUI

struct PomodoroWindowView: View {
    static let panelSize = CGSize(width: 280, height: 340)

    @Environment(PomodoroService.self) private var service
    @Environment(ThemeManager.self) private var theme
    @State private var durationDraft = ""
    @State private var dragOrigin: CGPoint?
    @FocusState private var editingTime: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Pomodoro")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            PomodoroAnalogClock(progress: service.justFinished ? 1 : service.progress, accent: theme.accent)
                .frame(width: 148, height: 148)
            if service.justFinished {
                Text("Countdown complete")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else if service.isActive {
                Text(service.display)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
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
                    Image(systemName: service.isActive ? "pause.fill" : "play.fill")
                    Text(service.isActive ? "Pause" : "Play")
                }
                Button {
                    service.stop()
                    durationDraft = service.display
                } label: {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                }
            }
            .controlSize(.small)
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .gesture(windowDrag)
        .onAppear { durationDraft = service.display }
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

private struct PomodoroAnalogClock: View {
    var progress: Double
    var accent: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { _ in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 6
                let face = Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.stroke(face, with: .color(.white.opacity(0.18)), lineWidth: 3)
                for hour in 0..<12 {
                    let angle = Angle.degrees(Double(hour) / 12 * 360 - 90)
                    var tickPath = Path()
                    tickPath.move(to: point(center, radius - 12, angle))
                    tickPath.addLine(to: point(center, radius - 2, angle))
                    context.stroke(tickPath, with: .color(.white.opacity(0.45)), lineWidth: 2)
                }
                let handAngle = Angle.degrees(progress * 360 - 90)
                var hand = Path()
                hand.move(to: center)
                hand.addLine(to: point(center, radius - 16, handAngle))
                context.stroke(hand, with: .color(accent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                let hub = Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
                context.fill(hub, with: .color(accent))
            }
        }
    }

    private func point(_ center: CGPoint, _ radius: CGFloat, _ angle: Angle) -> CGPoint {
        CGPoint(
            x: center.x + CGFloat(cos(angle.radians)) * radius,
            y: center.y + CGFloat(sin(angle.radians)) * radius
        )
    }
}
