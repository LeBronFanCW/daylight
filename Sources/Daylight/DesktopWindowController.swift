import AppKit
import Combine
import CoreGraphics
import SwiftUI

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        (screen ?? self.screen ?? NSScreen.main)?.frame ?? frameRect
    }
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

        model.$showsDaylightBackground
            .removeDuplicates()
            .sink { [weak self] isVisible in
                self?.applyBackgroundVisibility(isVisible)
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
        window.minSize = screen.frame.size
        window.maxSize = screen.frame.size
        let hostingView = NSHostingView(rootView: DesktopCalendarView(model: model))
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // Keep SwiftUI inside an AppKit-owned container. Making the hosting
        // view the window's content view lets its wallpaper-derived ideal size
        // (often square) override the display's actual aspect ratio.
        let containerView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        containerView.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        window.contentView = containerView
        // NSHostingView otherwise applies its square ideal size to this
        // borderless window, which can push the final month rows off-screen.
        window.setFrame(screen.frame, display: false)
        containerView.frame = NSRect(origin: .zero, size: screen.frame.size)
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
        if model.showsDaylightBackground {
            window.orderFrontRegardless()
            window.setFrame(screen.frame, display: true)
        } else {
            window.orderOut(nil)
        }
        self.window = window

        // SwiftUI resolves the background image's ideal size on the next run
        // loop. Reassert the physical display bounds after that sizing pass.
        DispatchQueue.main.async { [weak self] in
            self?.resizeToMainScreen()
        }

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
        guard let window, model.showsDaylightBackground else { return }
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

    private func applyBackgroundVisibility(_ isVisible: Bool) {
        guard let window else { return }
        if isVisible {
            applyInteractionMode(model.isInteractive)
            window.orderFrontRegardless()
            resizeToMainScreen()
        } else {
            window.orderOut(nil)
        }
    }

    private func resizeToMainScreen() {
        guard let screen = NSScreen.main, let window else { return }
        if model.showsDaylightBackground {
            window.orderFrontRegardless()
            window.minSize = NSSize(width: 1, height: 1)
            window.maxSize = screen.frame.size
            window.setFrame(screen.frame, display: true)
            window.contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
            window.contentView?.layoutSubtreeIfNeeded()
            window.minSize = screen.frame.size
            window.maxSize = screen.frame.size
        }
    }
}
