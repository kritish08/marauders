import TipKit

struct WhatsThisTip: Tip {
    var title: Text { Text("Ask about anything you see") }
    var message: Text? { Text("Not an AR target? Tap \"What's this?\" and the guide identifies whatever the camera sees.") }
    var image: Image? { Image(systemName: "sparkle.magnifyingglass") }
}

struct TextChatTip: Tip {
    var title: Text { Text("Prefer typing?") }
    var message: Text? { Text("Ask the guide by text for fast, silent answers — even offline on newer iPhones.") }
    var image: Image? { Image(systemName: "keyboard.fill") }
}
