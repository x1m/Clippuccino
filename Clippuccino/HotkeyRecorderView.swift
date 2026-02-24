import AppKit
import Carbon.HIToolbox
import Foundation

final class HotkeyRecorderView: NSView {
    var onHotkeyRecorded: ((HotkeyBinding) -> Void)?

    var hotkey: HotkeyBinding {
        didSet {
            updateLabel()
        }
    }

    private var isRecording = false {
        didSet {
            updateLabel()
            needsDisplay = true
        }
    }

    private let label = NSTextField(labelWithString: "")

    init(hotkey: HotkeyBinding) {
        self.hotkey = hotkey
        super.init(frame: .zero)
        setupUI()
        updateLabel()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let roundedRect = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        roundedRect.lineWidth = 1
        roundedRect.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard window?.makeFirstResponder(self) == true else { return }
        isRecording = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if Int(event.keyCode) == kVK_Escape {
            isRecording = false
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !modifiers.isEmpty else {
            NSSound.beep()
            return
        }

        let newBinding = HotkeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        hotkey = newBinding
        isRecording = false
        onHotkeyRecorded?(newBinding)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    private func setupUI() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            heightAnchor.constraint(equalToConstant: 30),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
    }

    private func updateLabel() {
        label.stringValue = isRecording ? "Type shortcut…" : hotkey.displayString
    }
}
