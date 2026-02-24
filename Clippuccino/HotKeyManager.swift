import AppKit
import Carbon.HIToolbox
import Foundation

final class HotKeyManager {
    var onHotKeyPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    deinit {
        unregisterCurrentHotKey()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    @discardableResult
    func register(binding: HotkeyBinding) -> Bool {
        if eventHandlerRef == nil {
            var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData in
                    guard let userData else { return noErr }
                    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                    manager.handleHotKeyEvent(event)
                    return noErr
                },
                1,
                &eventSpec,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                &eventHandlerRef
            )
            guard status == noErr else {
                return false
            }
        }

        unregisterCurrentHotKey()

        let hotKeyID = EventHotKeyID(signature: HotKeyManager.signature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(binding.keyCode),
            binding.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        return status == noErr
    }

    private func unregisterCurrentHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func handleHotKeyEvent(_ event: EventRef?) {
        guard let event else { return }

        var hotKeyID = EventHotKeyID()
        let dataSize = MemoryLayout<EventHotKeyID>.size
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            dataSize,
            nil,
            &hotKeyID
        )

        guard status == noErr, hotKeyID.signature == HotKeyManager.signature else { return }
        onHotKeyPressed?()
    }

    private static let signature: OSType = {
        let chars: [UInt8] = Array("CHMB".utf8)
        return chars.reduce(0) { ($0 << 8) + OSType($1) }
    }()
}
