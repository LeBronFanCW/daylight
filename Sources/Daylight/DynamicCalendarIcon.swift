import AppKit
import Foundation

enum DynamicCalendarDate {
    static func dayNumber(at date: Date = Date(), calendar: Calendar = .current) -> Int {
        calendar.component(.day, from: date)
    }

    static func nextRefreshDate(after date: Date = Date(), calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: date)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? date.addingTimeInterval(86_400)
        return startOfTomorrow.addingTimeInterval(1)
    }
}

@MainActor
final class DynamicCalendarIconController: ObservableObject {
    @Published private(set) var dayNumber = DynamicCalendarDate.dayNumber()

    private var midnightTimer: Timer?
    private var dayChangeObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    func start() {
        refresh()

        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        dayNumber = DynamicCalendarDate.dayNumber()
        NSApp.applicationIconImage = DynamicCalendarIconRenderer.image(day: dayNumber)
        scheduleMidnightRefresh()
    }

    private func scheduleMidnightRefresh() {
        midnightTimer?.invalidate()
        let timer = Timer(
            fire: DynamicCalendarDate.nextRefreshDate(),
            interval: 0,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }

    deinit {
        midnightTimer?.invalidate()
        if let dayChangeObserver { NotificationCenter.default.removeObserver(dayChangeObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}

enum DynamicCalendarIconRenderer {
    static func image(day: Int, size: CGFloat = 1024) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        context.saveGState()
        context.scaleBy(x: size / 1024, y: size / 1024)

        let outer = NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 220, yRadius: 220)
        NSGradient(colors: [
            NSColor(red: 0.06, green: 0.12, blue: 0.13, alpha: 1),
            NSColor(red: 0.02, green: 0.05, blue: 0.07, alpha: 1)
        ])?.draw(in: outer, angle: -45)

        context.setShadow(offset: CGSize(width: 0, height: -18), blur: 34, color: NSColor.black.withAlphaComponent(0.30).cgColor)
        let sheet = NSBezierPath(roundedRect: NSRect(x: 208, y: 174, width: 608, height: 676), xRadius: 92, yRadius: 92)
        NSColor(red: 0.94, green: 0.92, blue: 0.84, alpha: 1).setFill()
        sheet.fill()
        context.setShadow(offset: .zero, blur: 0, color: nil)

        let headerColor = NSColor(red: 0.96, green: 0.70, blue: 0.24, alpha: 1)
        headerColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 208, y: 690, width: 608, height: 160), xRadius: 92, yRadius: 92).fill()
        NSBezierPath(rect: NSRect(x: 208, y: 690, width: 608, height: 80)).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        String(day).draw(
            in: NSRect(x: 208, y: 276, width: 608, height: 340),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 280, weight: .semibold),
                .foregroundColor: NSColor(red: 0.06, green: 0.11, blue: 0.12, alpha: 1),
                .paragraphStyle: paragraph
            ]
        )

        for x in [330.0, 694.0] {
            let ring = NSBezierPath(roundedRect: NSRect(x: x - 24, y: 792, width: 48, height: 116), xRadius: 24, yRadius: 24)
            NSColor(red: 0.48, green: 0.82, blue: 0.73, alpha: 1).setFill()
            ring.fill()
        }

        context.restoreGState()
        image.unlockFocus()
        return image
    }
}
