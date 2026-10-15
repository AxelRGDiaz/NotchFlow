import Foundation
import Testing
@testable import NotchKit

@MainActor
@Suite struct ShelfServiceTests {
    private func makeDefaults() -> UserDefaults {
        let name = "shelf-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data("x".utf8).write(to: url)
        return url
    }

    @Test func addsNewestFirstWithoutDuplicatesAndPersists() throws {
        let defaults = makeDefaults()
        let a = try makeFile("a.txt"), b = try makeFile("b.txt")
        let shelf = ShelfService(defaults: defaults)
        shelf.add([a])
        shelf.add([b, a, URL(string: "https://example.com")!])
        #expect(shelf.items == [b, a].map(\.standardizedFileURL))

        let reopened = ShelfService(defaults: defaults)
        #expect(reopened.items == shelf.items)
    }

    @Test func dropsMissingFilesOnLoad() throws {
        let defaults = makeDefaults()
        let kept = try makeFile("kept.txt"), gone = try makeFile("gone.txt")
        ShelfService(defaults: defaults).add([kept, gone])
        try FileManager.default.removeItem(at: gone)
        #expect(ShelfService(defaults: defaults).items == [kept.standardizedFileURL])
    }

    @Test func capsTheNumberOfItems() throws {
        let shelf = ShelfService(defaults: makeDefaults())
        let files = try (0..<(ShelfService.maxItems + 5)).map { try makeFile("\($0).txt") }
        shelf.add(files)
        #expect(shelf.items.count == ShelfService.maxItems)
    }

    @Test func keepsTheOriginalFileName() throws {
        // El Finder puede entregar "file:///.file/id=…"; debe verse el nombre real.
        let file = try makeFile("Informe final.pdf")
        let shelf = ShelfService(defaults: makeDefaults())
        shelf.add([file])
        #expect(shelf.items.first?.lastPathComponent == file.lastPathComponent)
        #expect(ShelfService.resolved(URL(string: "https://example.com")!) == nil)
    }

    @Test func pruneDropsFilesMovedAway() throws {
        let shelf = ShelfService(defaults: makeDefaults())
        let kept = try makeFile("kept.txt"), moved = try makeFile("moved.txt")
        shelf.add([kept, moved])
        try FileManager.default.removeItem(at: moved)
        shelf.pruneMissing()
        #expect(shelf.items == [kept.standardizedFileURL])
    }

    @Test func removeAndClear() throws {
        let shelf = ShelfService(defaults: makeDefaults())
        let a = try makeFile("a.txt"), b = try makeFile("b.txt")
        shelf.add([a, b])
        shelf.remove(a.standardizedFileURL)
        #expect(shelf.items == [b.standardizedFileURL])
        shelf.clear()
        #expect(shelf.items.isEmpty)
    }
}

@Suite struct ReminderItemTests {
    @Test func datedFirstThenUndatedInOriginalOrder() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let items = [
            ReminderItem(id: "sin1", title: "Sin fecha 1"),
            ReminderItem(id: "tarde", title: "Tarde", dueDate: now + 3600),
            ReminderItem(id: "sin2", title: "Sin fecha 2"),
            ReminderItem(id: "pronto", title: "Pronto", dueDate: now),
        ]
        #expect(ReminderItem.sorted(items).map(\.id) == ["pronto", "tarde", "sin1", "sin2"])
    }
}

@Suite struct CountdownTimerTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func runsPausesResumesAndFinishes() {
        var timer = CountdownTimer(duration: 300)
        #expect(timer.remaining(at: t0) == 300)
        timer.start(now: t0)
        #expect(timer.remaining(at: t0 + 100) == 200)
        #expect(abs(timer.progress(at: t0 + 150) - 0.5) < 0.0001)

        timer.pause(now: t0 + 100)
        #expect(timer.state == .paused(remaining: 200))
        // En pausa no avanza.
        #expect(timer.remaining(at: t0 + 1000) == 200)

        timer.start(now: t0 + 1000)
        #expect(timer.finishIfDue(now: t0 + 1100) == false)
        #expect(timer.finishIfDue(now: t0 + 1200) == true)
        #expect(timer.state == .finished(at: t0 + 1200))
        #expect(timer.remaining(at: t0 + 1300) == 0)
        // Solo avisa una vez.
        #expect(timer.finishIfDue(now: t0 + 1300) == false)
    }

    @Test func durationIsClampedAndResetKeepsIt() {
        var timer = CountdownTimer(duration: 5)
        #expect(timer.duration == 60)
        timer.setDuration(600)
        timer.start(now: t0)
        timer.reset()
        #expect(timer.state == .idle)
        #expect(timer.duration == 600)
    }

    @Test func formatsMinutesAndHours() {
        #expect(CountdownTimer.format(65) == "1:05")
        #expect(CountdownTimer.format(59.2) == "1:00")
        #expect(CountdownTimer.format(3725) == "1:02:05")
    }

    @Test func compactWingShowsTimerBeforeEvent() {
        var timer = CountdownTimer(duration: 300)
        timer.start(now: t0)
        let event = CalendarEvent(id: "e", title: "Reunión", start: t0 + 600, end: t0 + 1200, isAllDay: false)
        let running = CompactContentBuilder.build(.init(events: [event], timer: timer, indicators: [.nextEvent], now: t0))
        #expect(running.content.leading?.countdownEnd == t0 + 300)
        #expect(running.content.wingWidth == 92)

        _ = timer.finishIfDue(now: t0 + 300)
        let finished = CompactContentBuilder.build(.init(timer: timer, indicators: [], now: t0 + 310))
        #expect(finished.content.leading?.text == "Listo")
        #expect(finished.nextRefresh == t0 + 300 + CompactContentBuilder.timerFinishedLinger)

        let later = CompactContentBuilder.build(.init(events: [event], timer: timer, indicators: [.nextEvent], now: t0 + 400))
        #expect(later.content.leading?.systemImage == "calendar")
    }
}

@Suite struct PendingSeekTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func track(position: TimeInterval, at date: Date, playing: Bool = true, id: String = "A") -> NowPlaying {
        NowPlaying(player: .appleMusic, trackID: id, title: "Canción", duration: 300, isPlaying: playing, position: position, positionDate: date)
    }

    @Test func keepsTheRequestedPositionWhileThePlayerReportsTheOldOne() {
        let pending = PendingSeek(track: track(position: 30, at: t0), position: 200, date: t0)
        // Lectura llegada justo después, aún con la posición vieja.
        let result = pending.reconcile(track(position: 31, at: t0 + 1), now: t0 + 1)
        #expect(result.stillPending)
        #expect(result.track.position(at: t0 + 1) == 201)
    }

    @Test func acceptsThePlayerOnceItCatchesUp() {
        let pending = PendingSeek(track: track(position: 30, at: t0), position: 200, date: t0)
        let fresh = track(position: 201.4, at: t0 + 1)
        let result = pending.reconcile(fresh, now: t0 + 1)
        #expect(!result.stillPending)
        #expect(result.track == fresh)
    }

    @Test func givesUpAfterTimeoutOrTrackChange() {
        let pending = PendingSeek(track: track(position: 30, at: t0), position: 200, date: t0)
        let stale = track(position: 33, at: t0 + 4)
        #expect(pending.reconcile(stale, now: t0 + 4).track == stale)
        let other = track(position: 0, at: t0 + 1, id: "B")
        #expect(pending.reconcile(other, now: t0 + 1).stillPending == false)
    }
}
