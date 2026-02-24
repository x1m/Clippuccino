import Foundation

final class HistoryManager {
    var maxItems: Int {
        didSet {
            if maxItems < 1 { maxItems = 1 }
            enforceMaxItems()
            notifyChanged()
        }
    }

    var ttlSeconds: Int {
        didSet {
            if ttlSeconds < 0 { ttlSeconds = 0 }
            removeExpiredItems()
        }
    }

    let maxItemLength: Int

    private(set) var items: [ClipboardItem] = []
    var onChange: (() -> Void)?

    init(maxItems: Int, ttlSeconds: Int, maxItemLength: Int = SettingsModel.defaultMaxItemLength) {
        self.maxItems = max(1, maxItems)
        self.ttlSeconds = max(0, ttlSeconds)
        self.maxItemLength = maxItemLength
    }

    @discardableResult
    func add(text: String, now: Date = Date()) -> Bool {
        guard !text.isEmpty else { return false }
        guard text.count <= maxItemLength else { return false }
        if let current = items.first, current.text == text { return false }

        items.insert(ClipboardItem(text: text, createdAt: now), at: 0)
        enforceMaxItems()
        notifyChanged()
        return true
    }

    func removeExpiredItems(now: Date = Date()) {
        guard ttlSeconds > 0 else { return }
        let ttl = TimeInterval(ttlSeconds)
        let originalCount = items.count
        items.removeAll { now.timeIntervalSince($0.createdAt) >= ttl }
        if items.count != originalCount {
            notifyChanged()
        }
    }

    func filteredItems(matching query: String, now: Date = Date()) -> [ClipboardItem] {
        removeExpiredItems(now: now)
        if query.isEmpty {
            return items
        }

        let lowercasedQuery = query.lowercased()
        return items.filter { $0.text.lowercased().contains(lowercasedQuery) }
    }

    func eraseAll() {
        guard !items.isEmpty else { return }
        items.removeAll()
        notifyChanged()
    }

    private func enforceMaxItems() {
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
    }

    private func notifyChanged() {
        onChange?()
    }
}
