import AppKit
import FocusCore

struct MenuBarSnapshot {
    var title: String
    var status: String
    var remaining: Int
    var duration: Int
    var round: Int
    var rounds: Int
    var running: Bool
    var hasSession: Bool
    var finished: Bool
    var isBreak: Bool
    var progress: Double

    var time: String { Self.clock(remaining) }
    var actionTitle: String { isBreak && !finished ? "跳过休息" : running ? "暂停" : finished ? "重新开始" : hasSession ? "继续专注" : "开始专注" }
    static func clock(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }

    static func make(schedule: FocusSchedule?, taskTitle: String, at now: Double) -> Self {
        let phases = schedule?.phases ?? [FocusPhase(kind: "focus", seconds: 1500)]
        var elapsed = schedule?.elapsed ?? 0
        if schedule?.running == true, let start = schedule?.startedAt { elapsed += max(0, now - start) }
        let total = phases.reduce(0) { $0 + $1.seconds }
        let finished = elapsed >= total
        var index = 0
        while index < phases.count - 1 && elapsed >= phases[index].seconds {
            elapsed -= phases[index].seconds
            index += 1
        }
        let phase = phases[index]
        let running = schedule?.running == true && !finished
        let hasSession = schedule?.sessionId != nil
        let status = finished ? "已完成" : !hasSession ? "准备开始" : !running ? "已暂停" : phase.kind == "break" ? "休息中" : "专注中"
        return Self(title: taskTitle.isEmpty ? "未设置任务" : taskTitle, status: status,
                    remaining: max(0, Int(ceil(phase.seconds - elapsed))), duration: Int(ceil(phase.seconds)),
                    round: phases.prefix(index + 1).filter { $0.kind == "focus" }.count,
                    rounds: phases.filter { $0.kind == "focus" }.count,
                    running: running, hasSession: hasSession, finished: finished, isBreak: phase.kind == "break",
                    progress: hasSession ? min(1, max(0, (phase.seconds - elapsed) / phase.seconds)) : 0)
    }
}

struct FocusPopoverPalette {
    let canvas: NSColor, text: NSColor, muted: NSColor, accent: NSColor, rest: NSColor, soft: NSColor, line: NSColor, onAccent: NSColor
    init(dark: Bool) {
        func color(_ hex: Int) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
        canvas = color(dark ? 0x232221 : 0xf7f7f3)
        text = color(dark ? 0xebebeb : 0x2d302d)
        muted = color(dark ? 0xababab : 0x757a73)
        accent = color(dark ? 0xd6e92f : 0x597e6f)
        rest = color(dark ? 0x7f96e3 : 0xa86234)
        soft = color(dark ? 0x333333 : 0xedf1eb)
        line = color(dark ? 0x3b3b3b : 0xe5e7e0)
        onAccent = color(dark ? 0x1b1a19 : 0xffffff)
    }
}

