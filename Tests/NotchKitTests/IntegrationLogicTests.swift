import Foundation
import Testing
@testable import NotchKit

@Suite struct CompactContentBuilderTests {
    let now = Date(timeIntervalSinceReferenceDate: 50_000)
    let all = Set(CompactIndicator.allCases)

    func event(_ id: String, startsIn: TimeInterval, lasts: TimeInterval = 1_800, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, title: id, start: now + startsIn, end: now + startsIn + lasts, isAllDay: allDay)
    }

    func track(playing: Bool) -> NowPlaying {
        NowPlaying(player: .appleMusic, title: "Pista", isPlaying: playing)
    }

    @Test func nothingToShowMeansEmptyContent() {
        let output = CompactContentBuilder.build(.init(indicators: all, now: now))
        #expect(output.content.isEmpty)
        #expect(output.nextRefresh == nil)
    }

    @Test func musicAppearsOnlyWhilePlaying() {
        let playing = CompactContentBuilder.build(.init(nowPlaying: track(playing: true), indicators: all, now: now))
        #expect(playing.content.leading?.systemImage == "waveform")
        let paused = CompactContentBuilder.build(.init(nowPlaying: track(playing: false), indicators: all, now: now))
        #expect(paused.content.isEmpty)
    }

    @Test func eventWithinLeadTimeShowsMinutesAndRefreshesOnNextMinute() {
        let output = CompactContentBuilder.build(.init(events: [event("reunión", startsIn: 12 * 60 + 20)], indicators: all, now: now))
        #expect(output.content.trailing?.text == "13 min")
        #expect(output.shownEventID == "reunión")
        // Pasa a "12 min" cuando falten exactamente 12 minutos.
        #expect(output.nextRefresh == now + 20)
    }

    @Test func distantEventIsHiddenUntilLeadTime() {
        let output = CompactContentBuilder.build(.init(events: [event("tarde", startsIn: 3 * 3_600)], indicators: all, now: now))
        #expect(output.content.isEmpty)
        #expect(output.nextRefresh == now + 3 * 3_600 - CompactContentBuilder.eventLeadTime)
    }

    @Test func justStartedEventShowsNowThenDisappears() {
        let started = CompactContentBuilder.build(.init(events: [event("daily", startsIn: -60)], indicators: all, now: now))
        #expect(started.content.trailing?.text == "ahora")
        #expect(started.nextRefresh == now - 60 + CompactContentBuilder.eventLingerTime)

        let longRunning = CompactContentBuilder.build(.init(events: [event("taller", startsIn: -3_600, lasts: 7_200)], indicators: all, now: now))
        #expect(longRunning.content.isEmpty)
    }

    @Test func upcomingEventWinsOverOneInProgress() {
        let events = [event("en curso", startsIn: -60), event("siguiente", startsIn: 300)]
        let output = CompactContentBuilder.build(.init(events: events, indicators: all, now: now))
        #expect(output.shownEventID == "siguiente")
        #expect(output.content.trailing?.text == "5 min")
    }

    @Test func allDayEventsNeverAppear() {
        let output = CompactContentBuilder.build(.init(events: [event("festivo", startsIn: 600, allDay: true)], indicators: all, now: now))
        #expect(output.content.isEmpty)
    }

    @Test func lowBatteryAppearsOnlyUnplugged() {
        let low = BatteryStatus(level: 0.18, isCharging: false, isPluggedIn: false)
        #expect(CompactContentBuilder.build(.init(battery: low, indicators: all, now: now)).content.trailing?.text == "18 %")

        let charging = BatteryStatus(level: 0.18, isCharging: true, isPluggedIn: true)
        #expect(CompactContentBuilder.build(.init(battery: charging, indicators: all, now: now)).content.isEmpty)

        let fine = BatteryStatus(level: 0.6, isCharging: false, isPluggedIn: false)
        #expect(CompactContentBuilder.build(.init(battery: fine, indicators: all, now: now)).content.isEmpty)
    }

    @Test func eventTakesTheTrailingSlotBeforeBattery() {
        let low = BatteryStatus(level: 0.1, isCharging: false, isPluggedIn: false)
        let output = CompactContentBuilder.build(.init(events: [event("ya", startsIn: 120)], battery: low, indicators: all, now: now))
        #expect(output.content.trailing?.systemImage == "calendar")
    }

    @Test func disabledIndicatorsAreIgnored() {
        let low = BatteryStatus(level: 0.1, isCharging: false, isPluggedIn: false)
        let output = CompactContentBuilder.build(.init(
            nowPlaying: track(playing: true), events: [event("ya", startsIn: 120)], battery: low, indicators: [], now: now
        ))
        #expect(output.content.isEmpty)
        #expect(output.nextRefresh == nil)
    }
}

