import AppKit
import Carbon.HIToolbox
import Foundation

private extension String {
    func width(using font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (self as NSString).size(withAttributes: attributes).width
    }
}

private final class HistoryPanel: NSPanel {
    var onEscapePressed: (() -> Void)?
    var onHandleKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscapePressed?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if Int(event.keyCode) == kVK_Escape {
                onEscapePressed?()
                return
            }

            if onHandleKeyDown?(event) == true {
                return
            }
        }

        super.sendEvent(event)
    }
}

private final class HoverActionButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet {
            updateBackground()
        }
    }

    override var isHighlighted: Bool {
        didSet {
            updateBackground()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.masksToBounds = true
        updateBackground()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        if let trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    private func updateBackground() {
        guard let layer else { return }
        if isHighlighted {
            layer.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.34).cgColor
        } else if isHovering {
            layer.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.22).cgColor
        } else {
            layer.backgroundColor = NSColor.clear.cgColor
        }
    }
}

final class HistoryPanelController: NSWindowController {
    var onSelectItem: ((String) -> Void)?
    var onEraseAllHistory: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    private let historyManager: HistoryManager

    private let headerLabel = NSTextField(labelWithString: "History")
    private let searchField = NSSearchField(frame: .zero)
    private let tableView = NSTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private let emptyStateLabel = NSTextField(labelWithString: "Clipboard history is empty")
    private let rowFont = NSFont.systemFont(ofSize: 16, weight: .regular)
    private let actionFont = NSFont.systemFont(ofSize: 15, weight: .regular)
    private let minPanelWidth: CGFloat = 320
    private let maxPanelWidth: CGFloat = 560
    private let maxMeasuredRowTextLength: Int = 80

    private var filteredItems: [ClipboardItem] = []

    init(historyManager: HistoryManager) {
        self.historyManager = historyManager

        let panel = HistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.transient, .canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: panel)

