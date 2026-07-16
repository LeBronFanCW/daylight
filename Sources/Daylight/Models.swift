import Foundation
import SwiftUI

enum CalendarAuthorization: Equatable {
    case notDetermined
    case fullAccess
    case denied
}

enum CalendarLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum CalendarViewMode: String, CaseIterable, Identifiable {
    case week
    case month
    case year

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .week: "rectangle.split.3x1"
        case .month: "calendar"
        case .year: "square.grid.3x3"
        }
    }
}

enum DaylightAppearance: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String { self == .light ? "sun.max" : "moon.stars" }
}

struct EventColor: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue)
    }

    static let blue = EventColor(red: 0.34, green: 0.63, blue: 0.98)
    static let coral = EventColor(red: 0.98, green: 0.48, blue: 0.42)
    static let mint = EventColor(red: 0.36, green: 0.82, blue: 0.65)
    static let gold = EventColor(red: 0.96, green: 0.72, blue: 0.30)
    static let violet = EventColor(red: 0.66, green: 0.50, blue: 0.95)
}

struct CalendarEvent: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var notes: String
    var calendarTitle: String
    var calendarIdentifier: String
    var color: EventColor
    var isEditable: Bool

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
}

struct EventDraft: Identifiable, Hashable {
    var id: String
    var originalEventID: String?
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var notes: String
    var calendarIdentifier: String?

    init(event: CalendarEvent) {
        id = event.id
        originalEventID = event.id
        title = event.title
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
        notes = event.notes
        calendarIdentifier = event.calendarIdentifier
    }

    init(newOn date: Date, calendar: Calendar = .current) {
        let hour = calendar.component(.hour, from: Date())
        let proposedHour = min(max(hour + 1, 8), 18)
        let start = calendar.date(bySettingHour: proposedHour, minute: 0, second: 0, of: date) ?? date
        id = UUID().uuidString
        originalEventID = nil
        title = ""
        startDate = start
        endDate = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
        isAllDay = false
        notes = ""
        calendarIdentifier = nil
    }

    var validationMessage: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add a title before saving."
        }
        if endDate <= startDate {
            return "The end time needs to be after the start time."
        }
        return nil
    }
}

struct EditorRoute: Identifiable, Hashable {
    let draft: EventDraft
    var id: String { draft.id }
}

enum CalendarGrouping {
    static func events(
        on day: Date,
        from events: [CalendarEvent],
        calendar: Calendar = .current
    ) -> [CalendarEvent] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return events
            .filter { $0.startDate < end && $0.endDate > start }
            .sorted {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                return $0.startDate < $1.startDate
            }
    }
}

enum CalendarNavigation {
    static func visibleInterval(
        for mode: CalendarViewMode,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        let component: Calendar.Component
        switch mode {
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        return calendar.dateInterval(of: component, for: referenceDate)
            ?? DateInterval(start: referenceDate, duration: 86_400)
    }

    static func weekDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func monthGridDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: month.start),
              let lastMoment = calendar.date(byAdding: .second, value: -1, to: month.end),
              let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastMoment) else {
            return []
        }
        let dayCount = calendar.dateComponents([.day], from: firstWeek.start, to: lastWeek.end).day ?? 42
        return (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: firstWeek.start) }
    }

    static func months(inYearContaining date: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.dateInterval(of: .year, for: date)?.start ?? date
        return (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
    }

    static func movedDate(
        from date: Date,
        mode: CalendarViewMode,
        by offset: Int,
        calendar: Calendar = .current
    ) -> Date {
        let component: Calendar.Component
        switch mode {
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        return calendar.date(byAdding: component, value: offset, to: date) ?? date
    }
}

extension CalendarEvent {
    static func demoEvents(reference: Date = Date(), calendar: Calendar = .current) -> [CalendarEvent] {
        let week = calendar.dateInterval(of: .weekOfYear, for: reference)?.start ?? reference
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: day, to: week) ?? week
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        func event(_ id: String, _ title: String, _ day: Int, _ hour: Int, _ duration: Double, _ color: EventColor, _ calendarName: String = "Work") -> CalendarEvent {
            let start = date(day, hour)
            return CalendarEvent(
                id: id,
                title: title,
                startDate: start,
                endDate: start.addingTimeInterval(duration * 3600),
                isAllDay: false,
                notes: "",
                calendarTitle: calendarName,
                calendarIdentifier: calendarName.lowercased(),
                color: color,
                isEditable: true
            )
        }
        return [
            event("demo-1", "Weekly planning", 1, 9, 1, .gold),
            event("demo-2", "Design critique", 1, 13, 1.5, .violet),
            event("demo-3", "Coffee with Maya", 2, 10, 1, .coral, "Personal"),
            event("demo-4", "Deep work · Calendar sync", 2, 14, 2, .blue),
            event("demo-5", "Product review", 3, 11, 1, .mint),
            event("demo-6", "Gym", 3, 17, 1, .coral, "Personal"),
            event("demo-7", "Ship Daylight beta", 4, 15, 1, .gold),
            event("demo-8", "Weekly reset", 5, 10, 1.5, .mint, "Personal")
        ]
    }
}
