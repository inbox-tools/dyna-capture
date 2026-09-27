import AppKit

// MARK: - 入力ウィンドウ

/// ふだんメニューバーにいるアプリでも、キー入力を受け取れるようにする
final class CaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class CaptureController: NSWindowController, NSTextViewDelegate {
    private let textView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "⌘↩ で送信　esc で閉じる")
    private let taskCheck = NSButton(checkboxWithTitle: "タスクとして送る", target: nil, action: nil)
    private let placeholder = NSTextField(labelWithString: "思いついたことを書く\n　改行すると子項目になります（行頭にスペースを足すともう1段深く）")
    private let sendButton = NSButton(title: "Dynalist へ送る", target: nil, action: nil)
    private var sending = false

    init() {
        let window = CaptureWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 360),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Dyna Capture"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.hidesOnDeactivate = false
        // どのデスクトップ（スペース）にいてもその場に出す
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let window = window else { return }
        let content = NSView()
        window.contentView = content

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        textView.delegate = self
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView

        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor

        taskCheck.font = NSFont.systemFont(ofSize: 12)
        sendButton.bezelStyle = .rounded
        sendButton.keyEquivalent = "\r"
        // ⌘↩ を送信に。修飾なしの ↩ はテキスト欄に渡して改行させる
        sendButton.keyEquivalentModifierMask = [.command]
        sendButton.target = self
        sendButton.action = #selector(sendTapped)

        placeholder.font = NSFont.systemFont(ofSize: 14)
        placeholder.textColor = .tertiaryLabelColor
        placeholder.maximumNumberOfLines = 3
        placeholder.lineBreakMode = .byWordWrapping

        for v in [scroll, placeholder, statusLabel, hintLabel, taskCheck, sendButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 36),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: taskCheck.topAnchor, constant: -12),

            taskCheck.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            taskCheck.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -46),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            statusLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: sendButton.leadingAnchor, constant: -8),

            hintLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            hintLabel.centerYAnchor.constraint(equalTo: taskCheck.centerYAnchor),
            hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: taskCheck.trailingAnchor, constant: 16),

            placeholder.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 12),
            placeholder.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 13),
            placeholder.trailingAnchor.constraint(lessThanOrEqualTo: scroll.trailingAnchor, constant: -12),

            sendButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            sendButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    // MARK: 表示

    func show() {
        guard let window = window else { return }
        // いま作業している画面＝マウスのある画面に出す
        let mouse = NSEvent.mouseLocation
        let target = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let screen = target {
            let v = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: v.midX - size.width / 2,
                                          y: v.midY - size.height / 2 + v.height * 0.12))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        placeholder.isHidden = !textView.string.isEmpty
        setStatus(Dynalist.token() == nil
                  ? "キーチェーンに dynalist-api のトークンがありません"
                  : "", isError: Dynalist.token() == nil)
    }

    func toggle() {
        if window?.isVisible == true && NSApp.isActive { window?.orderOut(nil) } else { show() }
    }

    private func setStatus(_ text: String, isError: Bool = false) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    // MARK: キー操作

    func textDidChange(_ note: Notification) {
        placeholder.isHidden = !textView.string.isEmpty
    }

    func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            window?.orderOut(nil)
            return true
        }
        // ⌘↩ で送信。ふつうの ↩ は改行のまま（複数行を書くため）
        if selector == #selector(NSResponder.insertNewline(_:)),
           NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            sendTapped()
            return true
        }
        return false
    }

    // MARK: 送信

    @objc private func sendTapped() {
        guard !sending else { return }
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { setStatus("送る内容がありません", isError: true); return }

        sending = true
        sendButton.isEnabled = false
        setStatus("送っています…")
        let checkbox = taskCheck.state == .on

        DispatchQueue.global(qos: .userInitiated).async {
            var result: Dynalist.SendResult?
            var failure: Error?
            do { result = try Dynalist.send(text: text, note: "", checkbox: checkbox) }
            catch { failure = error }

            DispatchQueue.main.async {
                self.sending = false
                self.sendButton.isEnabled = true
                if let r = result {
                    let suffix = r.childCount > 0 ? "（子 \(r.childCount) 件）" : ""
                    self.setStatus("送りました ✓ \(suffix)")
                    self.textView.string = ""
                    self.placeholder.isHidden = false
                    self.taskCheck.state = .off
                    // 送れたことが見えるよう少しだけ残してから閉じる
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        if self.textView.string.isEmpty { self.window?.orderOut(nil) }
                    }
                } else {
                    // 失敗したら本文は消さない。書いたものを失わせない
                    self.setStatus(failure?.localizedDescription ?? "送信に失敗しました", isError: true)
                }
            }
        }
    }
}

// MARK: - アプリ本体

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controller: CaptureController!

    private let agentPath = NSString(string: "~/Library/LaunchAgents/io.github.inbox-tools.dynacapture.plist")
        .expandingTildeInPath

    func applicationDidFinishLaunching(_ note: Notification) {
        controller = CaptureController()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "tray.and.arrow.down",
                                   accessibilityDescription: "Dyna Capture")
            button.image?.isTemplate = true
        }

        buildMenu()

        // 初回起動のときだけ出す。以後はホットキーかメニューバーから
        let key = "DynaCaptureDidIntroduce"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            controller.show()
        }
    }

    /// すでに常駐している状態で open -a されたとき（Alfred からの呼び出し）に窓を出す
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        controller.show()
        return true
    }

    // MARK: メニュー

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "メモを書く",
                     action: #selector(openCapture), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let login = NSMenuItem(title: "ログイン時に起動",
                               action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = FileManager.default.fileExists(atPath: agentPath) ? .on : .off
        menu.addItem(login)
        menu.addItem(withTitle: "Dynalist を開く",
                     action: #selector(openDynalist), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Dyna Capture を終了",
                     action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc private func openCapture() { controller.show() }
    @objc private func openDynalist() { NSWorkspace.shared.open(URL(string: "https://dynalist.io/")!) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLoginItem() {
        let fm = FileManager.default
        if fm.fileExists(atPath: agentPath) {
            try? fm.removeItem(atPath: agentPath)
        } else {
            let exe = Bundle.main.bundlePath
            let plist: [String: Any] = [
                "Label": "io.github.inbox-tools.dynacapture",
                "ProgramArguments": ["/usr/bin/open", "-a", exe],
                "RunAtLoad": true,
            ]
            try? fm.createDirectory(atPath: (agentPath as NSString).deletingLastPathComponent,
                                    withIntermediateDirectories: true)
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                             format: .xml, options: 0) {
                try? data.write(to: URL(fileURLWithPath: agentPath))
            }
        }
        buildMenu()
    }

}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // Dock には出さずメニューバーに常駐
app.run()
