import AppKit
import EventKit
import Foundation

@MainActor
final class CalendarService {
    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?
    var onStoreChanged: (() -> Void)?

    init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onStoreChanged?()
            }
        }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    var authorization: CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return .fullAccess
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted, .writeOnly:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func requestFullAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func fetchEvents(in interval: DateInterval) -> [CalendarEvent] {
        let predicate = store.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: nil
        )
        return store.events(matching: predicate).map(snapshot)
    }

    func save(_ draft: EventDraft) throws {
        let event: EKEvent
        if let identifier = draft.originalEventID,
           let existing = store.event(withIdentifier: identifier) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            if let identifier = draft.calendarIdentifier,
               let selected = store.calendar(withIdentifier: identifier),
               selected.allowsContentModifications {
                event.calendar = selected
            } else {
                event.calendar = store.defaultCalendarForNewEvents
            }
        }

        event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay
        event.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        try store.save(event, span: .thisEvent, commit: true)
    }

    func delete(eventID: String) throws {
        guard let event = store.event(withIdentifier: eventID) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    private func snapshot(_ event: EKEvent) -> CalendarEvent {
        let color = NSColor(cgColor: event.calendar.cgColor)?.usingColorSpace(.sRGB)
        return CalendarEvent(
            id: event.eventIdentifier ?? event.calendarItemIdentifier,
            title: event.title?.isEmpty == false ? event.title : "Untitled event",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            notes: event.notes ?? "",
            calendarTitle: event.calendar.title,
            calendarIdentifier: event.calendar.calendarIdentifier,
            color: EventColor(
                red: Double(color?.redComponent ?? 0.35),
                green: Double(color?.greenComponent ?? 0.64),
                blue: Double(color?.blueComponent ?? 0.98)
            ),
            isEditable: event.calendar.allowsContentModifications
        )
    }
}