@Suite struct EventCountdownTests {
    @Test func formatsEachPhase() {
        #expect(EventCountdown.text(for: .upcoming(startsIn: 30)) == "empieza ahora")
        #expect(EventCountdown.text(for: .upcoming(startsIn: 12 * 60)) == "en 12 min")
        #expect(EventCountdown.text(for: .upcoming(startsIn: 2 * 3_600)) == "en 2 h")
        #expect(EventCountdown.text(for: .upcoming(startsIn: 2 * 3_600 + 15 * 60)) == "en 2 h 15 min")
        #expect(EventCountdown.text(for: .upcoming(startsIn: 26 * 3_600)) == "en 1 día")
        #expect(EventCountdown.text(for: .upcoming(startsIn: 3 * 86_400)) == "en 3 días")
        #expect(EventCountdown.text(for: .inProgress(remaining: 600)) == "en curso · quedan 10 min")
    }
}

@Suite struct MusicScriptParserTests {
    let now = Date(timeIntervalSinceReferenceDate: 1)

    func list(_ items: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
        let list = NSAppleEventDescriptor.list()
        for (index, item) in items.enumerated() { list.insert(item, at: index + 1) }
        return list
    }

    @Test func parsesAPlayingTrack() throws {
        let descriptor = list([
            .init(boolean: true), .init(string: "Canción"), .init(string: "Artista"), .init(string: "Álbum"),
            .init(double: 215.5), .init(double: 42.25), .init(string: "ABC123"),
        ])
        let track = try #require(MusicScriptParser.nowPlaying(from: descriptor, player: .appleMusic, now: now))
        #expect(track.isPlaying)
        #expect(track.title == "Canción")
        #expect(track.artist == "Artista")
        #expect(track.album == "Álbum")
        #expect(track.duration == 215.5)
        #expect(track.position == 42.25)
        #expect(track.trackID == "ABC123")
        #expect(track.positionDate == now)
    }

    @Test func emptyListMeansNoTrack() {
        #expect(MusicScriptParser.nowPlaying(from: list([]), player: .appleMusic, now: now) == nil)
        #expect(MusicScriptParser.nowPlaying(from: .null(), player: .appleMusic, now: now) == nil)
    }

    @Test func streamWithoutDurationOrArtistIsStillValid() throws {
        let descriptor = list([
            .init(boolean: false), .init(string: "Radio"), .init(string: ""), .init(string: ""),
            .init(double: 0), .null(), .init(string: "ID"),
        ])
        let track = try #require(MusicScriptParser.nowPlaying(from: descriptor, player: .appleMusic, now: now))
        #expect(!track.isPlaying)
        #expect(track.artist == nil)
        #expect(track.duration == nil)
        #expect(track.position == 0)
        #expect(track.progress(at: now) == nil)
    }

    @Test func mapsAutomationAndScriptErrorCodes() {
        #expect(AppleScriptRunner.error(forCode: -1743) == .automationDenied)
        #expect(AppleScriptRunner.error(forCode: -600) == .playerNotRunning)
        #expect(AppleScriptRunner.error(forCode: -1728) == .scriptFailed(code: -1728))
        #expect(Automation.permission(forStatus: 0) == .granted)
        #expect(Automation.permission(forStatus: -1744) == .notDetermined)
        #expect(Automation.permission(forStatus: -1743) == .denied)
        #expect(Automation.permission(forStatus: -600) == .targetNotRunning)
    }
}

@MainActor
@Suite struct ApplicationServiceTests {
    func makeService() throws -> (ApplicationService, PreferencesStore, cleanup: () -> Void) {
        let suite = "NotchKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = PreferencesStore(defaults: defaults)
        return (ApplicationService(store: store), store, { defaults.removePersistentDomain(forName: suite) })
    }

    let safari = URL(fileURLWithPath: "/Applications/Safari.app")
    let calendar = URL(fileURLWithPath: "/System/Applications/Calendar.app")

    @Test func buildsFavoriteFromApplicationBundle() throws {
        let app = try #require(FavoriteApp(applicationURL: calendar))
        #expect(app.bundleIdentifier == "com.apple.iCal")
        #expect(!app.displayName.isEmpty)
        #expect(!app.displayName.hasSuffix(".app"))
        #expect(FavoriteApp(applicationURL: URL(fileURLWithPath: "/tmp")) == nil)
    }

    @Test func addsWithoutDuplicatesAndPersists() throws {
        let (service, store, cleanup) = try makeService()
        defer { cleanup() }
        service.add([calendar, safari])
        service.add([calendar])
        #expect(service.favorites.map(\.bundleIdentifier) == ["com.apple.iCal", "com.apple.Safari"])
        #expect(store.preferences.favorites.count == 2)
    }

    @Test func reordersAndRemoves() throws {
        let (service, _, cleanup) = try makeService()
        defer { cleanup() }
        service.add([calendar, safari])
        let first = try #require(service.favorites.first)
        service.move(first, by: 1)
        #expect(service.favorites.map(\.bundleIdentifier) == ["com.apple.Safari", "com.apple.iCal"])
        service.move(first, by: 1)  // ya es el último: no cambia
        #expect(service.favorites.last == first)
        service.remove(first)
        #expect(service.favorites.map(\.bundleIdentifier) == ["com.apple.Safari"])
    }

