import Foundation

/// Time spent reading, per calendar day, for the streak and the activity chart.
public struct ReadingLog: Codable, Sendable, Equatable {
    public struct Day: Codable, Sendable, Equatable {
        public var seconds: Double
        /// Books read that day, in the order first opened.
        public var books: [String]

        public init(seconds: Double = 0, books: [String] = []) {
            self.seconds = seconds
            self.books = books
        }
    }

    /// Keyed by local day, "2026-03-09". A day is the reader's own calendar day at the
    /// time of reading; it is stored as text so it does not shift when they travel.
    public var days: [String: Day]

    /// Decides where one day ends and the next begins. Not stored.
    public var calendar: Calendar

    /// Reading time a day needs to count toward the streak.
    public static let streakThreshold: Double = 5 * 60

    public init(days: [String: Day] = [:], calendar: Calendar = .current) {
        self.days = days
        self.calendar = calendar
    }

    private enum CodingKeys: String, CodingKey { case days }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        days = try container.decode([String: Day].self, forKey: .days)
        calendar = .current
    }

    public static func == (lhs: ReadingLog, rhs: ReadingLog) -> Bool {
        lhs.days == rhs.days
    }

    public mutating func record(seconds: Double, bookID: String, date: Date = Date()) {
        guard seconds > 0, seconds.isFinite else { return }
        let key = Self.key(for: date, calendar)
        var day = days[key] ?? Day()
        day.seconds += seconds
        if !day.books.contains(bookID) { day.books.append(bookID) }
        days[key] = day
    }

    public func secondsRead(on date: Date) -> Double {
        days[Self.key(for: date, calendar)]?.seconds ?? 0
    }

    public func bookIDs(on date: Date) -> [String] {
        days[Self.key(for: date, calendar)]?.books ?? []
    }

    /// Consecutive days with at least five minutes of reading. Today counts once it has
    /// its five minutes; until then the streak that ran through yesterday still stands.
    public func streak(asOf date: Date = Date()) -> Int {
        var day = calendar.startOfDay(for: date)
        if secondsRead(on: day) < Self.streakThreshold {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while secondsRead(on: day) >= Self.streakThreshold {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// The last `n` days ending with `asOf`, oldest first, zero for days without reading.
    public func lastDays(_ n: Int, asOf date: Date = Date()) -> [(day: Date, seconds: Double)] {
        guard n > 0 else { return [] }
        let today = calendar.startOfDay(for: date)
        return (0..<n).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { (day: $0, seconds: secondsRead(on: $0)) }
        }
    }

    static func key(for date: Date, _ calendar: Calendar) -> String {
        ReviewScheduler.dayKey(date, calendar)
    }
}

/// `<libraryRoot>/reading-log.json`.
public struct ReadingLogStore: Sendable {
    public let fileURL: URL
    private let calendar: Calendar

    public init(libraryRoot: URL, calendar: Calendar = .current) {
        fileURL = libraryRoot.appendingPathComponent("reading-log.json")
        self.calendar = calendar
    }

    /// Empty log when the file is missing or unreadable.
    public func load() -> ReadingLog {
        var log = LibraryJSONFile.load(ReadingLog.self, from: fileURL) ?? ReadingLog()
        log.calendar = calendar
        return log
    }

    public func save(_ log: ReadingLog) throws {
        try LibraryJSONFile.save(log, to: fileURL)
    }
}
