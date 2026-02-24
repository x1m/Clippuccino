import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum DefaultsKey {
        static let maxItems = "settings.maxItems"
        static let ttlSeconds = "settings.ttlSeconds"
        static let startOnLogin = "settings.startOnLogin"
        static let hotkeyKeyCode = "settings.hotkey.keyCode"
        static let hotkeyModifiers = "settings.hotkey.modifiers"
    }

    private enum StartOnLoginError: Error {
        case statusMismatch
    }

    private var settings: SettingsModel = SettingsModel()

    private var historyManager: HistoryManager!
    private var clipboardWatcher: ClipboardWatcher!
    private var hotKeyManager: HotKeyManager!
    private var statusBarController: StatusBarController!
    private var historyPanelController: HistoryPanelController!
    private var settingsWindowController: SettingsWindowController!
    private var pasteTargetApplication: NSRunningApplication?
    private var lastHistoryToggleTime: Date = .distantPast
    private var hasRequestedAccessibilityPermissionThisLaunch = false

    private var ttlCleanupTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = loadSettings()

        historyManager = HistoryManager(
            maxItems: settings.maxItems,
            ttlSeconds: settings.ttlSeconds,
            maxItemLength: SettingsModel.defaultMaxItemLength
        )
        historyManager.onChange = { [weak self] in
            self?.historyPanelController.reloadDataIfVisible()
        }

        clipboardWatcher = ClipboardWatcher(
            historyManager: historyManager,
            pasteboard: .general,
            pollInterval: SettingsModel.defaultPollInterval
        )

        hotKeyManager = HotKeyManager()
        hotKeyManager.onHotKeyPressed = { [weak self] in
            self?.toggleHistoryPanel(anchorRect: nil)
        }

        statusBarController = StatusBarController()
        historyPanelController = HistoryPanelController(historyManager: historyManager)
        historyPanelController.onSelectItem = { [weak self] text in
            self?.clipboardWatcher.setClipboardFromHistory(text)
            self?.performAutoPaste()
        }
        historyPanelController.onEraseAllHistory = { [weak self] in
            self?.historyManager.eraseAll()
        }
        historyPanelController.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        historyPanelController.onQuit = {
            NSApp.terminate(nil)
        }

        settingsWindowController = SettingsWindowController(settings: settings)

        wireControllers()

        if !hotKeyManager.register(binding: settings.hotkey) {
            settings.hotkey = .default
            _ = hotKeyManager.register(binding: settings.hotkey)
            persistSettings()
        }

        clipboardWatcher.start()
        startTTLCleanupTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardWatcher.stop()
        ttlCleanupTimer?.invalidate()
    }

    private func wireControllers() {
        statusBarController.onOpenHistory = { [weak self] statusRect in
            self?.toggleHistoryPanel(anchorRect: statusRect)
        }

        statusBarController.onTogglePauseCapture = { [weak self] paused in
            self?.clipboardWatcher.isPaused = paused
            self?.statusBarController.updatePauseCaptureState(paused)
        }

        statusBarController.onEraseAllHistory = { [weak self] in
            self?.historyManager.eraseAll()
        }

        statusBarController.onOpenSettings = { [weak self] in
            self?.openSettings()
        }

        statusBarController.onQuit = {
            NSApp.terminate(nil)
        }

        settingsWindowController.onSettingsChanged = { [weak self] newSettings in
            self?.applySettings(newSettings)
        }

        settingsWindowController.onEraseAllHistory = { [weak self] in
            self?.historyManager.eraseAll()
        }

        settingsWindowController.onSetHotkey = { [weak self] binding in
            guard let self else { return false }
            let didRegister = self.hotKeyManager.register(binding: binding)
            if didRegister {
                self.settings.hotkey = binding
                self.persistSettings()
            }
            return didRegister
        }

        settingsWindowController.onSetStartOnLogin = { [weak self] enabled in
            try self?.setStartOnLogin(enabled: enabled)
        }
    }

    private func toggleHistoryPanel(anchorRect: NSRect?) {
        let now = Date()
        if now.timeIntervalSince(lastHistoryToggleTime) < 0.2 {
            return
        }
        lastHistoryToggleTime = now

        historyManager.removeExpiredItems()

        if historyPanelController.isPanelPresented {
            historyPanelController.closePanel()
            return
        }

        capturePasteTargetApplication()
        historyPanelController.showPanel(anchorRect: anchorRect)
    }

    private func openSettings() {
        settings.startOnLogin = isStartOnLoginEnabled()
        settingsWindowController.updateSettings(settings)
        settingsWindowController.show()
    }

    private func applySettings(_ newSettings: SettingsModel) {
        settings.maxItems = clamp(newSettings.maxItems, min: SettingsModel.minMaxItems, max: SettingsModel.maxMaxItems)
        settings.ttlSeconds = clamp(newSettings.ttlSeconds, min: SettingsModel.minTTLSeconds, max: SettingsModel.maxTTLSeconds)
        settings.startOnLogin = newSettings.startOnLogin

        historyManager.maxItems = settings.maxItems
        historyManager.ttlSeconds = settings.ttlSeconds
        historyManager.removeExpiredItems()

        persistSettings()
    }

    private func startTTLCleanupTimer() {
        ttlCleanupTimer?.invalidate()
        ttlCleanupTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.historyManager.removeExpiredItems()
        }
        if let ttlCleanupTimer {
            RunLoop.main.add(ttlCleanupTimer, forMode: .common)
        }
    }

    private func setStartOnLogin(enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }

        let actualState = isStartOnLoginEnabled()
        guard actualState == enabled else {
            throw StartOnLoginError.statusMismatch
        }

        settings.startOnLogin = actualState
        persistSettings()
        settingsWindowController.updateSettings(settings)
    }

    private func isStartOnLoginEnabled() -> Bool {
        switch SMAppService.mainApp.status {
        case .enabled:
            return true
        default:
            return false
        }
    }

    private func loadSettings() -> SettingsModel {
        let defaults = UserDefaults.standard

        let maxItems = clamp(
            defaults.object(forKey: DefaultsKey.maxItems) as? Int ?? SettingsModel.defaultMaxItems,
            min: SettingsModel.minMaxItems,
            max: SettingsModel.maxMaxItems
        )

        let ttl = clamp(
            defaults.object(forKey: DefaultsKey.ttlSeconds) as? Int ?? SettingsModel.defaultTTLSeconds,
            min: SettingsModel.minTTLSeconds,
            max: SettingsModel.maxTTLSeconds
        )

        let defaultHotkey = HotkeyBinding.default
        let hotkeyKeyCode = defaults.object(forKey: DefaultsKey.hotkeyKeyCode) as? Int
        let hotkeyModifierRaw = defaults.object(forKey: DefaultsKey.hotkeyModifiers) as? Int
        let hotkey: HotkeyBinding
        if let hotkeyKeyCode, let hotkeyModifierRaw {
            let modifiers = NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifierRaw))
            hotkey = HotkeyBinding(keyCode: UInt32(hotkeyKeyCode), modifiers: modifiers)
        } else {
            hotkey = defaultHotkey
        }

        let serviceState = isStartOnLoginEnabled()
        let _ = defaults.object(forKey: DefaultsKey.startOnLogin) as? Bool ?? serviceState

        var model = SettingsModel()
        model.maxItems = maxItems
        model.ttlSeconds = ttl
        model.hotkey = hotkey
        model.startOnLogin = serviceState

        defaults.set(serviceState, forKey: DefaultsKey.startOnLogin)
        return model
    }

    private func persistSettings() {
        let defaults = UserDefaults.standard
        defaults.set(settings.maxItems, forKey: DefaultsKey.maxItems)
        defaults.set(settings.ttlSeconds, forKey: DefaultsKey.ttlSeconds)
        defaults.set(settings.startOnLogin, forKey: DefaultsKey.startOnLogin)
        defaults.set(settings.hotkey.keyCode, forKey: DefaultsKey.hotkeyKeyCode)
        defaults.set(settings.hotkey.modifierFlagsRawValue, forKey: DefaultsKey.hotkeyModifiers)
    }

    private func clamp(_ value: Int, min lowerBound: Int, max upperBound: Int) -> Int {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }

    private func capturePasteTargetApplication() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            pasteTargetApplication = nil
            return
        }

        if frontmost.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            pasteTargetApplication = nil
            return
        }

        pasteTargetApplication = frontmost
    }

    private func performAutoPaste() {
        guard let targetApplication = pasteTargetApplication else { return }
        guard ensureAccessibilityPermission() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            _ = targetApplication.activate(options: [.activateIgnoringOtherApps])
            self?.postCommandV()
            self?.pasteTargetApplication = nil
        }
    }

    private func ensureAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        guard !hasRequestedAccessibilityPermissionThisLaunch else {
            return false
        }
        hasRequestedAccessibilityPermissionThisLaunch = true

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func postCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let keyCode = CGKeyCode(kVK_ANSI_V)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
