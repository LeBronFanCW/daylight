import AppKit
import XCTest
@testable import Daylight

final class DaylightTests: XCTestCase {
    @MainActor
    func testDesktopWindowCanReceiveFocus() {
        let window = DesktopWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.canBecomeMain)
    }

    func testDraftRequiresTitle() {
        let draft = EventDraft(newOn: Date())
        XCTAssertEqual(draft.validationMessage, "Add a title before saving.")
    }

    func testDraftRejectsEndBeforeStart() {
        var draft = EventDraft(newOn: Date())
        draft.title = "Planning"
        draft.endDate = draft.startDate.addingTimeInterval(-60)
        XCTAssertEqual(draft.validationMessage, "The end time needs to be after the start time.")
    }

    func testGroupingSortsAllDayFirstThenByStartTime() {
        let calendar = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let timed = CalendarEvent(
            id: "timed", title: "Timed", startDate: day.addingTimeInterval(3600),
            endDate: day.addingTimeInterval(7200), isAllDay: false, notes: "",
            calendarTitle: "Work", calendarIdentifier: "work", color: .blue, isEditable: true
        )
        let allDay = CalendarEvent(
            id: "all-day", title: "All Day", startDate: day,
            endDate: day.addingTimeInterval(86_400), isAllDay: true, notes: "",
            calendarTitle: "Work", calendarIdentifier: "work", color: .gold, isEditable: true
        )

        let grouped = CalendarGrouping.events(on: day, from: [timed, allDay], calendar: calendar)
        XCTAssertEqual(grouped.map(\.id), ["all-day", "timed"])
    }

    func testMonthGridStartsOnFirstWeekdayAndUsesWholeWeeks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        let reference = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!

        let days = CalendarNavigation.monthGridDays(containing: reference, calendar: calendar)

        XCTAssertFalse(days.isEmpty)
        XCTAssertEqual(days.count % 7, 0)
        XCTAssertEqual(calendar.component(.weekday, from: days[0]), calendar.firstWeekday)
        XCTAssertTrue(days.contains { calendar.component(.day, from: $0) == 31 && calendar.component(.month, from: $0) == 7 })
    }

    func testVisibleYearIntervalContainsTwelveMonths() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!

        let interval = CalendarNavigation.visibleInterval(for: .year, referenceDate: reference, calendar: calendar)
        let months = calendar.dateComponents([.month], from: interval.start, to: interval.end).month

        XCTAssertEqual(months, 12)
        XCTAssertTrue(interval.contains(reference))
    }

    func testPeriodNavigationMovesBySelectedGranularity() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!

        let nextMonth = CalendarNavigation.movedDate(from: reference, mode: .month, by: 1, calendar: calendar)
        let previousYear = CalendarNavigation.movedDate(from: reference, mode: .year, by: -1, calendar: calendar)

        XCTAssertEqual(calendar.component(.month, from: nextMonth), 8)
        XCTAssertEqual(calendar.component(.year, from: previousYear), 2025)
    }

    func testMultiDayEventAppearsOnEveryOverlappingDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 18))!
        let event = CalendarEvent(
            id: "trip", title: "Trip", startDate: start,
            endDate: calendar.date(byAdding: .day, value: 2, to: start)!, isAllDay: false, notes: "",
            calendarTitle: "Personal", calendarIdentifier: "personal", color: .coral, isEditable: true
        )
        let nextDay = calendar.date(byAdding: .day, value: 1, to: start)!

        XCTAssertEqual(CalendarGrouping.events(on: nextDay, from: [event], calendar: calendar).map(\.id), ["trip"])
    }
}
