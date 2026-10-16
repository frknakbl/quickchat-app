// Drive AppKit events while waiting, as a running application does.
func pumpEvents(until deadline: Date) {
    while Date() < deadline {
        if let event = NSApp.nextEvent(matching: .any, until: deadline, inMode: .default, dequeue: true) {
            NSApp.sendEvent(event)
        }
    }
}

extension AppDelegate {
    static var observerForCheck: String { responseObserverScript }

    func checkPanelSizing() {
        buildPanel()
        compactHeight = 420
        setPanelHeight(1)
        assert(panel.frame.height == panel.minSize.height)
        setPanelHeight(100_000)
        let visible = panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        assert(panel.frame.height <= min(panel.maxSize.height, visible.height))
        assert(panel.frame.minY >= visible.minY && panel.frame.maxY <= visible.maxY)
        let capped = panel.frame
        setPanelHeight(100_000)
        assert(panel.frame == capped, "Üst sınırda pencere büyümeye devam etti")
        compactHeight = 700
        beginNewConversation()
        assert(panel.frame.height == 420, "Yeni sohbet başlangıç boyutuna dönmedi")
        assert(compactHeight == 420, "Kaydedilmiş büyük boyut yeni sohbetin kompakt boyutunu ezdi")
        assert(submittedGeneration == nil)

        panel.setFrame(NSRect(x: visible.midX - 300, y: visible.minY + 40, width: 600, height: 420), display: true)
        panel.orderFront(nil)
        let bottom = panel.frame.minY
        let top = panel.frame.maxY
        let chrome = panel.frame.height - webView.bounds.height
        submittedGeneration = conversationGeneration
        expandForResponse(contentHeight: 600 - chrome)
        let firstAnimation = resizeAnimation
        expandForResponse(contentHeight: 700 - chrome)
        expandForResponse(contentHeight: 650 - chrome)
        assert(resizeAnimation === firstAnimation, "Akıştaki her ölçüm animasyonu yeniden başlattı")
        var sampledHeights: [CGFloat] = []
        let deadline = Date().addingTimeInterval(3)
        while resizeAnimation != nil && Date() < deadline {
            pumpEvents(until: Date().addingTimeInterval(0.01))
            sampledHeights.append(panel.frame.height)
            assert(abs(panel.frame.minY - bottom) < 1, "Büyürken alt kenar hareket etti")
        }
        assert(resizeAnimation == nil && abs(panel.frame.height - 700) < 1,
               "Son yükseklik hedefine ulaşılamadı: frame=\(panel.frame), visible=\(visible), animating=\(String(describing: resizeAnimation?.isAnimating)), progress=\(String(describing: resizeAnimation?.currentProgress)), pending=\(String(describing: pendingResponseHeight))")
        assert(panel.frame.maxY > top, "Üst kenar yukarı açılmadı")
        assert(zip(sampledHeights, sampledHeights.dropFirst()).allSatisfy { $0 <= $1 + 1 }, "Akış sırasında pencere küçüldü")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            assert(sampledHeights.filter { $0 > 421 && $0 < 699 }.count >= 3, "Animasyonda ara kareler yok")
        }

        expandForResponse(contentHeight: 10000)
        waitFor("Animasyon üst sınırda tamamlanmadı") { self.resizeAnimation == nil }
        assert(abs(panel.frame.minY - bottom) < 1)
        assert(panel.frame.height <= min(panel.maxSize.height, visible.maxY - bottom))
        let expanded = panel.frame
        expandForResponse(contentHeight: 20000)
        assert(panel.frame == expanded && resizeAnimation == nil, "Sınırda gereksiz animasyon başladı")

        beginNewConversation()
        submittedGeneration = conversationGeneration
        expandForResponse(contentHeight: 700 - chrome)
        expandForResponse(contentHeight: 800 - chrome)
        beginNewConversation()
        pumpEvents(until: Date().addingTimeInterval(0.4))
        assert(panel.frame.height == 420 && resizeAnimation == nil && pendingResponseHeight == nil, "Eski animasyon yeni sohbeti büyüttü")

        submittedGeneration = conversationGeneration
        expandForResponse(contentHeight: 700 - chrome)
        windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification, object: panel))
        assert(resizeAnimation == nil && submittedGeneration == nil, "Elle boyutlandırma animasyonu durdurmadı")

        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: visible.maxY - 500))
        submittedGeneration = conversationGeneration
        expandForResponse(contentHeight: 10000)
        waitFor("Ekranın üst sınırındaki animasyon tamamlanmadı") { self.resizeAnimation == nil }
        assert(abs(panel.frame.height - 500) < 1 && abs(panel.frame.maxY - visible.maxY) < 1, "Ekranın tepesinde aşağı doğru büyüdü")

        beginNewConversation()
        submittedGeneration = conversationGeneration
        expandForResponse(contentHeight: 10000)
        panel.hide()
        pumpEvents(until: Date().addingTimeInterval(0.3))
        assert(resizeAnimation == nil && pendingResponseHeight == nil, "Gizlenen pencerenin animasyonu devam etti")
        panel.orderOut(nil)
    }
}

