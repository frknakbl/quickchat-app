import Cocoa
import WebKit
import Carbon

private let chatHomeURL = URL(string: "https://chatgpt.com/")!
private let resetInterval: TimeInterval = 5 * 60
private let defaultCompactHeight: CGFloat = 420
private let minimumPanelHeight: CGFloat = 320
private let compactHeightDefaultsKey = "QuickChatCompactHeight"
final class FloatingPanel: NSPanel {
    var beforeHide: (() -> Void)?
    var suppressAutoHide = false

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .windowBackgroundColor
        hasShadow = true
        isReleasedWhenClosed = false
        setFrameAutosaveName("QuickChatFloatingFrameV3")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func hide() {
        beforeHide?()
        orderOut(nil)
    }

    override func resignKey() {
        super.resignKey()
        if !suppressAutoHide { hide() }
    }

    override func cancelOperation(_ sender: Any?) {
        hide()
    }
}

final class ChatWebView: WKWebView {
    var onNewChat: (() -> Void)?
    var onOpenInApp: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command else { return super.performKeyEquivalent(with: event) }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "n":
            onNewChat?()
            return true
        case "o":
            onOpenInApp?()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    func applyWebCleanup() {
        let css = """
        div:has(> button[aria-label="Öneriyi kapat"]),
        div:has(> button[aria-label="Dismiss suggestion"]),
        li:has(> button[aria-label="Öneriyi kapat"]),
        li:has(> button[aria-label="Dismiss suggestion"]) {
            display: none !important;
        }
        """

        let script = """
        (() => {
          let style = document.getElementById('quickchat-cleanup-style');
          if (!style) {
            style = document.createElement('style');
            style.id = 'quickchat-cleanup-style';
            document.head.appendChild(style);
          }
          style.textContent = \(String(reflecting: css));
        })();
        """
        evaluateJavaScript(script, completionHandler: nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate, WKScriptMessageHandler, NSAnimationDelegate {
    private var panel: FloatingPanel!
    private var webView: ChatWebView!
    private var statusItem: NSStatusItem!
    private var hotKeyRef: EventHotKeyRef?
    private var eventMonitor: Any?
    private var lastActivityAt = Date()
    private var titlebarAccessory: NSTitlebarAccessoryViewController?
    private var compactHeight = defaultCompactHeight
    private var programmaticResize = false
    private var conversationGeneration = 0
    private var submittedGeneration: Int?
    private var resizeAnimation: NSViewAnimation?
    private var pendingResponseHeight: CGFloat?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        buildPanel()
        setupStatusItem()
        registerGlobalHotKey()
        monitorActivity()
        startNewChat()
        showPanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopResponseExpansion()
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "quickChat")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    private func buildPanel() {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(
            width: min(820, visible.width - 48),
            height: min(defaultCompactHeight, visible.height - 72)
        )
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 60
        )

        panel = FloatingPanel(contentRect: NSRect(origin: origin, size: size))
        panel.delegate = self
        panel.beforeHide = { [weak self] in
            self?.lastActivityAt = Date()
            self?.stopResponseExpansion()
        }
        panel.minSize = NSSize(width: 520, height: minimumPanelHeight)
        panel.maxSize = NSSize(
            width: min(1100, visible.width),
            height: min(820, visible.height)
        )
        let savedHeight = UserDefaults.standard.double(forKey: compactHeightDefaultsKey)
        compactHeight = CGFloat(savedHeight > 0 ? savedHeight : Double(defaultCompactHeight))
        compactHeight = min(max(compactHeight, panel.minSize.height), panel.maxSize.height)
        setPanelHeight(compactHeight)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = container

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(self, name: "quickChat")
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.responseObserverScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        webView = ChatWebView(frame: .zero, configuration: configuration)
        webView.pageZoom = 0.8
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.onNewChat = { [weak self] in self?.newChat() }
        webView.onOpenInApp = { [weak self] in self?.openInChatGPT() }

        let controls = NSStackView(views: [
            makeButton(symbol: "square.and.pencil", toolTip: "Yeni sohbet (⌘N)", action: #selector(newChat)),
            makeButton(symbol: "arrow.up.forward.app", toolTip: "ChatGPT uygulamasını aç (⌘O)", action: #selector(openInChatGPT))
        ])
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.orientation = .horizontal
        controls.spacing = 2

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 58, height: 28))
        accessoryView.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: accessoryView.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: accessoryView.trailingAnchor),
            controls.centerYAnchor.constraint(equalTo: accessoryView.centerYAnchor)
        ])

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .left
        accessory.view = accessoryView
        panel.addTitlebarAccessoryViewController(accessory)
        titlebarAccessory = accessory

        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    private func makeButton(symbol: String, toolTip: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)!, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.toolTip = toolTip
        button.contentTintColor = .secondaryLabelColor
        button.imagePosition = .imageOnly
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func setupMainMenu() {
        let menu = NSMenu()
        let appItem = menu.addItem(withTitle: "QuickChat", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "QuickChat")
        let quit = appMenu.addItem(withTitle: "QuickChat’ten Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appItem.submenu = appMenu

        let editItem = menu.addItem(withTitle: "Düzenle", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Düzenle")
        editItem.submenu = editMenu

        editMenu.addItem(withTitle: "Geri Al", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Yinele", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Kes", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = menu
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "circle", accessibilityDescription: "QuickChat")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Göster / Gizle (⌥Space)", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Yeni sohbet (⌘N)", action: #selector(newChat), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "ChatGPT uygulamasını aç (⌘O)", action: #selector(openInChatGPT), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Çıkış", action: #selector(quitApp), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private func monitorActivity() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            guard let self else { return event }
            if self.panel.isVisible {
                self.lastActivityAt = Date()
                if event.type == .keyDown,
                   event.keyCode == UInt16(kVK_Escape),
                   event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                    self.panel.hide()
                    return nil
                }
            }
            return event
        }
    }

    private func registerGlobalHotKey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x51434854), id: 1)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.togglePanel()
            }
            return noErr
        }, 1, &eventType, nil, nil)

        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            statusItem.button?.toolTip = "Option+Space başka bir uygulama tarafından kullanılıyor"
        }
    }

    @objc private func togglePanel() {
        panel.isVisible ? panel.hide() : showPanel()
    }

    private func showPanel() {
        if Date().timeIntervalSince(lastActivityAt) >= resetInterval {
            startNewChat()
        }
        lastActivityAt = Date()
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        webView.applyWebCleanup()
    }

    @objc private func newChat() {
        startNewChat()
        showPanel()
    }

    private func startNewChat() {
        beginNewConversation()
        lastActivityAt = Date()
        webView.load(URLRequest(url: chatHomeURL, cachePolicy: .reloadRevalidatingCacheData))
    }

    @objc private func openInChatGPT() {
        let appURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            NSSound.beep()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if error != nil { NSSound.beep() }
        }
    }

    private func expandForResponse(contentHeight: CGFloat) {
        guard panel.isVisible, submittedGeneration == conversationGeneration else { return }
        let chromeHeight = panel.frame.height - webView.bounds.height
        let visible = panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let availableHeight = visible.maxY - max(visible.minY, panel.frame.minY)
        let targetHeight = min(max(compactHeight, contentHeight + chromeHeight), min(panel.maxSize.height, availableHeight))
        guard targetHeight > panel.frame.height + 1 else { return }
        pendingResponseHeight = max(pendingResponseHeight ?? 0, targetHeight)
        animateResponseExpansion()
    }

    private func animateResponseExpansion() {
        guard resizeAnimation == nil, let height = pendingResponseHeight else { return }
        pendingResponseHeight = nil
        guard height > panel.frame.height + 1 else { return }
        setPanelHeight(height, animated: true)
    }

    private func stopResponseExpansion() {
        resizeAnimation?.delegate = nil
        resizeAnimation?.stop()
        resizeAnimation = nil
        pendingResponseHeight = nil
        programmaticResize = false
        panel?.suppressAutoHide = false
    }

    func animationDidEnd(_ animation: NSAnimation) {
        guard animation === resizeAnimation else { return }
        resizeAnimation = nil
        programmaticResize = false
        panel.suppressAutoHide = false
        animateResponseExpansion()
    }

    private func beginNewConversation() {
        conversationGeneration += 1
        submittedGeneration = nil
        resetPanelHeight()
    }

    private func resetPanelHeight() {
        compactHeight = min(max(defaultCompactHeight, panel.minSize.height), panel.maxSize.height)
        UserDefaults.standard.set(Double(compactHeight), forKey: compactHeightDefaultsKey)
        setPanelHeight(compactHeight)
    }

    private func setPanelHeight(_ requestedHeight: CGFloat, animated: Bool = false) {
        guard panel != nil else { return }
        if !animated { stopResponseExpansion() }
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        let targetHeight = min(max(requestedHeight, panel.minSize.height), min(panel.maxSize.height, visible.height))
        var frame = panel.frame
        guard abs(frame.height - targetHeight) > 0.5 else { return }
        frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - targetHeight))
        frame.size.height = targetHeight
        panel.suppressAutoHide = true
        programmaticResize = true
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = NSViewAnimation(viewAnimations: [[
                .target: panel!,
                .startFrame: NSValue(rect: panel.frame),
                .endFrame: NSValue(rect: frame)
            ]])
            animation.duration = 0.18
            animation.animationCurve = .easeInOut
            animation.animationBlockingMode = .nonblocking
            animation.frameRate = 60
            animation.delegate = self
            resizeAnimation = animation
            animation.start()
        } else {
            panel.setFrame(frame, display: true)
            programmaticResize = false
            panel.suppressAutoHide = false
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "quickChat",
              message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == "https",
              message.frameInfo.securityOrigin.host == "chatgpt.com" else { return }

        if let payload = message.body as? [String: Any],
           payload["type"] as? String == "responseHeight",
           let height = payload["height"] as? Double,
           height.isFinite, height > 0, height < 100_000 {
            expandForResponse(contentHeight: CGFloat(height) * webView.pageZoom)
            return
        }

        guard let event = message.body as? String else { return }

        switch event {
        case "userSubmitted":
            submittedGeneration = conversationGeneration
        case "newChatStarted":
            beginNewConversation()
        default:
            return
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        panel.hide()
        return false
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === panel,
              !programmaticResize else { return }
        compactHeight = min(max(window.frame.height, panel.minSize.height), panel.maxSize.height)
        UserDefaults.standard.set(Double(compactHeight), forKey: compactHeightDefaultsKey)
        submittedGeneration = nil
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        stopResponseExpansion()
        submittedGeneration = nil
    }

    func windowWillMove(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        stopResponseExpansion()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        (webView as? ChatWebView)?.applyWebCleanup()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if navigationAction.navigationType == .linkActivated,
           let host = url.host?.lowercased(),
           !isAllowedHost(host) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if let host = url.host?.lowercased(), isAllowedHost(host) {
            webView.load(URLRequest(url: url))
        } else {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    private func isAllowedHost(_ host: String) -> Bool {
        let allowed = [
            "chatgpt.com", "openai.com", "auth.openai.com", "auth0.openai.com",
            "accounts.google.com", "appleid.apple.com", "login.microsoftonline.com"
        ]
        return allowed.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private static let responseObserverScript = """
    (() => {
      window.__quickChatResponseObserver?.disconnect();
      window.__quickChatResponseResizeObserver?.disconnect();

      const notify = value => window.webkit.messageHandlers.quickChat.postMessage(value);
      const composerSelector = '#prompt-textarea, textarea, [contenteditable="true"][role="textbox"], [contenteditable="true"]';
      const composer = () => document.querySelector(composerSelector);
      const messageNodes = role => {
        const tagged = Array.from(document.querySelectorAll('[data-message-author-role="' + role + '"]'));
        if (tagged.length) return tagged;
        const labels = role === 'assistant'
          ? ['ChatGPT dedi:', 'ChatGPT said:']
          : ['Şunu söylediniz:', 'You said:'];
        return Array.from(document.querySelectorAll('h1, h2, h3, h4, h5, h6'))
          .filter(heading => labels.includes(heading.textContent.trim()))
          .map(heading => heading.closest('article, [role="article"]') || heading.parentElement);
      };

      let knownAssistants = messageNodes('assistant').length;
      let submissionActive = false;
      let observedResponse = null;
      let lastHeight = 0;
      let scanQueued = false;

      const scheduleScan = () => {
        if (scanQueued) return;
        scanQueued = true;
        requestAnimationFrame(() => { scanQueued = false; scan(); });
      };
      const responseResize = new ResizeObserver(scheduleScan);
      window.__quickChatResponseResizeObserver = responseResize;

      const contentRect = element => {
        const content = element.querySelector('.markdown, .prose, [data-message-content]') || element;
        const range = document.createRange();
        range.selectNodeContents(content);
        return range.getBoundingClientRect();
      };

      const scan = () => {
        if (!submissionActive) return;
        const assistants = messageNodes('assistant');
        if (assistants.length <= knownAssistants) return;
        const response = assistants[assistants.length - 1];
        if (!response || !response.textContent.trim()) return;
        if (response !== observedResponse) {
          observedResponse = response;
          responseResize.disconnect();
          responseResize.observe(response);
        }
        const users = messageNodes('user');
        const user = users[users.length - 1];
        const replyRect = contentRect(response);
        const userRect = user ? contentRect(user) : replyRect;
        const bodyHeight = Math.max(replyRect.height, replyRect.bottom - userRect.top);
        const composerHeight = composer()?.getBoundingClientRect().height || 48;
        const height = Math.ceil(bodyHeight + composerHeight + 128);
        if (Math.abs(height - lastHeight) < 2) return;
        lastHeight = height;
        notify({type: 'responseHeight', height});
      };

      const notifySubmitted = element => {
        if (!element || !String(element.value ?? element.innerText ?? element.textContent ?? '').trim()) return;
        knownAssistants = messageNodes('assistant').length;
        submissionActive = true;
        observedResponse = null;
        lastHeight = 0;
        notify('userSubmitted');
        scheduleScan();
      };

      const resetConversation = () => {
        submissionActive = false;
        observedResponse = null;
        lastHeight = 0;
        responseResize.disconnect();
        notify('newChatStarted');
      };

      document.addEventListener('keydown', event => {
        if (event.key !== 'Enter' || event.shiftKey || event.isComposing) return;
        const editor = event.target.closest?.(composerSelector);
        if (editor) notifySubmitted(editor);
      }, true);

      document.addEventListener('click', event => {
        const control = event.target.closest?.('a, button');
        if (!control) return;
        const text = String(control.textContent ?? '').trim();
        const label = String(control.getAttribute('aria-label') ?? '').trim();
        const title = String(control.getAttribute('title') ?? '').trim();
        if ([text, label, title].some(value => /^(Yeni sohbet|New chat)(\\s|$)/i.test(value))
            || control.matches('a[href="/"], a[href^="/c/"]')) {
          resetConversation();
          return;
        }
        if (control.matches('[data-testid="send-button"]') || /^(send|gönder)/i.test(label)) {
          notifySubmitted(composer());
        }
      }, true);

      window.addEventListener('resize', scheduleScan);
      window.__quickChatResponseObserver = new MutationObserver(scheduleScan);
      window.__quickChatResponseObserver.observe(document.documentElement, {
        childList: true, subtree: true, characterData: true
      });
    })();
    """
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
