import AppKit
import EventKit
import SwiftUI

struct UpcomingEvent: Equatable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let location: String?
    let isAllDay: Bool
    let calendarColor: Color
}

enum CalendarSelection {
    static func nextEvent(from events: [UpcomingEvent], now: Date) -> UpcomingEvent? {
        events.first { $0.end > now } ?? events.first
    }
}

@Observable
@MainActor
final class CalendarService {
    var nextEvent: UpcomingEvent?
    var upcoming: [UpcomingEvent] = []
    var authorizationDenied = false
    var authorizationNotDetermined = false

    private let store = EKEventStore()
    private var timer: Timer?
    private var changeObserver: NSObjectProtocol?

    func start() {
        installChangeObserver()
        Task { await loadIfAuthorized(prompt: false) }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.loadEventsIfAuthorized()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
            self.changeObserver = nil
        }
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func installChangeObserver() {
        guard changeObserver == nil else { return }
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.loadEventsIfAuthorized()
            }
        }
    }

    func requestAccessFromUser() async {
        await loadIfAuthorized(prompt: true)
    }

    /// Request Calendar access only after the user interacts with Calendar.
    private func loadIfAuthorized(prompt: Bool) async {
        let status = EKEventStore.authorizationStatus(for: .event)
        if canReadEvents(status) {
            authorizationDenied = false
            authorizationNotDetermined = false
            await loadEvents()
        } else if status == .notDetermined {
            authorizationNotDetermined = true
            authorizationDenied = false
            guard prompt else { return }
            let granted = await requestAccess()
            authorizationNotDetermined = false
            authorizationDenied = !granted
            if granted {
                await loadEvents()
            }
        } else {
            authorizationDenied = true
            authorizationNotDetermined = false
        }
    }

    private func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    private func loadEventsIfAuthorized() async {
        guard canReadEvents(EKEventStore.authorizationStatus(for: .event)) else { return }
        await loadEvents()
    }

    /// macOS 14+ uses `.fullAccess`. Legacy `.authorized` is raw value 3.
    private func canReadEvents(_ status: EKAuthorizationStatus) -> Bool {
        if status == .fullAccess { return true }
        return status.rawValue == 3
    }

    private func loadEvents() async {
        let calendar = Calendar.current
        let start = Date()
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(604_800)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let mapped = store.events(matching: predicate)
            .sorted { lhs, rhs in
                return lhs.startDate < rhs.startDate
            }
            .prefix(10)
            .map { event in
                UpcomingEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Event",
                    start: event.startDate,
                    end: event.endDate,
                    location: event.location,
                    isAllDay: event.isAllDay,
                    calendarColor: Color(nsColor: event.calendar.color)
                )
            }

        upcoming = Array(mapped)
        let now = start
        nextEvent = CalendarSelection.nextEvent(from: upcoming, now: now)
    }
}