final class ResponseProbe: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var loaded = false
    var events: [String] = []
    var heights: [Double] = []
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let event = message.body as? String { events.append(event) }
        if let payload = message.body as? [String: Any], let height = payload["height"] as? Double { heights.append(height) }
    }
}

func waitFor(_ description: String, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(8)
    while !condition() && Date() < deadline {
        pumpEvents(until: Date().addingTimeInterval(0.02))
    }
    assert(condition(), description)
}

let behaviorApp = NSApplication.shared
behaviorApp.setActivationPolicy(.prohibited)
behaviorApp.finishLaunching()
AppDelegate().checkPanelSizing()

let probe = ResponseProbe()
let config = WKWebViewConfiguration()
config.userContentController.add(probe, name: "quickChat")
config.userContentController.addUserScript(WKUserScript(source: AppDelegate.observerForCheck, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
let fixture = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 420), configuration: config)
fixture.navigationDelegate = probe
fixture.loadHTMLString("""
<html><head><style>body{margin:0}p{margin:8px}h4{font-size:12px}#reply{white-space:pre-wrap;line-height:20px}</style>
<script>window.requestAnimationFrame = callback => setTimeout(callback, 0);</script></head><body>
<div id="messages"></div><div contenteditable="true" role="textbox">test</div>
<button aria-label="Gönder" id="send">Gönder</button><button id="new">Yeni sohbet ⇧⌘O</button>
</body></html>
""", baseURL: URL(string: "https://chatgpt.com/"))
waitFor("Yerel WebKit test sayfası yüklenmedi") { probe.loaded }

func evaluate(_ script: String) {
    var complete = false
    fixture.evaluateJavaScript(script) { _, error in
        assert(error == nil, String(describing: error))
        complete = true
    }
    waitFor("Test JavaScript'i tamamlanmadı") { complete }
}

evaluate("document.getElementById('send').click()")
waitFor("Güncel contenteditable alanı gönderim olarak algılanmadı") { probe.events.contains("userSubmitted") }
evaluate("""
document.getElementById('messages').innerHTML = '<section><h4>Şunu söylediniz:</h4><p>Test</p></section><section><h4>ChatGPT dedi:</h4><div class="markdown" id="reply">Kısa yanıt</div></section>';
""")
waitFor("Güncel başlık yapısındaki yanıt ölçülemedi") { !probe.heights.isEmpty }
var previousHeight = probe.heights.last!
for lines in [10, 30, 70] {
    let previousCount = probe.heights.count
    evaluate("document.getElementById('reply').textContent = Array(\(lines)).fill('Yanıt satırı').join(String.fromCharCode(10))")
    waitFor("Yanıt büyümesi bildirilmedi") { probe.heights.count > previousCount }
    assert(probe.heights.last! > previousHeight, "Yanıt uzadıkça ölçülen yükseklik artmadı")
    previousHeight = probe.heights.last!
}
evaluate("document.getElementById('new').click()")
waitFor("Yeni sohbet sinyali alınmadı") { probe.events.contains("newChatStarted") }
let stoppedCount = probe.heights.count
evaluate("document.getElementById('reply').textContent = 'Eski yanıt'")
pumpEvents(until: Date().addingTimeInterval(0.2))
assert(probe.heights.count == stoppedCount, "Yeni sohbetten sonra eski yanıt pencereyi etkiledi")

let submissions = probe.events.filter { $0 == "userSubmitted" }.count
evaluate("document.querySelector('[contenteditable]').dispatchEvent(new KeyboardEvent('keydown', {key:'Enter',shiftKey:true,bubbles:true}))")
assert(probe.events.filter { $0 == "userSubmitted" }.count == submissions, "Shift+Enter mesaj gönderimi sayıldı")
evaluate("document.querySelector('[contenteditable]').dispatchEvent(new KeyboardEvent('keydown', {key:'Enter',bubbles:true}))")
waitFor("Enter ile gönderim algılanmadı") { probe.events.filter { $0 == "userSubmitted" }.count == submissions + 1 }

print("PASS: WebKit içerik ölçümü ve gönderim; animasyonda ara kareler, sabit alt kenar, yukarı büyüme, birleştirilen hedefler, ekran sınırı, yeni sohbet/elle boyutlandırma/gizleme iptali.")
