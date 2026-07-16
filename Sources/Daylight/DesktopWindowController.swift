import AppKit
import Combine
import CoreGraphics
import SwiftUI

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class DesktopWindowController {
    private let model: AppModel
    private var window: NSWindow?
    private var subscriptions = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        model.$isInteractive
            .removeDuplicates()
            .sink { [weak self] isInteractive in
                self?.applyInteractionMode(isInteractive)
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.resizeToMainScreen() }
            .store(in: &subscriptions)
    }

    func show() {
        guard let screen = NSScreen.main else { return }
        let window = DesktopWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.contentView = NSHostingView(rootView: DesktopCalendarView(model: model))
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isMovable = false
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.level = desktopLayer
        window.ignoresMouseEvents = !model.isInteractive
        window.acceptsMouseMovedEvents = true
        window.orderFrontRegardless()
        self.window = window

        if model.isInteractive {
            applyInteractionMode(true)
        }
    }

    private var desktopLayer: NSWindow.Level {
        let rawLevel = CGWindowLevelForKey(.desktopWindow) + 1
        return NSWindow.Level(rawValue: Int(rawLevel))
    }

    private var interactiveLayer: NSWindow.Level {
        .floating
    }

    private func applyInteractionMode(_ interactive: Bool) {
        guard let window else { return }
        window.ignoresMouseEvents = !interactive
        if interactive {
            window.level = interactiveLayer
            window.orderFrontRegardless()
            window.makeKey()
        } else {
            window.resignKey()
            window.level = desktopLayer
            window.orderFrontRegardless()
        }
    }

    private func resizeToMainScreen() {
        guard let screen = NSScreen.main else { return }
        window?.setFrame(screen.frame, display: true)
        window?.orderFrontRegardless()
    }
}
