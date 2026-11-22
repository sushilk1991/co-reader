import Foundation
import Testing
@testable import CoreaderKit

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// Noon UTC on a day of March 2026.
private func day(_ d: Int, hour: Int = 12) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 3, day: d, hour: hour))!
}

private func tempRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("coreader-review-\(UUID().uuidString)")
}

// MARK: Scheduler

@Test func reviewNewHighlightsWaitUntilTheNextDay() {
    let scheduler = ReviewScheduler(dailyLimit: 7, calendar: utc)
    let created = ["old": day(1), "today": day(10, hour: 1), "lateYesterday": day(9, hour: 23)]
    let due = scheduler.due(annotationIDs: ["old", "today", "lateYesterday", "undated"], createdAt: created,
                            state: ReviewState(), now: day(10))
    #expect(Set(due) == ["old", "lateYesterday", "undated"])
}

@Test func reviewRespectsTheDailyLimitAndKeepsTheOrderForTheDay() {
    let scheduler = ReviewScheduler(dailyLimit: 7, calendar: utc)
    let ids = (0..<40).map { "h\($0)" }
    let created = Dictionary(uniqueKeysWithValues: ids.map { ($0, day(1)) })
    let morning = scheduler.due(annotationIDs: ids, createdAt: created, state: ReviewState(), now: day(10, hour: 8))
    let evening = scheduler.due(annotationIDs: ids.reversed(), createdAt: created, state: ReviewState(), now: day(10, hour: 22))
    #expect(morning.count == 7)
    #expect(morning == evening)
    #expect(Set(morning).count == 7)
    // Another day draws a different hand.
    let tomorrow = scheduler.due(annotationIDs: ids, createdAt: created, state: ReviewState(), now: day(11))
    #expect(tomorrow != morning)
    #expect(ReviewScheduler(dailyLimit: 0, calendar: utc).due(annotationIDs: ids, createdAt: created, state: ReviewState(), now: day(10)).isEmpty)
}

@Test func reviewingShrinksTheListWithoutRefillingIt() {
    let scheduler = ReviewScheduler(dailyLimit: 7, calendar: utc)
    var state = ReviewState()
    let fresh = (0..<20).map { "new\($0)" }
    let returning = (0..<20).map { "old\($0)" }
    for (index, id) in returning.enumerated() {
        state.items[id] = ReviewState.Item(interval: 3, due: day(1 + index % 5), reviews: 2, lastReviewed: day(1))
    }
    let ids = fresh + returning
    let created = Dictionary(uniqueKeysWithValues: ids.map { ($0, day(1)) })

    var list = scheduler.due(annotationIDs: ids, createdAt: created, state: state, now: day(10))
    #expect(list.count == 7)
    #expect(list.filter { $0.hasPrefix("new") }.count == 3)   // 40% of 7, rounded
    #expect(list.filter { $0.hasPrefix("old") }.count == 4)

    // Work through the day's list with every kind of grade; each answer removes exactly
    // that item and leaves the rest in place.
    let grades: [ReviewGrade] = [.good, .forgot, .easy, .hard, .good, .forgot, .easy]
    var step = 0
    while let next = list.first {
        scheduler.record(grades[step % grades.count], for: next, in: &state, now: day(10, hour: 12 + step))
        let after = scheduler.due(annotationIDs: ids, createdAt: created, state: state, now: day(10, hour: 12 + step))
        #expect(after == Array(list.dropFirst()))
        list = after
        step += 1
    }
    #expect(step == 7)
    #expect(scheduler.due(annotationIDs: ids, createdAt: created, state: state, now: day(10, hour: 23)).isEmpty)
    #expect(scheduler.due(annotationIDs: ids, createdAt: created, state: state, now: day(11)).count == 7)
}

