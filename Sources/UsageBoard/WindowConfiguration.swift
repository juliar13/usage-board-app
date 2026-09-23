import AppKit
import SwiftUI

struct WindowConfiguration: NSViewRepresentable {
    var keepOnTop: Bool

    func makeNSView(context: Context) -> WindowProbe { WindowProbe() }

    func updateNSView(_ view: WindowProbe, context: Context) {
        view.keepOnTop = keepOnTop
        view.apply()
    }
}

final class WindowProbe: NSView {
    var keepOnTop = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    func apply() {
        guard let window else { return }
        window.level = keepOnTop ? .floating : .normal
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.055, green: 0.065, blue: 0.077, alpha: 1)
    }
}
