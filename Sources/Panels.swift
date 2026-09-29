import AppKit
import SwiftUI

/// A borderless panel that can take keyboard focus.
///
/// A plain NSPanel with .nonactivatingPanel never becomes key, which would be
/// fine for a menu but wrong for settings: text fields and pickers would take
/// no input at all.
private final class KeyablePanel: NSPanel {
    var wantsKey = false
    override var canBecomeKey: Bool { wantsKey }
}

/// Shows arbitrary SwiftUI content in a panel under a menu bar item.
///
/// AppKit offers NSMenu and NSPopover for this, and neither can be styled:
/// their appearance belongs to the system. So the panel is an ordinary window
/// with our own content, and everything the system would do for free has to be
/// reproduced by hand — dismissing on an outside click and on Escape.
@MainActor
final class FloatingPanel {
    private var panel: KeyablePanel?
    private var dismissMonitor: Any?
    private var keyMonitor: Any?

    var isShown: Bool { panel != nil }

    /// - Parameter takesFocus: whether the content needs keyboard input.
    func show(
        _ content: some View,
        below button: NSStatusBarButton,
        takesFocus: Bool = false
    ) {
        hide()

        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        let panel = KeyablePanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.wantsKey = takesFocus
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = hosting

        panel.setFrameTopLeftPoint(anchor(below: button, width: hosting.frame.width))
        if takesFocus {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            panel.orderFrontRegardless()
        }
        self.panel = panel

        dismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { _ in
            MainActor.assumeIsolated { [weak self] in self?.hide() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // While a chooser owns Escape, it closes the chooser or cancels a
            // recording inside it, and must not close the panel around it.
            guard event.keyCode == 53, !EscapeOwner.claimed else { return event }   // 53 = Escape
            MainActor.assumeIsolated { [weak self] in self?.hide() }
            return nil
        }
    }

    func hide() {
        if let dismissMonitor { NSEvent.removeMonitor(dismissMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        dismissMonitor = nil
        keyMonitor = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Places the panel under the icon, keeping it on screen at either edge.
    private func anchor(below button: NSStatusBarButton, width: CGFloat) -> NSPoint {
        guard let window = button.window else { return .zero }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        var x = frame.midX - width / 2
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) {
            let visible = screen.visibleFrame
            x = min(max(x, visible.minX + 8), visible.maxX - width - 8)
        }
        return NSPoint(x: x, y: frame.minY - 6)
    }
}

/// The dark rounded chrome shared by every surface of the app.
///
/// The dark scheme is forced rather than followed: the row highlight and the
/// hairline edge are tuned for a dark ground, and on a light one they would
/// read as smudges.
struct PanelChrome: ViewModifier {
    var radius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color.black.opacity(0.34)
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    // Without this edge the panel bleeds into a dark background
                    // and loses its shape.
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
            }
            .preferredColorScheme(.dark)
    }
}

extension View {
    func panelChrome(radius: CGFloat = 12) -> some View {
        modifier(PanelChrome(radius: radius))
    }

    /// Strips a system popover's own background so our chrome is what shows.
    /// Without it the system draws a light vibrant plate around dark content.
    @ViewBuilder
    func clearPopoverBackground() -> some View {
        if #available(macOS 13.3, *) {
            self.presentationBackground(.clear)
        } else {
            self
        }
    }
}