@Test func reviewFillsFromTheOtherPoolWhenOneIsShort() {
    let scheduler = ReviewScheduler(dailyLimit: 7, calendar: utc)
    var state = ReviewState()
    state.items["due"] = ReviewState.Item(interval: 1, due: day(9), reviews: 1, lastReviewed: day(8))
    state.items["later"] = ReviewState.Item(interval: 30, due: day(25), reviews: 3, lastReviewed: day(8))
    let fresh = (0..<10).map { "n\($0)" }
    let list = scheduler.due(annotationIDs: fresh + ["due", "later", "due"], createdAt: [:], state: state, now: day(10))
    #expect(list.count == 7)
    #expect(list.contains("due"))
    #expect(!list.contains("later"))
    #expect(list.filter { $0.hasPrefix("n") }.count == 6)

    // Only returning items: they take the whole day, most overdue first in.
    for index in 0..<10 {
        state.items["r\(index)"] = ReviewState.Item(interval: 2, due: day(index < 5 ? 2 : 9), reviews: 2, lastReviewed: day(1))
    }
    let onlyReturning = scheduler.due(annotationIDs: (0..<10).map { "r\($0)" }, createdAt: [:], state: state, now: day(10))
    #expect(onlyReturning.count == 7)
    #expect(Set((0..<5).map { "r\($0)" }).isSubset(of: Set(onlyReturning)))
}

@Test func reviewRecordFollowsSM2() {
    let scheduler = ReviewScheduler(calendar: utc)
    var state = ReviewState()

    scheduler.record(.good, for: "a", in: &state, now: day(10, hour: 23))
    var a = state.items["a"]!
    #expect(a.interval == 3)
    #expect(a.ease == 2.5)
    #expect(a.reviews == 1)
    #expect(a.lastReviewed == day(10, hour: 23))
    #expect(a.due == utc.startOfDay(for: day(13)))   // a whole day, however late the review

    scheduler.record(.good, for: "a", in: &state, now: day(13))
    a = state.items["a"]!
    #expect(a.interval == 7.5)
    #expect(a.due == utc.startOfDay(for: day(21)))

    scheduler.record(.easy, for: "a", in: &state, now: day(21))
    a = state.items["a"]!
    #expect(abs(a.interval - 24.4) < 0.01)   // 7.5 × 2.5 × 1.3
    #expect(abs(a.ease - 2.65) < 1e-9)

    scheduler.record(.hard, for: "a", in: &state, now: day(21))
    a = state.items["a"]!
    #expect(abs(a.interval - 29.3) < 0.01)
    #expect(abs(a.ease - 2.5) < 1e-9)

    scheduler.record(.forgot, for: "a", in: &state, now: day(22))
    a = state.items["a"]!
    #expect(a.interval == 1)
    #expect(abs(a.ease - 2.3) < 1e-9)
    #expect(a.due == utc.startOfDay(for: day(23)))
    #expect(a.reviews == 5)

    // First answers.
    scheduler.record(.easy, for: "e", in: &state, now: day(10))
    scheduler.record(.hard, for: "h", in: &state, now: day(10))
    scheduler.record(.forgot, for: "f", in: &state, now: day(10))
    #expect(state.items["e"]?.interval == 7)
    #expect(state.items["h"]?.interval == 1)
    #expect(state.items["f"]?.interval == 1)

    // Ease has a floor and intervals a ceiling.
    for step in 0..<12 { scheduler.record(.forgot, for: "f", in: &state, now: day(11 + step)) }
    #expect(state.items["f"]?.ease == 1.3)
    var date = day(10)
    for _ in 0..<12 {
        scheduler.record(.easy, for: "e", in: &state, now: date)
        date = state.items["e"]!.due
    }
    #expect(state.items["e"]?.interval == 365)
}

// MARK: Store

@Test func reviewStoreRoundTripsAndToleratesBadFiles() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ReviewStore(libraryRoot: root)
    #expect(store.load() == ReviewState())   // no folder, no file

    var state = ReviewState()
    ReviewScheduler(calendar: utc).record(.good, for: "abc123", in: &state, now: day(10))
    try store.save(state)
    #expect(store.fileURL.lastPathComponent == "review.json")
    #expect(store.load() == state)
    let text = try String(contentsOf: store.fileURL, encoding: .utf8)
    #expect(text.contains("\"due\" : \"2026-03-13T00:00:00Z\""))

    try Data("{ not json".utf8).write(to: store.fileURL)
    #expect(store.load() == ReviewState())
    // The unreadable file is kept aside before anything overwrites it.
    let backup = root.appendingPathComponent("review.corrupt.json")
    #expect(try String(contentsOf: backup, encoding: .utf8) == "{ not json")
    try store.save(state)
    #expect(store.load() == state)
}

