import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var isInteractive = false
    @Published private(set) var authorization: CalendarAuthorization = .notDetermined
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var loadState: CalendarLoadState = .idle
    @Published private(set) var isRefreshing = false
    @Published var editorRoute: EditorRoute?
    @Published var notice: String?
    @Published private(set) var appearanceMode: DaylightAppearance
    @Published private(set) var viewMode: CalendarViewMode
    @Published private(set) var referenceDate: Date = Date()

    let isDemoMode: Bool
    private let calendarService: CalendarService
    private let defaults: UserDefaults
    private var noticeTask: Task<Void, Never>?

    init(calendarService: CalendarService? = nil, defaults: UserDefaults = .standard) {
        let calendarService = calendarService ?? CalendarService()
        self.calendarService = calendarService
        self.defaults = defaults
        let arguments = ProcessInfo.processInfo.arguments
        let savedAppearance = DaylightAppearance(rawValue: defaults.string(forKey: "daylight.appearance") ?? "")
        let savedView = CalendarViewMode(rawValue: defaults.string(forKey: "daylight.viewMode") ?? "")
        if arguments.contains("--light") {
            appearanceMode = .light
        } else if arguments.contains("--dark") {
            appearanceMode = .dark
        } else {
            appearanceMode = savedAppearance ?? .dark
        }
        if arguments.contains("--week") {
            viewMode = .week
        } else if arguments.contains("--month") {
            viewMode = .month
        } else if arguments.contains("--year") {
            viewMode = .year
        } else {
            viewMode = savedView ?? .week
        }
        isDemoMode = arguments.contains("--demo")
        isInteractive = arguments.contains("--interactive")

        calendarService.onStoreChanged = { [weak self] in
            guard let self else { return }
            Task { await self.refresh(showSpinner: false) }
        }

        if isDemoMode {
            authorization = .fullAccess
            events = CalendarEvent.demoEvents()
            loadState = .loaded
            if ProcessInfo.processInfo.arguments.contains("--editor"), let event = events.first {
                editorRoute = EditorRoute(draft: EventDraft(event: event))
            }
        }
    }

    func start() async {
        guard !isDemoMode else { return }
        authorization = calendarService.authorization
        if authorization == .fullAccess {
            await refresh()
        }
    }

    func toggleInteractiveMode() {
        let willBecomeInteractive = !isInteractive
        if willBecomeInteractive {
            NSApp.activate(ignoringOtherApps: true)
        }
        isInteractive = willBecomeInteractive
        if willBecomeInteractive {
            showNotice("Interactive mode on")
        } else {
            editorRoute = nil
            showNotice("Back to background")
        }
    }

    func setAppearance(_ appearance: DaylightAppearance) {
        appearanceMode = appearance
        defaults.set(appearance.rawValue, forKey: "daylight.appearance")
        showNotice("\(appearance.title) appearance")
    }

    func toggleAppearance() {
        setAppearance(appearanceMode == .light ? .dark : .light)
    }

    func selectViewMode(_ mode: CalendarViewMode, focus date: Date? = nil) {
        viewMode = mode
        if let date { referenceDate = date }
        defaults.set(mode.rawValue, forKey: "daylight.viewMode")
        Task { await refresh(showSpinner: false) }
    }

    func navigatePeriod(by offset: Int) {
        referenceDate = CalendarNavigation.movedDate(from: referenceDate, mode: viewMode, by: offset)
        Task { await refresh(showSpinner: false) }
    }

    func goToToday() {
        referenceDate = Date()
        Task { await refresh(showSpinner: false) }
    }

    func requestCalendarAccess() async {
        do {
            let granted = try await calendarService.requestFullAccess()
            authorization = granted ? .fullAccess : .denied
            if granted {
                await refresh()
                showNotice("Apple Calendar connected")
            } else {
                showNotice("Calendar access wasn’t granted")
            }
        } catch {
            authorization = calendarService.authorization
            loadState = .failed(error.localizedDescription)
        }
    }

    func refresh(showSpinner: Bool = true) async {
        guard !isDemoMode else {
            events = CalendarEvent.demoEvents()
            return
        }
        authorization = calendarService.authorization
        guard authorization == .fullAccess else { return }

        if showSpinner { isRefreshing = true }
        if events.isEmpty { loadState = .loading }
        defer { isRefreshing = false }

        let interval = CalendarNavigation.visibleInterval(for: viewMode, referenceDate: referenceDate)
        events = calendarService.fetchEvents(in: interval)
        loadState = .loaded
    }

    func presentNewEvent(on date: Date) {
        guard isInteractive else { return }
        editorRoute = EditorRoute(draft: EventDraft(newOn: date))
    }

    func presentEditor(for event: CalendarEvent) {
        guard isInteractive, event.isEditable else { return }
        editorRoute = EditorRoute(draft: EventDraft(event: event))
    }

    func save(_ draft: EventDraft) async -> Bool {
        guard draft.validationMessage == nil else { return false }
        if isDemoMode {
            applyDemoSave(draft)
            editorRoute = nil
            showNotice(draft.originalEventID == nil ? "Event added" : "Event updated")
            return true
        }

        do {
            try calendarService.save(draft)
            await refresh(showSpinner: false)
            editorRoute = nil
            showNotice(draft.originalEventID == nil ? "Saved to Apple Calendar" : "Changes synced")
            return true
        } catch {
            notice = "Couldn’t save: \(error.localizedDescription)"
            return false
        }
    }

    func delete(eventID: String) async -> Bool {
        if isDemoMode {
            events.removeAll { $0.id == eventID }
            editorRoute = nil
            showNotice("Event deleted")
            return true
        }

        do {
            try calendarService.delete(eventID: eventID)
            await refresh(showSpinner: false)
            editorRoute = nil
            showNotice("Deleted from Apple Calendar")
            return true
        } catch {
            notice = "Couldn’t delete: \(error.localizedDescription)"
            return false
        }
    }

    private func applyDemoSave(_ draft: EventDraft) {
        if let originalID = draft.originalEventID,
           let index = events.firstIndex(where: { $0.id == originalID }) {
            events[index].title = draft.title
            events[index].startDate = draft.startDate
            events[index].endDate = draft.endDate
            events[index].isAllDay = draft.isAllDay
            events[index].notes = draft.notes
        } else {
            events.append(CalendarEvent(
                id: draft.id,
                title: draft.title,
                startDate: draft.startDate,
                endDate: draft.endDate,
                isAllDay: draft.isAllDay,
                notes: draft.notes,
                calendarTitle: "Work",
                calendarIdentifier: "work",
                color: .blue,
                isEditable: true
            ))
        }
    }

    private func showNotice(_ message: String) {
        noticeTask?.cancel()
        notice = message
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}
