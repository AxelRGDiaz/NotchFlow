import Foundation
import Testing
@testable import NotchKit

@Suite struct PreferencesTests {
    @Test func roundTripsThroughJSON() throws {
        var prefs = Preferences()
        prefs.moduleOrder = [.calendar, .music, .apps, .quickControls, .activity]
        prefs.hiddenModules = [.activity]
        prefs.panelSize = .large
        prefs.appearance = .dark
        prefs.favorites = [FavoriteApp(bundleIdentifier: "com.apple.Safari", displayName: "Safari")]
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs))
        #expect(decoded == prefs)
        #expect(decoded.visibleModules == [.calendar, .music, .apps, .quickControls])
    }

    @Test func missingAndUnknownValuesKeepDefaults() throws {
        let json = #"{"panelSize":"gigantic","opensOnHover":false,"moduleOrder":["calendar","hologram"]}"#
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        #expect(prefs.panelSize == .medium)
        #expect(prefs.opensOnHover == false)
        #expect(prefs.moduleOrder == ModuleID.allCases)
        #expect(prefs.closeDelay == Preferences().closeDelay)
    }

    @Test func normalizationRepairsInconsistentData() {
        var prefs = Preferences()
        prefs.moduleOrder = [.apps, .apps, .music]
        prefs.opensOnHover = false
        prefs.opensOnClick = false
        prefs.animationDuration = 30
        prefs.hoverOpenDelay = -1
        let app = FavoriteApp(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
        prefs.favorites = [app, app, FavoriteApp(bundleIdentifier: "", displayName: "?")]

        let fixed = prefs.normalized()
        #expect(fixed.moduleOrder == [.apps, .music, .calendar, .quickControls, .activity])
        #expect(fixed.opensOnClick)
        #expect(fixed.animationDuration == 1)
        #expect(fixed.hoverOpenDelay == 0)
        #expect(fixed.favorites == [app])
    }

    @MainActor
    @Test func storePersistsAndRestores() throws {
        let suite = "NotchKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(defaults: defaults)
        #expect(store.preferences == Preferences())
        store.preferences.panelSize = .small
        store.preferences.favorites.append(FavoriteApp(bundleIdentifier: "com.apple.Music", displayName: "Music"))

        let reopened = PreferencesStore(defaults: defaults)
        #expect(reopened.preferences.panelSize == .small)
        #expect(reopened.preferences.favorites.map(\.bundleIdentifier) == ["com.apple.Music"])
    }

    @MainActor
    @Test func storeRecoversFromCorruptData() throws {
        let suite = "NotchKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("no es json".utf8), forKey: PreferencesStore.defaultKey)
        #expect(PreferencesStore(defaults: defaults).preferences == Preferences())
    }
}

@Suite struct NowPlayingTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    func track(playing: Bool, duration: TimeInterval? = 200) -> NowPlaying {
        NowPlaying(player: .appleMusic, title: "Pista", duration: duration, isPlaying: playing, position: 50, positionDate: t0)
    }

    @Test func positionAdvancesOnlyWhilePlaying() {
        #expect(track(playing: true).position(at: t0 + 30) == 80)
        #expect(track(playing: false).position(at: t0 + 30) == 50)
    }

    @Test func positionIsClampedToDuration() {
        #expect(track(playing: true).position(at: t0 + 1_000) == 200)
        #expect(track(playing: true).position(at: t0 - 10) == 50)
    }

    @Test func progressIsNilWithoutDuration() {
        #expect(track(playing: true).progress(at: t0 + 50) == 0.5)
        #expect(track(playing: true, duration: nil).progress(at: t0) == nil)
    }
}

@Suite struct EventTimelineTests {
    let now = Date(timeIntervalSinceReferenceDate: 10_000)

    func event(_ id: String, from start: TimeInterval, to end: TimeInterval, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, title: id, start: now + start, end: now + end, isAllDay: allDay)
    }

    @Test func phaseReflectsCurrentTime() {
        #expect(event("a", from: 600, to: 1_200).phase(at: now) == .upcoming(startsIn: 600))
        #expect(event("b", from: -60, to: 300).phase(at: now) == .inProgress(remaining: 300))
        #expect(event("c", from: -600, to: 0).phase(at: now) == .ended)
    }

    @Test func currentOrNextSkipsEndedAndAllDayEvents() {
        let events = [
            event("pasado", from: -3_600, to: -1_800),
            event("todo el día", from: -10_000, to: 70_000, allDay: true),
            event("tarde", from: 7_200, to: 9_000),
            event("pronto", from: 900, to: 1_800),
        ]
        #expect(EventTimeline.currentOrNext(in: events, at: now)?.id == "pronto")
        #expect(EventTimeline.currentOrNext(in: [events[0], events[1]], at: now) == nil)
    }

    @Test func inProgressEventWinsOverUpcoming() {
        let events = [event("pronto", from: 900, to: 1_800), event("en curso", from: -300, to: 600)]
        #expect(EventTimeline.currentOrNext(in: events, at: now)?.id == "en curso")
    }

    @Test func nextBoundaryIsEarliestFutureStartOrEnd() {
        let events = [event("en curso", from: -300, to: 600), event("pronto", from: 900, to: 1_800)]
        #expect(EventTimeline.nextBoundary(in: events, after: now) == now + 600)
        #expect(EventTimeline.nextBoundary(in: [], after: now) == nil)
    }

    @Test func eventsOnDayListsAllDayFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let dayStart = calendar.startOfDay(for: now)
        let events = [
            CalendarEvent(id: "tarde", title: "", start: dayStart + 50_000, end: dayStart + 53_600),
            CalendarEvent(id: "mañana", title: "", start: dayStart + 30_000, end: dayStart + 33_600),
            CalendarEvent(id: "día", title: "", start: dayStart, end: dayStart + 86_400, isAllDay: true),
            CalendarEvent(id: "ayer", title: "", start: dayStart - 7_200, end: dayStart - 3_600),
        ]
        #expect(EventTimeline.events(on: now, in: events, calendar: calendar).map(\.id) == ["día", "mañana", "tarde"])
    }
}
