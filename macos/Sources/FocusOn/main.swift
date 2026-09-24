import AppKit
import WebKit
import FocusCore

final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    let root: URL
    init(root: URL) { self.root = root.standardizedFileURL }
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.host == "app" else {
            urlSchemeTask.didFailWithError(URLError(.badURL)); return
        }
        let path = url.path == "/" ? "index.html" : String(url.path.dropFirst())
        let file = root.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let types = ["html": "text/html", "js": "text/javascript", "css": "text/css", "svg": "image/svg+xml", "png": "image/png"]
        let response = URLResponse(url: url, mimeType: types[file.pathExtension] ?? "application/octet-stream",
                                   expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response); urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    let manager = FocusSessionManager()
    let eyeDebug = EyeDebugController()
    let monitorDiagnostics = MonitorDiagnosticsController()
    private(set) var menuBar: MenuBarController!
    private var sleepObservers: [NSObjectProtocol] = []
    private var quitting = false
    private var cameraBridgeGeneration = 0
    private var smokeDirectory: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        fputs("Focus On: launching\n", stderr)
        NSApp.setActivationPolicy(.regular)
        if let index = CommandLine.arguments.firstIndex(of: "--smoke-test"), CommandLine.arguments.count > index + 1 {
            smokeDirectory = CommandLine.arguments[index + 1]
        }
        eyeDebug.prepareToStart = { [weak self] completion in
            guard let self else { return }
            self.manager.stop()
            self.emit("focus-native-pause", detail: [:])
            self.manager.camera.stop(completion: completion)
        }
        configureMenu()
        menuBar = MenuBarController(target: self, action: #selector(showWindow))
        menuBar.onAction = { [weak self] action in
            guard let self, !self.quitting else { return }
            if action == "pause" { self.pause(); return }
            if action == "reset" {
                self.cameraBridgeGeneration += 1
                self.eyeDebug.stop()
                self.manager.stop()
                self.menuBar.pause()
            }
            self.emit("focus-native-control", detail: ["action": action])
        }
        let configuration = WKWebViewConfiguration()
        if smokeDirectory != nil { configuration.websiteDataStore = .nonPersistent() }
        configuration.userContentController.add(self, name: "focusOn")
        configuration.userContentController.addUserScript(WKUserScript(source: "window.__FOCUS_NATIVE__ = true;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let root = Bundle.main.resourceURL!.appendingPathComponent("Web")
        configuration.setURLSchemeHandler(BundleSchemeHandler(root: root), forURLScheme: "focuson")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 740),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Focus On · 专注时刻"; window.minSize = NSSize(width: 760, height: 700)
        window.contentView = webView; window.delegate = self; window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("FocusOnMainWindow"); window.center(); window.makeKeyAndOrderFront(nil)
        manager.onStatus = { [weak self] code, message in
            self?.emit("focus-native-status", detail: ["code": code, "message": message])
        }
        manager.onDiagnostics = { [weak self] text in self?.monitorDiagnostics.update(text) }
        manager.onDistraction = { [weak self] id, sessionId, at in
            self?.emit("focus-native-distraction", detail: ["id": id, "sessionId": sessionId, "at": at])
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            sleepObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.pause()
            })
        }
        fputs("Focus On: loading bundled UI\n", stderr)
        webView.load(URLRequest(url: URL(string: "focuson://app/index.html")!))
        NSApp.activate(ignoringOtherApps: true)
    }
    func configureMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 Focus On", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Focus On", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 Focus On", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); bar.addItem(edit); edit.submenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.submenu?.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        let session = NSMenuItem(); bar.addItem(session); session.submenu = NSMenu(title: "专注")
        session.submenu?.addItem(withTitle: "暂停专注", action: #selector(pause), keyEquivalent: "p").target = self
        session.submenu?.addItem(withTitle: "显示 Focus On", action: #selector(showWindow), keyEquivalent: "0").target = self
        session.submenu?.addItem(withTitle: "眼动测试…", action: #selector(showEyeDebug), keyEquivalent: "").target = self
        session.submenu?.addItem(withTitle: "监测诊断…", action: #selector(showMonitorDiagnostics), keyEquivalent: "").target = self
        NSApp.mainMenu = bar
    }
    @objc func showWindow() {
        menuBar.close()
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func minimizeToMenuBar() {
        menuBar.item.isVisible = true
        menuBar.refresh()
        // orderOut keeps the session alive and does not invoke windowShouldClose.
        window.orderOut(nil)
    }
    @objc func showEyeDebug() { eyeDebug.show() }
    @objc func showMonitorDiagnostics() {
        monitorDiagnostics.update(manager.diagnosticText); monitorDiagnostics.show()
    }
    @objc func pause() {
        menuBar.pause()
        cameraBridgeGeneration += 1
        eyeDebug.stop()
        manager.stop()
        emit("focus-native-pause", detail: [:])
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { pause(); return true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateNow }
        quitting = true
        eyeDebug.stop { [weak self] in
            guard let self else { sender.reply(toApplicationShouldTerminate: true); return }
            self.manager.shutdown { [weak self] in
            guard let self else { sender.reply(toApplicationShouldTerminate: true); return }
            var replied = false
            let finish = {
                guard !replied else { return }
                replied = true; sender.reply(toApplicationShouldTerminate: true)
            }
            self.webView.evaluateJavaScript("window.dispatchEvent(new Event('focus-native-pause'))") { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: finish)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: finish)
        }
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { eyeDebug.stop(); manager.stop() }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !quitting, message.frameInfo.isMainFrame, message.frameInfo.request.url?.scheme == "focuson",
              message.frameInfo.request.url?.host == "app",
              let body = message.body as? [String: Any], let command = body["command"] as? String else { return }
        switch command {
        case "theme":
            guard let value = body["theme"] as? String, let theme = PetTheme(rawValue: value) else { return }
            manager.reminder.theme = theme
            menuBar.dark = value == "dark"
        case "sync":
            guard let data = body["schedule"], let json = try? JSONSerialization.data(withJSONObject: data),
                  let schedule = try? JSONDecoder().decode(FocusSchedule.self, from: json) else { manager.stop(); return }
            menuBar.synchronize(schedule, taskTitle: body["taskTitle"] as? String ?? "")
            // Smoke tests never request access to the user's camera.
            if smokeDirectory != nil && schedule.monitoring { return }
            cameraBridgeGeneration += 1
            let token = cameraBridgeGeneration
            if schedule.running && eyeDebug.isRunning {
                eyeDebug.stop { [weak self] in
                    guard let self, !self.quitting, self.cameraBridgeGeneration == token else { return }
                    self.manager.synchronize(schedule)
                }
            } else { manager.synchronize(schedule) }
        case "minimizeToMenuBar": minimizeToMenuBar()
        case "eyeTest": eyeDebug.show()
        case "monitorDiagnostics": showMonitorDiagnostics()
        case "retry": if smokeDirectory == nil { manager.retry() }
        case "calibrate": if smokeDirectory == nil { manager.recalibrate() }
        case "settings":
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
        case "ready": emit("focus-native-status", detail: ["code": "idle", "message": "摄像头仅在专注时开启"])
        default: break
        }
    }
    func emit(_ name: String, detail: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: detail), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent('\(name)', {detail: \(json)}))", completionHandler: nil)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        decisionHandler(url?.scheme == "focuson" && url?.host == "app" ? .allow : .cancel)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        manager.stop(); webView.reload()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        fputs("Focus On: bundled UI loaded\n", stderr)
        if let smokeDirectory {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.runSmokeTest(directory: smokeDirectory) }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
