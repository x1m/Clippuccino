import AppKit
import Foundation

final class SettingsWindowController: NSWindowController {
    var onSettingsChanged: ((SettingsModel) -> Void)?
    var onSetStartOnLogin: ((Bool) throws -> Void)?
    var onSetHotkey: ((HotkeyBinding) -> Bool)?
    var onEraseAllHistory: (() -> Void)?

    private var settings: SettingsModel

    private let maxItemsField = NSTextField(frame: .zero)
    private let maxItemsStepper = NSStepper(frame: .zero)

    private let ttlField = NSTextField(frame: .zero)
    private let ttlStepper = NSStepper(frame: .zero)

    private let startOnLoginCheckbox = NSButton(checkboxWithTitle: "Start on login", target: nil, action: nil)
    private var hotkeyRecorderView: HotkeyRecorderView!

    private let eraseButton = NSButton(title: "Erase All History", target: nil, action: nil)

    init(settings: SettingsModel) {
        self.settings = settings

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false

        super.init(window: window)

        buildUI()
        applySettingsToControls()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        window.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func updateSettings(_ settings: SettingsModel) {
        self.settings = settings
        applySettingsToControls()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let maxItemsLabel = NSTextField(labelWithString: "Max items in history")
        maxItemsLabel.setContentHuggingPriority(.required, for: .horizontal)

        maxItemsField.target = self
        maxItemsField.action = #selector(maxItemsFieldChanged)

        maxItemsStepper.minValue = Double(SettingsModel.minMaxItems)
        maxItemsStepper.maxValue = Double(SettingsModel.maxMaxItems)
        maxItemsStepper.increment = 1
        maxItemsStepper.target = self
        maxItemsStepper.action = #selector(maxItemsStepperChanged)

        let maxItemsRow = NSStackView(views: [maxItemsLabel, maxItemsField, maxItemsStepper])
        maxItemsRow.orientation = .horizontal
        maxItemsRow.spacing = 8

        let ttlLabel = NSTextField(labelWithString: "Auto-erase TTL seconds")
        ttlLabel.setContentHuggingPriority(.required, for: .horizontal)

        ttlField.target = self
        ttlField.action = #selector(ttlFieldChanged)

        ttlStepper.minValue = Double(SettingsModel.minTTLSeconds)
        ttlStepper.maxValue = Double(SettingsModel.maxTTLSeconds)
        ttlStepper.increment = 1
        ttlStepper.target = self
        ttlStepper.action = #selector(ttlStepperChanged)

        let ttlRow = NSStackView(views: [ttlLabel, ttlField, ttlStepper])
        ttlRow.orientation = .horizontal
        ttlRow.spacing = 8

        startOnLoginCheckbox.target = self
        startOnLoginCheckbox.action = #selector(startOnLoginChanged)

        let hotkeyLabel = NSTextField(labelWithString: "Open History hotkey")
        hotkeyLabel.setContentHuggingPriority(.required, for: .horizontal)
        hotkeyRecorderView = HotkeyRecorderView(hotkey: settings.hotkey)
        hotkeyRecorderView.onHotkeyRecorded = { [weak self] newHotkey in
            self?.handleHotkeyUpdate(newHotkey)
        }

        let hotkeyRow = NSStackView(views: [hotkeyLabel, hotkeyRecorderView])
        hotkeyRow.orientation = .horizontal
        hotkeyRow.spacing = 8

        eraseButton.bezelStyle = .rounded
        eraseButton.target = self
        eraseButton.action = #selector(eraseAllHistoryTapped)

        let rootStack = NSStackView(views: [maxItemsRow, ttlRow, startOnLoginCheckbox, hotkeyRow, eraseButton])
        rootStack.orientation = .vertical
        rootStack.spacing = 14
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            maxItemsField.widthAnchor.constraint(equalToConstant: 80),
            ttlField.widthAnchor.constraint(equalToConstant: 80)
        ])
    }

    private func applySettingsToControls() {
        maxItemsField.stringValue = String(settings.maxItems)
        maxItemsStepper.integerValue = settings.maxItems

        ttlField.stringValue = String(settings.ttlSeconds)
        ttlStepper.integerValue = settings.ttlSeconds

        startOnLoginCheckbox.state = settings.startOnLogin ? .on : .off
        hotkeyRecorderView.hotkey = settings.hotkey
    }

    @objc private func maxItemsFieldChanged() {
        let value = clamp(
            Int(maxItemsField.stringValue) ?? settings.maxItems,
            min: SettingsModel.minMaxItems,
            max: SettingsModel.maxMaxItems
        )
        settings.maxItems = value
        applySettingsToControls()
        onSettingsChanged?(settings)
    }

    @objc private func maxItemsStepperChanged() {
        settings.maxItems = clamp(maxItemsStepper.integerValue, min: SettingsModel.minMaxItems, max: SettingsModel.maxMaxItems)
        applySettingsToControls()
        onSettingsChanged?(settings)
    }

    @objc private func ttlFieldChanged() {
        let value = clamp(
            Int(ttlField.stringValue) ?? settings.ttlSeconds,
            min: SettingsModel.minTTLSeconds,
            max: SettingsModel.maxTTLSeconds
        )
        settings.ttlSeconds = value
        applySettingsToControls()
        onSettingsChanged?(settings)
    }

    @objc private func ttlStepperChanged() {
        settings.ttlSeconds = clamp(ttlStepper.integerValue, min: SettingsModel.minTTLSeconds, max: SettingsModel.maxTTLSeconds)
        applySettingsToControls()
        onSettingsChanged?(settings)
    }

    @objc private func startOnLoginChanged() {
        let requestedState = startOnLoginCheckbox.state == .on

        do {
            try onSetStartOnLogin?(requestedState)
            settings.startOnLogin = requestedState
            onSettingsChanged?(settings)
        } catch {
            settings.startOnLogin.toggle()
            applySettingsToControls()
            showAlert(
                title: "Couldn’t Update Start on Login",
                message: "The setting could not be changed. Please try again."
            )
        }
    }

    @objc private func eraseAllHistoryTapped() {
        onEraseAllHistory?()
    }

    private func handleHotkeyUpdate(_ newHotkey: HotkeyBinding) {
        let didSet = onSetHotkey?(newHotkey) ?? false
        if didSet {
            settings.hotkey = newHotkey
            onSettingsChanged?(settings)
        } else {
            hotkeyRecorderView.hotkey = settings.hotkey
            showAlert(title: "Couldn’t Set Hotkey", message: "Please choose a different shortcut.")
        }
    }

    private func clamp(_ value: Int, min lowerBound: Int, max upperBound: Int) -> Int {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.beginSheetModal(for: window!)
    }
}
