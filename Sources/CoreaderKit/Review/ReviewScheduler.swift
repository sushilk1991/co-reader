import Foundation

public enum ReviewGrade: Int, Sendable, Codable, CaseIterable {
    case forgot = 0, hard, good, easy
}

/// Spaced-repetition state for the daily highlight review. Only reviewed highlights have
/// an entry; a highlight without one is new.
public struct ReviewState: Codable, Sendable, Equatable {
    /// Keyed by annotation id.
    public var items: [String: Item]

    public struct Item: Codable, Sendable, Equatable {
        /// Days until the next review, as of the last one.
        public var interval: Double
        /// SM-2 ease factor: how fast the interval grows. Starts at 2.5, never below 1.3.
        public var ease: Double
        public var due: Date
        public var reviews: Int
        public var lastReviewed: Date?

        public init(interval: Double = 0, ease: Double = 2.5, due: Date, reviews: Int = 0, lastReviewed: Date? = nil) {
            self.interval = interval
            self.ease = ease
            self.due = due
            self.reviews = reviews
            self.lastReviewed = lastReviewed
        }
    }

    public init(items: [String: Item] = [:]) {
        self.items = items
    }
}

public struct ReviewScheduler: Sendable {
    public var dailyLimit: Int
    public var calendar: Calendar

    /// Share of a day's reviews kept for highlights never reviewed before, when there are
    /// both new and returning ones to choose from.
    static let newShare = 0.4
    static let minimumEase = 1.3
    static let maximumInterval = 365.0

    public init(dailyLimit: Int = 7, calendar: Calendar = .current) {
        self.dailyLimit = max(dailyLimit, 0)
        self.calendar = calendar
    }

    /// Today's review list: returning highlights that are due plus some new ones, at most
    /// `dailyLimit` for the day counting what was already reviewed today.
    ///
    /// The list is stable within a day: reviewing an item removes it and nothing else
    /// moves in or reorders. New highlights become eligible the day after they are made
    /// (reviewing what you marked an hour ago teaches nothing). An id missing from
    /// `createdAt` is treated as old enough.
    public func due(annotationIDs: [String], createdAt: [String: Date], state: ReviewState, now: Date) -> [String] {
        let today = calendar.startOfDay(for: now)
        let ids = Array(Set(annotationIDs))

        var returning: [(id: String, due: Date)] = []
        var fresh: [String] = []
        // What today has used up already, split the same way, so the quotas below are
        // computed over the same pools all day long.
        var doneReturning = 0, doneFresh = 0
        for id in ids {
            if let item = state.items[id] {
                if let last = item.lastReviewed, calendar.isDate(last, inSameDayAs: now) {
                    if item.reviews <= 1 { doneFresh += 1 } else { doneReturning += 1 }
                } else if calendar.startOfDay(for: item.due) <= today {
                    returning.append((id, item.due))
                }
            } else if let created = createdAt[id] {
                if calendar.startOfDay(for: created) < today { fresh.append(id) }
            } else {
                fresh.append(id)
            }
        }

        let dayKey = Self.dayKey(today, calendar)
        func order(_ id: String) -> UInt64 { FNV1a.hash(dayKey + "|" + id) }

        // Most overdue first among returning items; new ones in the day's shuffle.
        returning.sort { ($0.due, $0.id) < ($1.due, $1.id) }
        fresh.sort { (order($0), $0) < (order($1), $1) }

        let freshPool = fresh.count + doneFresh
        let returningPool = returning.count + doneReturning
        var freshQuota = min(freshPool, Int((Double(dailyLimit) * Self.newShare).rounded()))
        var returningQuota = min(returningPool, dailyLimit - freshQuota)
        // Whatever one pool cannot fill goes to the other.
        freshQuota = min(freshPool, dailyLimit - returningQuota)
        returningQuota = min(returningPool, dailyLimit - freshQuota)

        let chosen = returning.prefix(max(returningQuota - doneReturning, 0)).map(\.id)
            + fresh.prefix(max(freshQuota - doneFresh, 0))
        // One shuffle for the whole list so new and returning highlights are interleaved.
        return chosen.sorted { (order($0), $0) < (order($1), $1) }
    }

    /// SM-2, adapted to highlights: there is no "learning" phase, intervals start in days.
    ///
    /// - forgot: back tomorrow, ease drops.
    /// - hard: interval grows by 20% (at least a day), ease drops a little.
    /// - good: interval × ease (3 days the first time).
    /// - easy: interval × ease × 1.3 (a week the first time), ease rises.
    public func record(_ grade: ReviewGrade, for id: String, in state: inout ReviewState, now: Date) {
        var item = state.items[id] ?? ReviewState.Item(due: now)
        let isFirst = item.reviews == 0 || item.interval <= 0

        switch grade {
        case .forgot:
            item.interval = 1
            item.ease -= 0.2
        case .hard:
            item.interval = isFirst ? 1 : max(1, item.interval * 1.2)
            item.ease -= 0.15
        case .good:
            item.interval = isFirst ? 3 : item.interval * item.ease
        case .easy:
            item.interval = isFirst ? 7 : item.interval * item.ease * 1.3
            item.ease += 0.15
        }
        item.ease = max(Self.minimumEase, item.ease)
        item.interval = min(Self.maximumInterval, (item.interval * 10).rounded() / 10)
        item.reviews += 1
        item.lastReviewed = now
        // Due dates are whole days: an item reviewed late at night is still due on the
        // morning of its day, not at 23:40.
        let days = Int(item.interval.rounded(.up))
        item.due = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(item.interval * 86_400)
        state.items[id] = item
    }

    static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// `<libraryRoot>/review.json`. Like every file in the library it is written atomically
/// and readable by other tools.
public struct ReviewStore: Sendable {
    public let fileURL: URL

    public init(libraryRoot: URL) {
        fileURL = libraryRoot.appendingPathComponent("review.json")
    }

    /// Empty state when the file is missing or unreadable.
    public func load() -> ReviewState {
        LibraryJSONFile.load(ReviewState.self, from: fileURL) ?? ReviewState()
    }

    public func save(_ state: ReviewState) throws {
        try LibraryJSONFile.save(state, to: fileURL)
    }
}

/// Shared reading and writing for the small JSON files in the library root.
enum LibraryJSONFile {
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let value = try? decoder.decode(type, from: data) { return value }
        // Unreadable: starting empty is right, but the next save would erase whatever is
        // there (a sync conflict, a half-written file). Keep a copy beside it first.
        let backup = url.deletingPathExtension().appendingPathExtension("corrupt.json")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: url, to: backup)
        return nil
    }

    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