final class FocusPopoverView: NSView {
    let statusLabel = NSTextField(labelWithString: "")
    let roundsLabel = NSTextField(labelWithString: "")
    let taskLabel = NSTextField(labelWithString: "当前任务")
    let titleLabel = NSTextField(wrappingLabelWithString: "")
    let timeLabel = NSTextField(labelWithString: "")
    let durationLabel = NSTextField(labelWithString: "")
    let toggleButton = HoverActionButton(title: "", target: nil, action: nil)
    let resetButton = HoverActionButton(title: "", target: nil, action: nil)
    private let dot = NSView()
    private let track = NSView()
    private let fill = NSView()
    var onToggle: (() -> Void)?
    var onReset: (() -> Void)?
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 272, height: 224))
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        for view in [dot, statusLabel, roundsLabel, taskLabel, titleLabel, timeLabel, durationLabel, track, toggleButton, resetButton] {
            addSubview(view)
        }
        track.addSubview(fill)
        for view in [dot, track, fill] { view.wantsLayer = true }
        dot.layer?.cornerRadius = 3
        track.layer?.cornerRadius = 3
        fill.layer?.cornerRadius = 3
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        for label in [statusLabel, roundsLabel, taskLabel, durationLabel] { label.font = .systemFont(ofSize: 11, weight: .medium) }
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .semibold)
        roundsLabel.alignment = .right
        durationLabel.alignment = .right
        for button in [toggleButton, resetButton] {
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            button.layer?.borderWidth = 1
            button.font = .systemFont(ofSize: 13, weight: .semibold)
            button.setButtonType(.momentaryChange)
            button.target = self
        }
        toggleButton.action = #selector(toggle)
        toggleButton.imagePosition = .imageLeft
        toggleButton.imageHugsTitle = true
        resetButton.action = #selector(reset)
        resetButton.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "重置整个专注计时")
        resetButton.imagePosition = .imageOnly
        resetButton.toolTip = "重置整个专注计时，返回第一轮"
        resetButton.setAccessibilityLabel("重置整个专注计时")
        toggleButton.nextKeyView = resetButton
        resetButton.nextKeyView = toggleButton
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func toggle() { onToggle?() }
    @objc private func reset() { onReset?() }

    func render(_ state: MenuBarSnapshot, dark: Bool, busy: Bool) {
        let palette = FocusPopoverPalette(dark: dark)
        let resting = state.isBreak && !state.finished
        let accent = resting ? palette.rest : palette.accent
        appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        layer?.backgroundColor = palette.canvas.cgColor
        layer?.borderColor = palette.line.cgColor
        statusLabel.stringValue = state.status
        roundsLabel.stringValue = "第 \(state.round) / \(state.rounds) 轮"
        titleLabel.stringValue = state.title
        titleLabel.toolTip = state.title
        taskLabel.stringValue = resting ? "休息时间 · 当前任务" : "当前任务"
        timeLabel.stringValue = state.time
        durationLabel.stringValue = "/ \(MenuBarSnapshot.clock(state.duration))"
        for label in [statusLabel, roundsLabel, taskLabel, durationLabel] { label.textColor = palette.muted }
        titleLabel.textColor = palette.text
        timeLabel.textColor = palette.text
        dot.layer?.backgroundColor = (state.running ? accent : palette.muted).cgColor
        track.layer?.backgroundColor = palette.line.cgColor
        fill.layer?.backgroundColor = accent.cgColor
        // Match the dial: remaining time shrinks the bar; reset leaves it empty.
        dot.frame = NSRect(x: 16, y: 21, width: 5, height: 5)
        statusLabel.frame = NSRect(x: 27, y: 14, width: 120, height: 18)
        roundsLabel.frame = NSRect(x: 156, y: 14, width: 100, height: 18)
        taskLabel.frame = NSRect(x: 16, y: 44, width: 240, height: 16)
        titleLabel.frame = NSRect(x: 16, y: 64, width: 240, height: 38)
        timeLabel.frame = NSRect(x: 14, y: 106, width: 176, height: 42)
        durationLabel.frame = NSRect(x: 192, y: 123, width: 64, height: 18)
        track.frame = NSRect(x: 16, y: 160, width: 240, height: 5)
        fill.frame = NSRect(x: 0, y: 0, width: 240 * state.progress, height: 5)
        toggleButton.frame = NSRect(x: 16, y: 182, width: resting ? 240 : 192, height: 32)
        resetButton.frame = NSRect(x: 216, y: 182, width: 40, height: 32)
        resetButton.isHidden = resting
        toggleButton.nextKeyView = resting ? toggleButton : resetButton
        toggleButton.title = state.actionTitle
        toggleButton.setAccessibilityLabel(state.actionTitle)
        toggleButton.image = NSImage(systemSymbolName: resting ? "forward.end.fill" : state.running ? "pause.fill" : "play.fill", accessibilityDescription: nil)
        toggleButton.contentTintColor = state.running && !resting ? palette.text : palette.onAccent
        toggleButton.layer?.backgroundColor = (state.running && !resting ? palette.soft : accent).cgColor
        toggleButton.layer?.borderColor = (state.running && !resting ? palette.line : accent).cgColor
        resetButton.contentTintColor = palette.muted
        resetButton.layer?.backgroundColor = palette.soft.cgColor
        resetButton.layer?.borderColor = palette.line.cgColor
        toggleButton.isEnabled = !busy
        resetButton.isEnabled = state.hasSession && !busy
        resetButton.alphaValue = resetButton.isEnabled ? 1 : 0.4
    }
}
