import SwiftUI

struct DesktopCalendarView: View {
    @ObservedObject var model: AppModel
    let renderingMode: CalendarRenderingMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let calendar = Calendar.current
    private var palette: DaylightPalette {
        let palette = model.resolvedAppearance.palette
        return model.customBackgroundURL == nil ? palette : palette.adaptedForWallpaper
    }
    private var isInteractive: Bool { model.isInteractive && !renderingMode.isLockScreen }

    init(model: AppModel, renderingMode: CalendarRenderingMode = .live) {
        self.model = model
        self.renderingMode = renderingMode
    }

    var body: some View {
        ZStack {
            background

            ambientTexture

            if model.authorization == .fullAccess {
                VStack(spacing: 0) {
                    header

                    if isInteractive {
                        InteractionToolbar(model: model)
                            .padding(.bottom, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    content
                }
                .padding(.horizontal, DaylightTheme.xLarge)
                .padding(.top, 34)
                .padding(.bottom, 28)
            } else {
                content
                    .padding(.horizontal, DaylightTheme.xLarge)
                    .padding(.vertical, 28)
            }

            if !renderingMode.isLockScreen, let notice = model.notice {
                noticeView(notice)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .environment(\.daylightPalette, palette)
        .preferredColorScheme(model.resolvedAppearance.colorScheme)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: model.isInteractive)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.notice)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: model.viewMode)
        .tint(palette.focus)
        .sheet(item: $model.editorRoute) { route in
            EventEditorView(model: model, initialDraft: route.draft)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daylight \(model.viewMode.title.lowercased()) calendar")
    }

    @ViewBuilder
    private var background: some View {
        if let url = model.customBackgroundURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            (palette.isLight ? Color.white : Color.black)
                .opacity(model.wallpaperPresentation?.washOpacity ?? 0.26)
                .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [palette.canvasTop, palette.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    private var ambientTexture: some View {
        Canvas { context, size in
            for index in 0..<24 {
                let x = size.width * CGFloat((index * 37) % 101) / 101
                let y = size.height * CGFloat((index * 61) % 97) / 97
                let rect = CGRect(x: x, y: y, width: 1, height: 1)
                context.fill(Path(ellipseIn: rect), with: .color(palette.texture))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(spacing: 5) {
            Text(periodTitle)
                .font(.system(size: 34, weight: .medium, design: .serif))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .shadow(color: palette.isLight ? .white.opacity(0.72) : .black.opacity(0.78), radius: 5)
            Text(periodSubtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(palette.secondaryInk)
                .multilineTextAlignment(.center)
                .shadow(color: palette.isLight ? .white.opacity(0.68) : .black.opacity(0.74), radius: 4)
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.secondaryInk)
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, isInteractive && model.authorization == .fullAccess ? 14 : 24)
    }

    @ViewBuilder
    private var content: some View {
        switch model.authorization {
        case .fullAccess:
            switch model.viewMode {
            case .week:
                WeekCalendarView(
                    model: model,
                    isInteractive: isInteractive,
                    redactsEventTitles: renderingMode.hidesEventTitles
                )
                    .transition(.opacity)
            case .month:
                MonthCalendarView(
                    model: model,
                    isInteractive: isInteractive,
                    redactsEventTitles: renderingMode.hidesEventTitles
                )
                    .transition(.opacity)
            case .year:
                YearCalendarView(model: model)
                    .transition(.opacity)
            }
        case .notDetermined:
            permissionState(
                symbol: "calendar.badge.plus",
                title: "Bring Apple Calendar to your desktop",
                message: "Daylight reads and edits events only after you choose to connect it.",
                buttonTitle: "Connect Apple Calendar"
            )
        case .denied:
            permissionState(
                symbol: "calendar.badge.exclamationmark",
                title: "Calendar access is off",
                message: "Allow Daylight in System Settings → Privacy & Security → Calendars, then refresh.",
                buttonTitle: "Open System Settings"
            )
        }
    }

    private func permissionState(
        symbol: String,
        title: String,
        message: String,
        buttonTitle: String
    ) -> some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(palette.today)
            Text(title)
                .font(.system(size: 24, weight: .medium, design: .serif))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(palette.secondaryInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            if isInteractive {
                HStack(spacing: 10) {
                    Button {
                        if model.authorization == .denied {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                                NSWorkspace.shared.open(url)
                            }
                        } else {
                            Task { await model.requestCalendarAccess() }
                        }
                    } label: {
                        Text(buttonTitle)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.isLight ? Color.white : Color.black.opacity(0.84))
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .background(palette.focus, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.toggleAppearance()
                    } label: {
                        Label(
                            model.resolvedAppearance == .light ? "Dark" : "Light",
                            systemImage: model.resolvedAppearance == .light ? "moon.stars" : "sun.max"
                        )
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(palette.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(palette.rule, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.toggleInteractiveMode()
                    } label: {
                        Text("Done")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.ink)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(palette.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(palette.rule, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Label("Press Control–Shift–T or use the menu bar to interact", systemImage: "keyboard")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.quietInk)
            }
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func noticeView(_ message: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(palette.today)
                Text(message)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(palette.panel, in: Capsule())
            .overlay { Capsule().stroke(palette.rule, lineWidth: 1) }
            .padding(.top, 28)
            Spacer()
        }
        .allowsHitTesting(false)
        .accessibilityLabel(message)
    }

    private var periodTitle: String {
        switch model.viewMode {
        case .week, .month:
            return model.referenceDate.formatted(.dateTime.month(.wide).year())
        case .year:
            return model.referenceDate.formatted(.dateTime.year())
        }
    }

    private var periodSubtitle: String {
        switch model.viewMode {
        case .week: "Week view · Your schedule, quietly present"
        case .month: "Month view · Plan the shape of your days"
        case .year: "Year view · Choose a month to look closer"
        }
    }

    private var statusText: String {
        if model.isDemoMode { return "Preview calendar" }
        if model.authorization == .fullAccess { return "Synced with Apple Calendar" }
        return "Not connected"
    }

    private var statusColor: Color {
        model.authorization == .fullAccess ? EventColor.mint.swiftUIColor : palette.quietInk
    }
}

private struct InteractionToolbar: View {
    @ObservedObject var model: AppModel
    @Environment(\.daylightPalette) private var palette

    var body: some View {
        GlassControlSurface {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    toolbarButton("Previous \(model.viewMode.title.lowercased())", symbol: "chevron.left") {
                        model.navigatePeriod(by: -1)
                    }
                    Button("Today") { model.goToToday() }
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44)
                    toolbarButton("Next \(model.viewMode.title.lowercased())", symbol: "chevron.right") {
                        model.navigatePeriod(by: 1)
                    }
                }

                Divider().frame(height: 24)

                Picker("Calendar view", selection: Binding(
                    get: { model.viewMode },
                    set: { model.selectViewMode($0) }
                )) {
                    ForEach(CalendarViewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)

                Spacer()

                Button {
                    NotificationCenter.default.post(name: .daylightShowBackgroundStudio, object: nil)
                } label: {
                    Label("Create", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("b", modifiers: [.command])

                Button {
                    model.toggleAppearance()
                } label: {
                    Label(
                        model.resolvedAppearance == .light ? "Dark" : "Light",
                        systemImage: model.resolvedAppearance == .light ? "moon.stars" : "sun.max"
                    )
                }
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
                .help("Override automatic colors with \(model.resolvedAppearance == .light ? "dark" : "light") appearance")

                Button {
                    model.presentNewEvent(on: model.referenceDate)
                } label: {
                    Label("New event", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n")

                Button {
                    model.toggleInteractiveMode()
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func toolbarButton(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct WeekCalendarView: View {
    @ObservedObject var model: AppModel
    let isInteractive: Bool
    let redactsEventTitles: Bool
    @Environment(\.daylightPalette) private var palette
    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CalendarNavigation.weekDays(containing: model.referenceDate), id: \.self) { day in
                DayColumn(
                    day: day,
                    events: CalendarGrouping.events(on: day, from: model.events),
                    isToday: calendar.isDateInToday(day),
                    isInteractive: isInteractive,
                    redactsEventTitles: redactsEventTitles,
                    onAdd: { model.presentNewEvent(on: day) },
                    onSelect: { model.presentEditor(for: $0) }
                )
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(palette.rule).frame(height: 1)
        }
    }
}

private struct MonthCalendarView: View {
    @ObservedObject var model: AppModel
    let isInteractive: Bool
    let redactsEventTitles: Bool
    @Environment(\.daylightPalette) private var palette
    private let calendar = Calendar.current

    private var days: [Date] {
        CalendarNavigation.monthGridDays(containing: model.referenceDate)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = fittedCalendarSize(in: proxy.size)
            calendarGrid
                .frame(width: size.width, height: size.height)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private var calendarGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(palette.quietInk)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 28)

            GeometryReader { proxy in
                let rows = max(days.count / 7, 1)
                let cellHeight = proxy.size.height / CGFloat(rows)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                    spacing: 0
                ) {
                    ForEach(days, id: \.self) { day in
                        MonthDayCell(
                            day: day,
                            displayedMonth: model.referenceDate,
                            events: CalendarGrouping.events(on: day, from: model.events),
                            isInteractive: isInteractive,
                            redactsEventTitles: redactsEventTitles,
                            onAdd: { model.presentNewEvent(on: day) },
                            onSelect: { model.presentEditor(for: $0) }
                        )
                        .frame(height: cellHeight)
                    }
                }
            }
        }
    }

    private func fittedCalendarSize(in available: CGSize) -> CGSize {
        let rows = max(days.count / 7, 1)
        // A consistent cell proportion keeps all five- and six-row months
        // visible while centering the calendar on every display shape.
        let aspectRatio = 7 / (CGFloat(rows) * 0.82)
        guard available.width > 0, available.height > 0 else { return .zero }

        if available.width / available.height > aspectRatio {
            return CGSize(width: available.height * aspectRatio, height: available.height)
        }
        return CGSize(width: available.width, height: available.width / aspectRatio)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[offset...] + symbols[..<offset])
    }
}

private struct MonthDayCell: View {
    let day: Date
    let displayedMonth: Date
    let events: [CalendarEvent]
    let isInteractive: Bool
    let redactsEventTitles: Bool
    let onAdd: () -> Void
    let onSelect: (CalendarEvent) -> Void

    @Environment(\.daylightPalette) private var palette
    private let calendar = Calendar.current

    private var isInMonth: Bool {
        calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 13, weight: calendar.isDateInToday(day) ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(calendar.isDateInToday(day) ? palette.today : (isInMonth ? palette.ink : palette.quietInk.opacity(0.58)))
                    .frame(minWidth: 28, minHeight: 28, alignment: .leading)
                Spacer()
                if isInteractive && isInMonth {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.focus)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Add event on \(day.formatted(date: .long, time: .omitted))")
                    .accessibilityLabel("Add event on \(day.formatted(date: .long, time: .omitted))")
                }
            }

            ForEach(events.prefix(3)) { event in
                Button {
                    if isInteractive && event.isEditable { onSelect(event) }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(event.color.swiftUIColor).frame(width: 6, height: 6)
                        Text(redactsEventTitles ? "Busy" : event.title)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 7)
                    .frame(maxWidth: .infinity, minHeight: 25, alignment: .leading)
                    .background(event.color.swiftUIColor.opacity(palette.isLight ? 0.14 : 0.11), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(redactsEventTitles ? "Busy" : event.title), \(event.startDate.formatted(date: .omitted, time: .shortened))")
                .accessibilityHint(isInteractive && event.isEditable ? "Opens event editor" : "")
            }

            if events.count > 3 {
                Text("+\(events.count - 3) more")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.quietInk)
                    .padding(.leading, 7)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .opacity(isInMonth ? 1 : 0.50)
        .background(calendar.isDateInToday(day) ? palette.today.opacity(0.07) : Color.clear)
        .overlay(alignment: .top) { Rectangle().fill(palette.rule).frame(height: 1) }
        .overlay(alignment: .trailing) { Rectangle().fill(palette.rule).frame(width: 1) }
    }
}

private struct YearCalendarView: View {
    @ObservedObject var model: AppModel
    private let calendar = Calendar.current

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 4),
            spacing: 18
        ) {
            ForEach(CalendarNavigation.months(inYearContaining: model.referenceDate), id: \.self) { month in
                MiniMonthView(month: month, events: model.events) {
                    model.selectViewMode(.month, focus: month)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct MiniMonthView: View {
    let month: Date
    let events: [CalendarEvent]
    let action: () -> Void

    @Environment(\.daylightPalette) private var palette
    private let calendar = Calendar.current

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(month.formatted(.dateTime.month(.wide)))
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundStyle(palette.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.quietInk)
                }

                HStack(spacing: 0) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.quietInk)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7),
                    spacing: 3
                ) {
                    ForEach(CalendarNavigation.monthGridDays(containing: month), id: \.self) { day in
                        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
                        let hasEvents = !CalendarGrouping.events(on: day, from: events).isEmpty
                        ZStack(alignment: .bottom) {
                            Text(day.formatted(.dateTime.day()))
                                .font(.system(size: 8, weight: calendar.isDateInToday(day) ? .bold : .medium, design: .rounded))
                                .foregroundStyle(calendar.isDateInToday(day) ? palette.today : palette.secondaryInk)
                                .opacity(inMonth ? 1 : 0)
                            if inMonth && hasEvents {
                                Circle()
                                    .fill(palette.focus)
                                    .frame(width: 3, height: 3)
                                    .offset(y: 2)
                            }
                        }
                        .frame(height: 15)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .top)
            .background(palette.elevatedPanel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(palette.rule, lineWidth: 1)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("Open \(month.formatted(.dateTime.month(.wide).year())) month view")
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[offset...] + symbols[..<offset])
    }
}

private struct DayColumn: View {
    let day: Date
    let events: [CalendarEvent]
    let isToday: Bool
    let isInteractive: Bool
    let redactsEventTitles: Bool
    let onAdd: () -> Void
    let onSelect: (CalendarEvent) -> Void

    @Environment(\.daylightPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayHeader
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Rectangle().fill(palette.rule).frame(height: 1)

            if events.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(events) { event in
                            EventCard(
                                event: event,
                                isInteractive: isInteractive,
                                redactsEventTitle: redactsEventTitles
                            ) {
                                onSelect(event)
                            }
                        }
                    }
                    .padding(10)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(isToday ? palette.today.opacity(0.05) : Color.clear)
        .overlay(alignment: .trailing) {
            Rectangle().fill(palette.rule).frame(width: 1)
        }
    }

    private var dayHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(isToday ? palette.today : palette.quietInk)
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(palette.ink)
            }
            Spacer()
            if isInteractive {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .foregroundStyle(palette.focus)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Add event on \(day.formatted(date: .long, time: .omitted))")
                .accessibilityLabel("Add event on \(day.formatted(date: .long, time: .omitted))")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Text("Open")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(palette.quietInk)
            if isInteractive {
                Button("Add event", action: onAdd)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.focus)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EventCard: View {
    let event: CalendarEvent
    let isInteractive: Bool
    let redactsEventTitle: Bool
    let action: () -> Void

    @Environment(\.daylightPalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(event.color.swiftUIColor)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 6) {
                    Text(redactsEventTitle ? "Busy" : event.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        Text(timeText)
                        Text("·")
                        Text(redactsEventTitle ? "Private" : event.calendarTitle).lineLimit(1)
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondaryInk)
                }
                Spacer(minLength: 0)
                if isInteractive && event.isEditable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.quietInk)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(event.color.swiftUIColor.opacity(palette.isLight ? 0.13 : 0.10), in: RoundedRectangle(cornerRadius: DaylightTheme.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DaylightTheme.radius, style: .continuous)
                    .stroke(event.color.swiftUIColor.opacity(isInteractive ? 0.34 : 0.22), lineWidth: 1)
            }
        }
        .buttonStyle(EventCardButtonStyle(isEnabled: isInteractive && event.isEditable))
        .disabled(!isInteractive || !event.isEditable)
        .accessibilityLabel(redactsEventTitle ? "Busy, \(timeText)" : "\(event.title), \(timeText), \(event.calendarTitle)")
        .accessibilityHint(isInteractive && event.isEditable ? "Opens event editor" : "")
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        return event.startDate.formatted(date: .omitted, time: .shortened)
    }
}

private struct EventCardButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed && isEnabled ? 0.74 : 1)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.80 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
