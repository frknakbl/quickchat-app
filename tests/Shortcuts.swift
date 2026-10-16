
// Exercise AppKit's menu-to-responder dispatch without sending keys to other apps.
extension AppDelegate {
    func prepareShortcutCheck() { setupMainMenu() }
}

let testApplication = NSApplication.shared
testApplication.setActivationPolicy(.prohibited)
let testDelegate = AppDelegate()
testDelegate.prepareShortcutCheck()

let pasteboard = NSPasteboard.general
let savedClipboard = (pasteboard.pasteboardItems ?? []).map { item in
    item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
}
defer {
    pasteboard.clearContents()
    let items = savedClipboard.map { values in
        let item = NSPasteboardItem()
        for (type, data) in values { item.setData(data, forType: type) }
        return item
    }
    if !items.isEmpty { pasteboard.writeObjects(items) }
}

let editor = NSTextView(frame: .zero)
editor.isEditable = true
editor.isRichText = false
testApplication.nextResponder = editor

func command(_ key: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = .command) -> Bool {
    guard let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers,
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
        context: nil, characters: key, charactersIgnoringModifiers: key,
        isARepeat: false, keyCode: keyCode
    ) else { fatalError("Klavye olayı oluşturulamadı") }
    return testApplication.mainMenu?.performKeyEquivalent(with: event) ?? false
}

editor.string = "QuickChat kısayol kontrolü"
editor.setSelectedRange(NSRange(location: 0, length: 0))
assert(command("a", keyCode: UInt16(kVK_ANSI_A)), "⌘A yakalanmadı")
assert(editor.selectedRange().length == (editor.string as NSString).length, "⌘A metni seçmedi")

assert(command("c", keyCode: UInt16(kVK_ANSI_C)), "⌘C yakalanmadı")
assert(pasteboard.string(forType: .string) == editor.string, "⌘C panoya kopyalamadı")

editor.string = ""
editor.setSelectedRange(NSRange(location: 0, length: 0))
assert(command("v", keyCode: UInt16(kVK_ANSI_V)), "⌘V yakalanmadı")
assert(editor.string == "QuickChat kısayol kontrolü", "⌘V metni yapıştırmadı")

editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
assert(command("x", keyCode: UInt16(kVK_ANSI_X)), "⌘X yakalanmadı")
assert(editor.string.isEmpty, "⌘X metni kesmedi")
assert(pasteboard.string(forType: .string) == "QuickChat kısayol kontrolü", "⌘X panoyu güncellemedi")

assert(!command("v", keyCode: UInt16(kVK_ANSI_V), modifiers: [.command, .control]), "⌃⌘V yanlışlıkla yakalandı")
assert(!command("v", keyCode: UInt16(kVK_ANSI_V), modifiers: []), "Normal V tuşu yakalandı")
print("PASS: ⌘A, ⌘C, ⌘V, ⌘X AppKit komut zinciri üzerinden çalışıyor; farklı tuş birleşimleri korunuyor.")
