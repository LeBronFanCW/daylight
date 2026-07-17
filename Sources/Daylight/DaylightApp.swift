import AppKit
import SwiftUI

@main
struct DaylightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                model: appDelegate.model,
                updateManager: appDelegate.updateManager,
                lockScreenManager: appDelegate.lockScreenManager,
                launchAtLoginManager: appDelegate.launchAtLoginManager
            )
        } label: {
            MenuBarLabel(model: appDelegate.model, updateManager: appDelegate.updateManager)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updateManager = UpdateManager()
    let launchAtLoginManager = LaunchAtLoginManager()
    let calendarIcon = DynamicCalendarIconController()
    lazy var lockScreenManager = LockScreenWallpaperManager(model: model)
    private var desktopWindowController: DesktopWindowController?
    private var hotKeyManager: HotKeyManager?
    private lazy var backgroundStudioController = BackgroundStudioWindowController(
        appModel: model,
        lockScreenManager: lockScreenManager
    )
    private var studioObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        calendarIcon.start()

        let controller = DesktopWindowController(model: model)
        desktopWindowController = controller
        controller.show()

        let hotKey = HotKeyManager { [weak model] in
            model?.toggleInteractiveMode()
        }
        hotKeyManager = hotKey
        hotKey.register()
        launchAtLoginManager.start()
        studioObserver = NotificationCenter.default.addObserver(
            forName: .daylightShowBackgroundStudio,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.showBackgroundStudio() }
        }

        Task {
            await model.start()
            lockScreenManager.start()
        }

        if ProcessInfo.processInfo.arguments.contains("--studio") {
            DispatchQueue.main.async { [weak self] in self?.showBackgroundStudio() }
        }
    }

    func showBackgroundStudio() {
        backgroundStudioController.show()
    }
}

extension Notification.Name {
    static let daylightShowBackgroundStudio = Notification.Name("daylight.showBackgroundStudio")
}

private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        Image(systemName: iconName)
            .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        if updateManager.updateAvailable {
            return "calendar.badge.exclamationmark"
        }
        return model.isInteractive ? "calendar.badge.checkmark" : "calendar"
    }

    private var accessibilityLabel: String {
        if updateManager.updateAvailable {
            return "Daylight update available"
        }
        return model.isInteractive ? "Daylight interactive" : "Daylight passive"
    }
}

private struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updateManager: UpdateManager
    @ObservedObject var lockScreenManager: LockScreenWallpaperManager
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager

    var body: some View {
        Button {
            if model.showsDaylightBackground {
                lockScreenManager.restoreOriginalBackground()
                model.setDaylightBackgroundVisible(false)
            } else {
                model.setDaylightBackgroundVisible(true)
            }
        } label: {
            Label(
                model.showsDaylightBackground ? "Show Original Wallpaper" : "Show Daylight Background",
                systemImage: model.showsDaylightBackground ? "photo" : "calendar"
            )
        }

        Button {
            NotificationCenter.default.post(name: .daylightShowBackgroundStudio, object: nil)
        } label: {
            Label("Create Background…", systemImage: "sparkles")
        }
        .keyboardShortcut("b", modifiers: [.command])

        Divider()

        Button {
            model.toggleInteractiveMode()
        } label: {
            Label(
                model.isInteractive ? "Return to Background" : "Make Calendar Interactive",
                systemImage: model.isInteractive ? "cursorarrow.slash" : "cursorarrow.motionlines"
            )
        }
        .keyboardShortcut("t", modifiers: [.control, .shift])

        Divider()

        Menu("View") {
            ForEach(CalendarViewMode.allCases) { mode in
                Button {
                    model.selectViewMode(mode)
                } label: {
                    Label(mode.title, systemImage: model.viewMode == mode ? "checkmark" : mode.symbol)
                }
            }
        }

        Menu("Appearance") {
            Button {
                model.useAutomaticAppearance()
            } label: {
                Label(
                    "Match Background Automatically",
                    systemImage: model.usesAutomaticAppearance ? "checkmark" : "circle.lefthalf.filled"
                )
            }

            Divider()

            ForEach(DaylightAppearance.allCases) { appearance in
                Button {
                    model.setAppearance(appearance)
                } label: {
                    Label(
                        appearance.title,
                        systemImage: !model.usesAutomaticAppearance && model.appearanceMode == appearance ? "checkmark" : appearance.symbol
                    )
                }
            }
        }

        Menu("Lock Screen") {
            Toggle("Show Daylight on Lock Screen", isOn: Binding(
                get: { lockScreenManager.isEnabled },
                set: { lockScreenManager.setEnabled($0) }
            ))

            Toggle("Show Event Titles", isOn: Binding(
                get: { !lockScreenManager.hidesEventTitles },
                set: { lockScreenManager.setShowsEventTitles($0) }
            ))
            .disabled(!lockScreenManager.isEnabled)

            Button("Refresh Snapshot") {
                lockScreenManager.refreshNow()
            }
            .disabled(!lockScreenManager.isEnabled || lockScreenManager.isRefreshing)

            if let error = lockScreenManager.lastError {
                Text(error)
            } else {
                Text("Read-only snapshot · titles hidden by default")
            }
        }

        Button {
            model.goToToday()
        } label: {
            Label("Go to Today", systemImage: "scope")
        }

        Divider()

        if model.authorization != .fullAccess && !model.isDemoMode {
            Button {
                Task { await model.requestCalendarAccess() }
            } label: {
                Label("Connect Apple Calendar…", systemImage: "checkmark.shield")
            }
        }

        Button {
            Task { await model.refresh() }
        } label: {
            Label("Refresh Now", systemImage: "arrow.clockwise")
        }
        .disabled(model.isRefreshing)

        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        } label: {
            Label("Open Apple Calendar", systemImage: "arrow.up.forward.app")
        }

        Divider()

        Toggle("Launch Daylight at Login", isOn: Binding(
            get: { launchAtLoginManager.desiredEnabled },
            set: { launchAtLoginManager.setEnabled($0) }
        ))

        if launchAtLoginManager.requiresApproval {
            Button("Approve in Login Item Settings…") {
                launchAtLoginManager.openLoginItemSettings()
            }
            Text("macOS approval is required before Daylight can start automatically.")
        } else if let error = launchAtLoginManager.lastError {
            Text(error)
        }

        Divider()

        Button(updateManager.updateAvailable ? "Install Available Update…" : "Check for Updates…") {
            updateManager.checkForUpdates()
        }
        .disabled(!updateManager.canCheckForUpdates)

        Text("Control–Shift–T toggles interaction")
        Button("Quit Daylight") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
