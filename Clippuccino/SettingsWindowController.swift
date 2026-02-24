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
    private let labelColumnWidth: CGFloat = 170
    private let numericFieldWidth: CGFloat = 86

    init(settings: SettingsModel) {
        self.settings = settings

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
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

        let maxItemsLabel = makeSettingLabel("Max items in history")

        maxItemsField.target = self
        maxItemsField.action = #selector(maxItemsFieldChanged)
        maxItemsField.alignment = .right

        maxItemsStepper.minValue = Double(SettingsModel.minMaxItems)
        maxItemsStepper.maxValue = Double(SettingsModel.maxMaxItems)
        maxItemsStepper.increment = 1
        maxItemsStepper.target = self
        maxItemsStepper.action = #selector(maxItemsStepperChanged)

        let maxItemsControls = NSStackView(views: [maxItemsField, maxItemsStepper])
        maxItemsControls.orientation = .horizontal
        maxItemsControls.spacing = 8
        maxItemsControls.alignment = .centerY
        let maxItemsRow = makeSettingRow(labelView: maxItemsLabel, controlView: maxItemsControls)

        let ttlLabel = makeSettingLabel("Auto-erase TTL (seconds)")

        ttlField.target = self
        ttlField.action = #selector(ttlFieldChanged)
        ttlField.alignment = .right

        ttlStepper.minValue = Double(SettingsModel.minTTLSeconds)
        ttlStepper.maxValue = Double(SettingsModel.maxTTLSeconds)
        ttlStepper.increment = 1
        ttlStepper.target = self
        ttlStepper.action = #selector(ttlStepperChanged)

        let ttlControls = NSStackView(views: [ttlField, ttlStepper])
        ttlControls.orientation = .horizontal
        ttlControls.spacing = 8
        ttlControls.alignment = .centerY
        let ttlRow = makeSettingRow(labelView: ttlLabel, controlView: ttlControls)

        let startOnLoginLabel = makeSettingLabel("Start on login")
        startOnLoginCheckbox.title = "Enabled"
        startOnLoginCheckbox.target = self
        startOnLoginCheckbox.action = #selector(startOnLoginChanged)
        let startOnLoginRow = makeSettingRow(labelView: startOnLoginLabel, controlView: startOnLoginCheckbox)

        let hotkeyLabel = makeSettingLabel("Open History hotkey")
        hotkeyRecorderView = HotkeyRecorderView(hotkey: settings.hotkey)
        hotkeyRecorderView.onHotkeyRecorded = { [weak self] newHotkey in
            self?.handleHotkeyUpdate(newHotkey)
        }
        let hotkeyRow = makeSettingRow(labelView: hotkeyLabel, controlView: hotkeyRecorderView)

        let eraseLabel = makeSettingLabel("History")

        eraseButton.bezelStyle = .rounded
        eraseButton.target = self
        eraseButton.action = #selector(eraseAllHistoryTapped)
        let eraseRow = makeSettingRow(labelView: eraseLabel, controlView: eraseButton)

        let separator = NSBox()
        separator.boxType = .separator

        let rootStack = NSStackView(views: [maxItemsRow, ttlRow, startOnLoginRow, hotkeyRow, separator, eraseRow])
        rootStack.orientation = .vertical
        rootStack.spacing = 12
        rootStack.alignment = .leading
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
            maxItemsField.widthAnchor.constraint(equalToConstant: numericFieldWidth),
            ttlField.widthAnchor.constraint(equalToConstant: numericFieldWidth),
            separator.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])
    }

    private func makeSettingLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: labelColumnWidth).isActive = true
        return label
    }

    private func makeSettingRow(labelView: NSView, controlView: NSView) -> NSStackView {
        controlView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        controlView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [labelView, controlView])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 460).isActive = true
        return row
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
