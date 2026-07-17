import AppKit
import Combine
import SwiftUI

@MainActor
final class LockScreenWallpaperManager: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var hidesEventTitles: Bool
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private let model: AppModel
    private let defaults: UserDefaults
    private var subscriptions = Set<AnyCancellable>()
    private var hasStarted = false

    private let enabledKey = "daylight.lockScreen.enabled"
    private let hidesTitlesKey = "daylight.lockScreen.hidesEventTitles"
    private let originalWallpapersKey = "daylight.lockScreen.originalWallpapers"

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        isEnabled = defaults.object(forKey: enabledKey) as? Bool ?? true
        hidesEventTitles = defaults.object(forKey: hidesTitlesKey) as? Bool ?? true

        Publishers.CombineLatest4(model.$events, model.$viewMode, model.$referenceDate, model.$appearanceMode)
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshIfPossible() }
            .store(in: &subscriptions)

        model.$authorization
            .removeDuplicates()
            .sink { [weak self] _ in self?.refreshIfPossible() }
            .store(in: &subscriptions)

        model.$customBackgroundURL
            .removeDuplicates()
            .sink { [weak self] _ in self?.refreshIfPossible() }
            .store(in: &subscriptions)

        Publishers.CombineLatest(model.$wallpaperPresentation, model.$usesAutomaticAppearance)
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshIfPossible() }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refreshIfPossible() }
            .store(in: &subscriptions)
    }

    func start() {
        hasStarted = true
        refreshIfPossible()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: enabledKey)
        lastError = nil
        enabled ? refreshIfPossible() : restoreOriginalWallpapers()
    }

    func setShowsEventTitles(_ showsTitles: Bool) {
        hidesEventTitles = !showsTitles
        defaults.set(hidesEventTitles, forKey: hidesTitlesKey)
        refreshIfPossible()
    }

    func refreshNow() {
        refreshIfPossible()
    }

    private func refreshIfPossible() {
        guard hasStarted, isEnabled, model.authorization == .fullAccess, !isRefreshing else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            captureOriginalWallpapersIfNeeded()
            try FileManager.default.createDirectory(at: wallpaperDirectory, withIntermediateDirectories: true)

            for screen in NSScreen.screens {
                let imageURL = try renderWallpaper(for: screen)
                try NSWorkspace.shared.setDesktopImageURL(
                    imageURL,
                    for: screen,
                    options: [
                        .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,
                        .allowClipping: true
                    ]
                )
            }
            lastError = nil
        } catch {
            lastError = "Lock Screen: \(error.localizedDescription)"
        }
    }

    private func renderWallpaper(for screen: NSScreen) throws -> URL {
        let size = screen.frame.size
        let content = DesktopCalendarView(
            model: model,
            renderingMode: .lockScreen(hideEventTitles: hidesEventTitles)
        )
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = screen.backingScaleFactor

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw WallpaperError.renderFailed
        }

        let url = wallpaperDirectory.appendingPathComponent("daylight-lock-\(screenIdentifier(screen)).png")
        try png.write(to: url, options: .atomic)
        return url
    }

    private func captureOriginalWallpapersIfNeeded() {
        guard defaults.dictionary(forKey: originalWallpapersKey) == nil else { return }

        var originals: [String: String] = [:]
        for screen in NSScreen.screens {
            if let url = NSWorkspace.shared.desktopImageURL(for: screen) {
                originals[screenIdentifier(screen)] = url.absoluteString
            }
        }
        defaults.set(originals, forKey: originalWallpapersKey)
    }

    private func restoreOriginalWallpapers() {
        guard let originals = defaults.dictionary(forKey: originalWallpapersKey) as? [String: String] else { return }

        do {
            for screen in NSScreen.screens {
                guard let rawURL = originals[screenIdentifier(screen)], let url = URL(string: rawURL) else { continue }
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen)
            }
            defaults.removeObject(forKey: originalWallpapersKey)
            lastError = nil
        } catch {
            lastError = "Couldn’t restore wallpaper: \(error.localizedDescription)"
        }
    }

    private var wallpaperDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Daylight/Wallpapers", isDirectory: true)
    }

    private func screenIdentifier(_ screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.stringValue ?? "main"
    }
}

private enum WallpaperError: LocalizedError {
    case renderFailed

    var errorDescription: String? {
        "Daylight couldn’t render the lock screen snapshot."
    }
}