        panel.onEscapePressed = { [weak self] in
            self?.closePanel()
        }
        panel.onHandleKeyDown = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }

        setupUI()
        configureWindowBehavior()
        refreshData(selectFirstRow: true)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func togglePanel() {
        if isPanelPresented {
            closePanel()
        } else {
            showPanel()
        }
    }

    var isPanelPresented: Bool {
        guard let window else { return false }
        return window.isVisible && window.occlusionState.contains(.visible)
    }

    func showPanel(anchorRect: NSRect? = nil) {
        guard let panel = window as? NSPanel else { return }
        refreshData(selectFirstRow: true)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.positionPanel(panel, anchorRect: anchorRect)
            panel.orderFrontRegardless()
            panel.makeKey()
            panel.makeFirstResponder(self.searchField)
        }
    }

    func closePanel() {
        window?.orderOut(nil)
    }

    func reloadDataIfVisible() {
        if window?.isVisible == true {
            refreshData(selectFirstRow: false)
        }
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let backgroundView = NSVisualEffectView(frame: .zero)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.material = .menu
        backgroundView.state = .active
        backgroundView.blendingMode = .withinWindow
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 10
        backgroundView.layer?.masksToBounds = true

        contentView.addSubview(backgroundView)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        headerLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        headerLabel.textColor = .secondaryLabelColor

        searchField.placeholderString = "Search"
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        searchField.focusRingType = .none

        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("historyColumn"))
        tableColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(tableColumn)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsEmptySelection = false
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.focusRingType = .none
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        emptyStateLabel.alignment = .center
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.font = NSFont.systemFont(ofSize: 12)
        emptyStateLabel.isHidden = true
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false

        let topStack = NSStackView(views: [headerLabel, searchField])
        topStack.orientation = .vertical
        topStack.spacing = 6
        topStack.alignment = .leading
        topStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 8, right: 12)

        let separator = NSBox()
        separator.boxType = .separator

        let clearButton = makeActionButton(title: "Clear History", action: #selector(clearHistoryTapped))
        let settingsButton = makeActionButton(title: "Preferences…", action: #selector(settingsTapped))
        let quitButton = makeActionButton(title: "Quit", action: #selector(quitTapped))

        let actionStack = NSStackView(views: [clearButton, settingsButton, quitButton])
        actionStack.orientation = .vertical
        actionStack.spacing = 8
        actionStack.alignment = .leading
        actionStack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 10, right: 0)

        let rootStack = NSStackView(views: [topStack, scrollView, separator, actionStack])
        rootStack.orientation = .vertical
        rootStack.spacing = 0
        rootStack.alignment = .leading
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        backgroundView.addSubview(rootStack)
        backgroundView.addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

            searchField.heightAnchor.constraint(equalToConstant: 26),
            actionStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            searchField.widthAnchor.constraint(equalTo: topStack.widthAnchor, constant: -24),
            clearButton.widthAnchor.constraint(equalTo: actionStack.widthAnchor),
            settingsButton.widthAnchor.constraint(equalTo: actionStack.widthAnchor),
            quitButton.widthAnchor.constraint(equalTo: actionStack.widthAnchor),
            clearButton.heightAnchor.constraint(equalToConstant: 24),
            settingsButton.heightAnchor.constraint(equalToConstant: 24),
            quitButton.heightAnchor.constraint(equalToConstant: 24),

            emptyStateLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
    }

    private func configureWindowBehavior() {
        window?.delegate = self
    }

    private func refreshData(selectFirstRow: Bool) {
        filteredItems = historyManager.filteredItems(matching: searchField.stringValue)
        adjustPanelWidth()
        tableView.reloadData()
        tableView.sizeLastColumnToFit()
        emptyStateLabel.isHidden = !filteredItems.isEmpty

        guard !filteredItems.isEmpty else { return }

        if selectFirstRow {
            selectRow(0)
        } else if tableView.selectedRow >= filteredItems.count {
            selectRow(filteredItems.count - 1)
        }
    }

    @objc private func searchFieldChanged() {
        refreshData(selectFirstRow: true)
    }

    @objc private func clearHistoryTapped() {
        onEraseAllHistory?()
        refreshData(selectFirstRow: true)
    }

    @objc private func settingsTapped() {
        onOpenSettings?()
    }

    @objc private func quitTapped() {
        onQuit?()
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_UpArrow:
            moveSelection(delta: -1)
            return true
        case kVK_DownArrow:
            moveSelection(delta: 1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            selectCurrentRow()
            return true
        default:
            break
        }

        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            return false
        }
        guard let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1 else { return false }

        let index: Int?
        switch key {
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            index = Int(key).map { $0 - 1 }
        case "0":
            index = 9
        default:
            index = nil
        }

        guard let resolvedIndex = index, resolvedIndex >= 0, resolvedIndex < filteredItems.count else {
            return false
        }

        selectRow(resolvedIndex)
        selectCurrentRow()
        return true
    }

    private func moveSelection(delta: Int) {
        guard !filteredItems.isEmpty else { return }

        let currentRow = tableView.selectedRow
        let targetRow: Int
        if currentRow == -1 {
            targetRow = delta > 0 ? 0 : filteredItems.count - 1
        } else {
            targetRow = min(max(currentRow + delta, 0), filteredItems.count - 1)
        }

        selectRow(targetRow)
    }

    private func selectRow(_ row: Int) {
        guard row >= 0, row < filteredItems.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func selectCurrentRow() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredItems.count else { return }

        let selectedItem = filteredItems[row]
        onSelectItem?(selectedItem.text)
        closePanel()
    }

    private func positionPanel(_ panel: NSPanel, anchorRect: NSRect?) {
        let mouseLocation = NSEvent.mouseLocation
        let referencePoint = anchorRect?.origin ?? mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(referencePoint) }) ?? NSScreen.main
        guard let screen else { return }

        let panelSize = panel.frame.size
        let visibleFrame = screen.visibleFrame.insetBy(dx: 8, dy: 8)

        var origin: NSPoint
        if let anchorRect {
            // Match native status item popup behavior: left edge under icon.
            origin = NSPoint(
                x: anchorRect.minX,
                y: anchorRect.minY - panelSize.height - 6
            )
        } else {
            origin = NSPoint(
                x: mouseLocation.x + 12,
                y: mouseLocation.y - panelSize.height - 12
            )
        }

        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - panelSize.height)
        panel.setFrameOrigin(origin)
    }

    private func adjustPanelWidth() {
        guard let panel = window as? NSPanel else { return }

        let screen = NSScreen.screens.first(where: { $0.frame.contains(panel.frame.origin) }) ?? NSScreen.main
        let screenWidthLimit = max(minPanelWidth, (screen?.visibleFrame.width ?? 900) - 16)
        let maxAllowedWidth = min(maxPanelWidth, screenWidthLimit)

        var widest: CGFloat = 0
        for (idx, item) in filteredItems.enumerated() {
            let text = "\(idx + 1). \(previewText(for: item.text, maxLength: maxMeasuredRowTextLength))"
            widest = max(widest, text.width(using: rowFont))
        }

        widest = max(widest, "History".width(using: NSFont.systemFont(ofSize: 14, weight: .medium)))
        widest = max(widest, "Clear History".width(using: actionFont))
        widest = max(widest, "Preferences…".width(using: actionFont))
        widest = max(widest, "Quit".width(using: actionFont))

        // Side insets + room for scroller + selection highlight breathing space.
        let desiredWidth = min(max(widest + 40, minPanelWidth), maxAllowedWidth)
        guard abs(panel.frame.width - desiredWidth) >= 1 else { return }

        var frame = panel.frame
        frame.size.width = desiredWidth
        panel.setFrame(frame, display: false)
    }

    private func previewText(for text: String, maxLength: Int = 120) -> String {
        let sanitized = text.replacingOccurrences(of: "\n", with: " ")
        if sanitized.count <= maxLength {
            return sanitized
        }
        return String(sanitized.prefix(maxLength)) + "…"
    }

    private func makeActionButton(title: String, action: Selector) -> NSButton {
        let button = HoverActionButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.alignment = .left
        button.font = actionFont
        button.contentTintColor = .labelColor
        button.setButtonType(.momentaryPushIn)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.firstLineHeadIndent = 10
        paragraphStyle.headIndent = 10
        let attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: actionFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
        )
        button.attributedTitle = attributedTitle
        button.attributedAlternateTitle = attributedTitle
        return button
    }
}

extension HistoryPanelController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        closePanel()
    }
}

extension HistoryPanelController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = filteredItems[row]
        let identifier = NSUserInterfaceItemIdentifier("HistoryCell")

        let cellView: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cellView = existing
        } else {
            cellView = NSTableCellView(frame: .zero)
            cellView.identifier = identifier

            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            label.font = rowFont
            cellView.textField = label
            cellView.addSubview(label)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cellView.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
                label.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 3),
                label.bottomAnchor.constraint(equalTo: cellView.bottomAnchor, constant: -3)
            ])
        }

        cellView.textField?.stringValue = "\(row + 1). \(previewText(for: item.text))"
        return cellView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if tableView.selectedRow == -1, !filteredItems.isEmpty {
            selectRow(0)
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        row >= 0 && row < filteredItems.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        32
    }
}