    @Test func resolvesInstalledAppsAndReportsMissingOnes() throws {
        let (service, _, cleanup) = try makeService()
        defer { cleanup() }
        let installed = try #require(FavoriteApp(applicationURL: calendar))
        #expect(service.url(for: installed) != nil)
        let missing = FavoriteApp(bundleIdentifier: "invalid.notchkit.missing", displayName: "Fantasma")
        #expect(service.url(for: missing) == nil)
        #expect(service.icon(for: missing).isValid)
    }
}

@MainActor
@Suite struct ActivityServiceTests {
    @Test func keepsNewestFirstAndCapsHistory() {
        let service = ActivityService()
        for index in 0..<(ActivityService.capacity + 5) {
            service.record(.trackChanged, title: "Pista \(index)")
        }
        #expect(service.items.count == ActivityService.capacity)
        #expect(service.items.first?.title == "Pista \(ActivityService.capacity + 4)")
        service.clear()
        #expect(service.items.isEmpty)
    }
}

@Suite struct MediaRemoteParsingTests {
    func line(_ json: String) -> Data { Data(json.utf8) }

    @Test func parsesFullAndDiffUpdates() throws {
        let full = try #require(MediaRemoteUpdate(line: line(#"""
        {"type":"data","diff":false,"payload":{"bundleIdentifier":"com.brave.Browser","title":"Video","artist":"Canal","playing":true,"playbackRate":1,"durationMicros":30293061000,"elapsedTimeMicros":50861625,"timestampEpochMicros":1791775209000000,"contentItemIdentifier":"ABC","artworkData":"iVBORw0KGgo="}}
        """#)))
        #expect(!full.isDiff)
        #expect(full.payload["playing"] == .bool(true))
        #expect(full.payload["playbackRate"] == .number(1))
        #expect(full.payload["artworkData"] == .data(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])))

        let diff = try #require(MediaRemoteUpdate(line: line(#"{"type":"data","diff":true,"payload":{"playing":false,"artist":null}}"#)))
        #expect(diff.isDiff)
        #expect(diff.payload["artist"] == .null)
    }

    @Test func rejectsUnrelatedOutput() {
        #expect(MediaRemoteUpdate(line: line("not json")) == nil)
        #expect(MediaRemoteUpdate(line: line(#"{"type":"other","payload":{}}"#)) == nil)
    }

    @Test func buildsNowPlayingFromAccumulatedState() throws {
        let state: [String: MediaRemoteValue] = [
            "bundleIdentifier": .string("com.apple.WebKit.GPU"),
            "parentApplicationBundleIdentifier": .string("com.apple.Safari"),
            "title": .string("Episodio"),
            "artist": .string(""),
            "playing": .bool(true),
            "playbackRate": .number(1),
            "durationMicros": .number(120_000_000),
            "elapsedTimeMicros": .number(30_000_000),
            "timestampEpochMicros": .number(1_000_000_000_000_000),
            "uniqueIdentifier": .string("U1"),
        ]
        let payload = try #require(MediaRemotePayload(state))
        #expect(payload.appBundleIdentifier == "com.apple.Safari")
        let track = payload.nowPlaying(player: PlayerID(bundleIdentifier: "com.apple.Safari", displayName: "Safari"))
        #expect(track.title == "Episodio")
        #expect(track.artist == nil)
        #expect(track.duration == 120)
        #expect(track.position == 30)
        #expect(track.positionDate == Date(timeIntervalSince1970: 1_000_000_000))
        #expect(track.trackID == "U1")
        #expect(track.isPlaying)
    }

    @Test func zeroPlaybackRateMeansPaused() throws {
        let state: [String: MediaRemoteValue] = [
            "bundleIdentifier": .string("com.spotify.client"), "title": .string("Canción"),
            "playing": .bool(true), "playbackRate": .number(0),
        ]
        #expect(try #require(MediaRemotePayload(state)).isPlaying == false)
    }

    @Test func emptyStateMeansNothingPlaying() {
        #expect(MediaRemotePayload([:]) == nil)
        #expect(MediaRemotePayload(["bundleIdentifier": .string("x")]) == nil)
    }

    @Test func lineReaderJoinsChunksAndSplitsLines() async {
        let collected = Collector()
        let reader = LineReader { collected.add($0) }
        let first = #"{"type":"data","diff":false,"payload":{"title":"A","bundleIdentifier":"x","playing":true}}"#
        let second = #"{"type":"data","diff":true,"payload":{"title":"B"}}"#
        let bytes = Array((first + "\n" + second + "\n").utf8)
        reader.append(Data(bytes[0..<20]))
        #expect(collected.count == 0)
        reader.append(Data(bytes[20...]))
        #expect(collected.count == 2)
    }

    final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var updates: [MediaRemoteUpdate] = []
        func add(_ update: MediaRemoteUpdate) { lock.withLock { updates.append(update) } }
        var count: Int { lock.withLock { updates.count } }
    }
}
