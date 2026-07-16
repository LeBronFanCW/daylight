import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable
}

enum LaunchAtLoginAction: Equatable {
    case none
    case register
    case unregister
}

enum LaunchAtLoginDecision {
    static func action(desiredEnabled: Bool, status: LaunchAtLoginStatus) -> LaunchAtLoginAction {
        switch (desiredEnabled, status) {
        case (true, .notRegistered):
            return .register
        case (false, .enabled), (false, .requiresApproval):
            return .unregister
        default:
            return .none
        }
    }
}

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var desiredEnabled: Bool
    @Published private(set) var status: LaunchAtLoginStatus = .notRegistered
    @Published private(set) var lastError: String?

    private let service = SMAppService.mainApp
    private let legacyService = LegacyLaunchAgent()
    private let defaults: UserDefaults
    private let desiredEnabledKey = "daylight.launchAtLogin.desiredEnabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: desiredEnabledKey) == nil {
            desiredEnabled = true
            defaults.set(true, forKey: desiredEnabledKey)
        } else {
            desiredEnabled = defaults.bool(forKey: desiredEnabledKey)
        }
        refreshStatus()
    }

    var isEnabled: Bool {
        status == .enabled
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func start() {
        applyDesiredState()
    }

    func setEnabled(_ enabled: Bool) {
        desiredEnabled = enabled
        defaults.set(enabled, forKey: desiredEnabledKey)
        lastError = nil
        applyDesiredState()
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func applyDesiredState() {
        refreshStatus()

        if !desiredEnabled, legacyService.isInstalled {
            do {
                try legacyService.uninstall()
            } catch {
                lastError = "Couldn’t turn off Launch at Login: \(error.localizedDescription)"
                return
            }
        }

        if service.status == .notFound {
            applyLegacyDesiredState()
            return
        }

        do {
            switch LaunchAtLoginDecision.action(desiredEnabled: desiredEnabled, status: status) {
            case .register:
                try service.register()
            case .unregister:
                try service.unregister()
            case .none:
                break
            }
            refreshStatus()
            if status == .enabled, legacyService.isInstalled {
                try? legacyService.uninstall()
            }
        } catch {
            applyLegacyDesiredState(nativeError: error)
        }
    }

    private func applyLegacyDesiredState(nativeError: Error? = nil) {
        do {
            if desiredEnabled {
                try legacyService.install()
                status = .enabled
            } else {
                try legacyService.uninstall()
                status = .notRegistered
            }
            lastError = nil
        } catch {
            let reason = nativeError.map { "\($0.localizedDescription); " } ?? ""
            lastError = "Couldn’t update Launch at Login: \(reason)\(error.localizedDescription)"
            status = legacyService.isInstalled ? .enabled : .unavailable
        }
    }

    private func refreshStatus() {
        switch service.status {
        case .notRegistered:
            status = .notRegistered
        case .enabled:
            status = .enabled
        case .requiresApproval:
            status = .requiresApproval
        case .notFound:
            status = legacyService.isInstalled ? .enabled : .unavailable
        @unknown default:
            status = .unavailable
        }
    }
}

private struct LegacyLaunchAgent {
    private let label = "com.callanwatkins.daylight.launch-at-login"

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func install() throws {
        let directory = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let appPath = Bundle.main.bundleURL.path
        let propertyList: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-gja", appPath],
            "RunAtLoad": true,
            "ProcessType": "Interactive"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)

        _ = runLaunchctl(["bootout", serviceTarget])
        let result = runLaunchctl(["bootstrap", domainTarget, plistURL.path])
        guard result == 0 else {
            throw LaunchAgentError.bootstrapFailed(result)
        }
    }

    func uninstall() throws {
        _ = runLaunchctl(["bootout", serviceTarget])
        if isInstalled {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    private var domainTarget: String {
        "gui/\(getuid())"
    }

    private var serviceTarget: String {
        "\(domainTarget)/\(label)"
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}

private enum LaunchAgentError: LocalizedError {
    case bootstrapFailed(Int32)

    var errorDescription: String? {
        switch self {
        case let .bootstrapFailed(status):
            return "the login agent could not be loaded (launchctl status \(status))"
        }
    }
}
