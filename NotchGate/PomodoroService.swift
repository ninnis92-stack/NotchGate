import AppKit
import Foundation

@Observable
@MainActor
final class PomodoroService {
    static let shared = PomodoroService()

    var isActive = false
    var timeRemaining: TimeInterval = NotchCustomization.shared.pomodoroDuration
    var completedSessions = 0
    var customDuration: TimeInterval?
    var justFinished = false

    var duration: TimeInterval {
        customDuration ?? NotchCustomization.shared.pomodoroDuration
    }

    var display: String {
        let total = max(0, Int(timeRemaining.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var progress: Double {
        let span = duration
        guard span > 0 else { return 0 }
        return 1 - min(max(timeRemaining / span, 0), 1)
    }

    private var timer: Timer?
    private var endsAt: Date?

    func startTimer() {
        guard !isActive else { return }
        if justFinished {
            justFinished = false
            timeRemaining = duration
        }
        isActive = true
        endsAt = Date().addingTimeInterval(max(timeRemaining, 0.2))
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { _ in
            DispatchQueue.main.async {
                PomodoroService.shared.decrement()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        decrement()
    }

    func pause() {
        if let endsAt {
            timeRemaining = max(0, endsAt.timeIntervalSinceNow)
        }
        isActive = false
        timer?.invalidate()
        timer = nil
        self.endsAt = nil
    }

    func stop() {
        pause()
        justFinished = false
        customDuration = nil
        timeRemaining = NotchCustomization.shared.pomodoroDuration
    }

    func decrement() {
        guard isActive, let endsAt else { return }
        timeRemaining = max(0, endsAt.timeIntervalSinceNow)
        if timeRemaining <= 0 {
            completeSession()
        }
    }

    func completeSession() {
        pause()
        timeRemaining = 0
        justFinished = true
        completedSessions += 1
        NSSound.beep()
    }

    func applyDuration(_ text: String) {
        pause()
        justFinished = false
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let seconds: Int
        let parts = trimmed.split(separator: ":")
        if parts.count == 2, let minutes = Int(parts[0]), let secs = Int(parts[1]), minutes >= 0, secs >= 0, secs < 60 {
            seconds = minutes * 60 + secs
        } else if let minutes = Int(trimmed), minutes > 0 {
            seconds = minutes * 60
        } else {
            return
        }
        let clamped = min(max(seconds, 1), 99 * 60)
        customDuration = TimeInterval(clamped)
        timeRemaining = TimeInterval(clamped)
    }
}
