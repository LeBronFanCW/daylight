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
                lockScreenManager: appDelegate.lockScreenManager
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
    lazy var lockScreenManager = LockScreenWallpaperManager(model: model)
    private var desktopWindowController: DesktopWindowController?
    private var hotKeyManager: HotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = DesktopWindowController(model: model)
        desktopWindowController = controller
        controller.show()

        let hotKey = HotKeyManager { [weak model] in
            model?.toggleInteractiveMode()
        }
        hotKeyManager = hotKey
        hotKey.register()

        Task {
            await model.start()
            lockScreenManager.start()
        }
    }
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

    var body: some View {
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
            ForEach(DaylightAppearance.allCases) { appearance in
                Button {
                    model.setAppearance(appearance)
                } label: {
                    Label(
                        appearance.title,
                        systemImage: model.appearanceMode == appearance ? "checkmark" : appearance.symbol
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