// MARK: Reading log

@Test func readingLogAccumulatesPerDay() {
    var log = ReadingLog(calendar: utc)
    log.record(seconds: 120, bookID: "b1", date: day(10, hour: 9))
    log.record(seconds: 200, bookID: "b2", date: day(10, hour: 21))
    log.record(seconds: 50, bookID: "b1", date: day(10, hour: 22))
    log.record(seconds: 0, bookID: "b3", date: day(10))
    log.record(seconds: -5, bookID: "b3", date: day(10))
    log.record(seconds: 30, bookID: "b9", date: day(11, hour: 0))
    #expect(log.secondsRead(on: day(10, hour: 3)) == 370)
    #expect(log.bookIDs(on: day(10)) == ["b1", "b2"])
    #expect(log.secondsRead(on: day(11)) == 30)
    #expect(log.secondsRead(on: day(12)) == 0)
    #expect(log.days.keys.sorted() == ["2026-03-10", "2026-03-11"])
}

@Test func readingLogStreak() {
    var log = ReadingLog(calendar: utc)
    #expect(log.streak(asOf: day(10)) == 0)
    for d in [5, 7, 8, 9] { log.record(seconds: 600, bookID: "b", date: day(d)) }
    // Nothing yet today: the streak through yesterday stands.
    #expect(log.streak(asOf: day(10)) == 3)
    // Under five minutes today changes nothing.
    log.record(seconds: 299, bookID: "b", date: day(10))
    #expect(log.streak(asOf: day(10)) == 3)
    log.record(seconds: 1, bookID: "b", date: day(10))
    #expect(log.streak(asOf: day(10)) == 4)
    // A missed day ends it.
    #expect(log.streak(asOf: day(12)) == 0)
    #expect(log.streak(asOf: day(11)) == 4)
    #expect(log.streak(asOf: day(6)) == 1)
}

@Test func readingLogLastDaysIsOldestFirstWithGapsAsZero() {
    var log = ReadingLog(calendar: utc)
    log.record(seconds: 100, bookID: "b", date: day(8))
    log.record(seconds: 300, bookID: "b", date: day(10))
    let week = log.lastDays(4, asOf: day(10, hour: 18))
    #expect(week.map(\.seconds) == [0, 100, 0, 300])
    #expect(week.map(\.day) == [7, 8, 9, 10].map { utc.startOfDay(for: day($0)) })
    #expect(log.lastDays(0, asOf: day(10)).isEmpty)
}

@Test func readingLogDaysFollowTheInjectedCalendar() {
    var tokyo = Calendar(identifier: .gregorian)
    tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    var log = ReadingLog(calendar: tokyo)
    // 20:00 UTC on the 10th is already the 11th in Tokyo.
    log.record(seconds: 400, bookID: "b", date: day(10, hour: 20))
    #expect(log.days.keys.sorted() == ["2026-03-11"])
}

@Test func readingLogStoreRoundTrips() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ReadingLogStore(libraryRoot: root, calendar: utc)
    #expect(store.load().days.isEmpty)

    var log = store.load()
    log.record(seconds: 301.5, bookID: "b1", date: day(10))
    try store.save(log)
    #expect(store.fileURL.lastPathComponent == "reading-log.json")
    let loaded = store.load()
    #expect(loaded == log)
    #expect(loaded.streak(asOf: day(10)) == 1)
    #expect(!(try String(contentsOf: store.fileURL, encoding: .utf8)).contains("calendar"))

    try Data("garbage".utf8).write(to: store.fileURL)
    #expect(store.load().days.isEmpty)
}
