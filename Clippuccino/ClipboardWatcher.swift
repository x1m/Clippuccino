import AppKit
import Foundation

final class ClipboardWatcher {
    private struct ProgrammaticWrite {
        let text: String
        let createdAt: Date
    }

    private let historyManager: HistoryManager
    private let pasteboard: NSPasteboard
    private let pollInterval: TimeInterval
    private let programmaticIgnoreWindow: TimeInterval = 2.0

    private var timer: Timer?
    private var lastChangeCount: Int
    private var pendingProgrammaticWrite: ProgrammaticWrite?

    var isPaused: Bool = false

    init(
        historyManager: HistoryManager,
        pasteboard: NSPasteboard = .general,
        pollInterval: TimeInterval = SettingsModel.defaultPollInterval
    ) {
        self.historyManager = historyManager
        self.pasteboard = pasteboard
        self.pollInterval = pollInterval
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setClipboardFromHistory(_ text: String) {
        pendingProgrammaticWrite = ProgrammaticWrite(text: text, createdAt: Date())
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func pollPasteboard(now: Date = Date()) {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }

        if isPaused {
            lastChangeCount = currentChangeCount
            pendingProgrammaticWrite = nil
            return
        }

        lastChangeCount = currentChangeCount

        if let pendingWrite = pendingProgrammaticWrite {
            if now.timeIntervalSince(pendingWrite.createdAt) > programmaticIgnoreWindow {
                pendingProgrammaticWrite = nil
            }
        }

        guard let string = pasteboard.string(forType: .string) else { return }

        if let pendingWrite = pendingProgrammaticWrite,
           now.timeIntervalSince(pendingWrite.createdAt) <= programmaticIgnoreWindow,
           pendingWrite.text == string {
            pendingProgrammaticWrite = nil
            return
        }

        historyManager.add(text: string, now: now)
    }
}
