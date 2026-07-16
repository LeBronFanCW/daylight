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
        } catch {
            lastError = "Couldn’t update Launch at Login: \(error.localizedDescription)"
            refreshStatus()
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
            status = .unavailable
        @unknown default:
            status = .unavailable
        }
    }
}
