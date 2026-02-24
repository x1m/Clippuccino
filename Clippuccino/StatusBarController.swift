import AppKit
import Foundation

final class StatusBarController: NSObject {
    var onOpenHistory: ((NSRect?) -> Void)?
    var onTogglePauseCapture: ((Bool) -> Void)?
    var onEraseAllHistory: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem: NSStatusItem
    private let pauseCaptureItem: NSMenuItem
    private let menu = NSMenu()

    private var isPaused: Bool = false {
        didSet {
            pauseCaptureItem.state = isPaused ? .on : .off
        }
    }

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        pauseCaptureItem = NSMenuItem(title: "Pause Capture", action: #selector(togglePauseCapture), keyEquivalent: "")
        super.init()
        configureStatusItem()
    }

    func updatePauseCaptureState(_ paused: Bool) {
        isPaused = paused
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyUpOrDown
            let iconSide = max(18, NSStatusBar.system.thickness - 2)

            if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
               let image = NSImage(contentsOfFile: iconPath) {
                image.isTemplate = false
                image.size = NSSize(width: iconSide, height: iconSide)
                button.image = image
            } else if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "png"),
                      let image = NSImage(contentsOfFile: iconPath) {
                image.isTemplate = false
                image.size = NSSize(width: iconSide, height: iconSide)
                button.image = image
            } else {
                button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clippuccino")
                button.image?.isTemplate = true
            }
            button.toolTip = "Clippuccino"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let openHistoryItem = NSMenuItem(title: "Open History", action: #selector(openHistory), keyEquivalent: "")
        openHistoryItem.target = self
        menu.addItem(openHistoryItem)

        pauseCaptureItem.target = self
        menu.addItem(pauseCaptureItem)

        let eraseItem = NSMenuItem(title: "Erase All History", action: #selector(eraseAllHistory), keyEquivalent: "")
        eraseItem.target = self
        menu.addItem(eraseItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        isPaused = false
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        onOpenHistory?(statusButtonRect(for: sender))
    }

    @objc private func openHistory() {
        onOpenHistory?(statusButtonRect(for: statusItem.button))
    }

    @objc private func togglePauseCapture() {
        isPaused.toggle()
        onTogglePauseCapture?(isPaused)
    }

    @objc private func eraseAllHistory() {
        onEraseAllHistory?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func quitApp() {
        onQuit?()
    }

    private func statusButtonRect(for button: NSStatusBarButton?) -> NSRect? {
        guard let button, let window = button.window else { return nil }
        return window.convertToScreen(button.frame)
    }
}
