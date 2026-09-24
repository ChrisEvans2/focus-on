import AppKit

/// Reads production monitoring state; opening this window never starts another camera.
final class MonitorDiagnosticsController {
    private(set) var window: NSWindow?
    private let values = NSTextField(wrappingLabelWithString: "尚未开始专注监测。")
    private var latest = "尚未开始专注监测。"

    func update(_ text: String) {
        latest = text
        if window?.isVisible == true { values.stringValue = text }
    }

    func show() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 560),
                                 styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            panel.title = "Focus On · 监测诊断"
            panel.isReleasedWhenClosed = false
            let root = NSView(); panel.contentView = root
            let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
            stack.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
                stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24)
            ])
            let heading = NSTextField(labelWithString: "为什么还没提醒？")
            heading.font = .systemFont(ofSize: 21, weight: .semibold)
            values.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            values.isSelectable = true
            let note = NSTextField(wrappingLabelWithString: "头部与双眼共同判断。视线是 Apple Vision 点位的近似估计，不能区分看键盘和看手机；反光或点位不稳时退回头部判断。此窗口只读，不保存画面。")
            note.font = .systemFont(ofSize: 13); note.textColor = .secondaryLabelColor
            for view in [heading, values, note] {
                stack.addArrangedSubview(view)
                view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            panel.center(); window = panel
        }
        values.stringValue = latest
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}
