import CoreGraphics
import Foundation
import Testing
@testable import NotchKit

@Suite struct NotchLayoutTests {
    let layout = NotchLayout(
        geometry: NotchGeometry(screen: NotchGeometryTests.airM3),
        contentSize: CGSize(width: 560, height: 240),
        wingWidth: 92,
        maxWingWidth: 120
    )

    @Test func idleWindowIsExactlyTheNotch() {
        #expect(layout.windowFrame(for: .idle) == CGRect(x: 751, y: 1074, width: 209, height: 38))
    }

    @Test func compactWindowMatchesTheVisibleShape() {
        let frame = layout.windowFrame(for: .compact)
        #expect(frame == CGRect(x: 751 - 92, y: 1074, width: 209 + 184, height: 38))
        #expect(frame == layout.shapeFrame(for: .compact))
    }

    @Test func compactWingsRespectUserMaximum() {
        var narrow = layout
        narrow.maxWingWidth = 40
        #expect(narrow.windowFrame(for: .compact).width == 289)
    }

    @Test func expandedWindowAddsShadowMarginExceptOnTop() {
        let shape = layout.shapeFrame(for: .expanded(pinned: false))
        let window = layout.windowFrame(for: .expanded(pinned: true))
        #expect(window.maxY == shape.maxY)
        #expect(window.minY == shape.minY - NotchLayout.shadowMargin)
        #expect(window.width == shape.width + NotchLayout.shadowMargin * 2)
    }

    @Test func everyStateIsCenteredOnTheNotch() {
        let center = layout.geometry.notchRect.midX
        for state in [NotchStateMachine.State.idle, .compact, .expanded(pinned: false)] {
            #expect(abs(layout.shapeFrame(for: state).midX - center) <= 0.5)
            #expect(abs(layout.windowFrame(for: state).midX - center) <= 0.5)
        }
    }
}

@MainActor
@Suite struct NotchViewModelTests {
    func makeModel(_ configure: (inout Preferences) -> Void = { _ in }) throws -> (NotchViewModel, cleanup: () -> Void) {
        let suite = "NotchKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = PreferencesStore(defaults: defaults)
        configure(&store.preferences)
        let model = NotchViewModel(store: store, geometry: NotchGeometry(screen: NotchGeometryTests.airM3))
        return (model, { defaults.removePersistentDomain(forName: suite) })
    }

    @Test func clickExpandsAndNotifiesLayoutOnce() throws {
        let (model, cleanup) = try makeModel()
        defer { cleanup() }
        var notifications = 0
        model.onLayoutChange = { notifications += 1 }
        model.send(.clicked)
        #expect(model.state == .expanded(pinned: false))
        #expect(notifications == 1)
        model.send(.clicked)
        #expect(notifications == 1)
    }

    @Test func hoverExpandsAfterConfiguredDelay() async throws {
        let (model, cleanup) = try makeModel { $0.hoverOpenDelay = 0.05 }
        defer { cleanup() }
        model.send(.pointerEntered)
        #expect(model.state == .idle)
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.state.isExpanded)
    }

    @Test func leavingCancelsPendingOpen() async throws {
        let (model, cleanup) = try makeModel { $0.hoverOpenDelay = 0.05 }
        defer { cleanup() }
        model.send(.pointerEntered)
        model.send(.pointerExited)
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.state == .idle)
    }

    @Test func preferenceChangesApplyToTheNextEvent() throws {
        let (model, cleanup) = try makeModel()
        defer { cleanup() }
        model.store.preferences.opensOnHover = false
        model.store.preferences.opensOnClick = true
        model.send(.pointerEntered)
        #expect(model.state == .idle)
        model.send(.clicked)
        #expect(model.state.isExpanded)
    }

    @Test func compactContentDrivesStateAndWindowWidth() throws {
        let (model, cleanup) = try makeModel()
        defer { cleanup() }
        var notifications = 0
        model.onLayoutChange = { notifications += 1 }

        model.setCompactContent(CompactContent(leading: .init(systemImage: "music.note", accessibilityLabel: "")))
        #expect(model.state == .compact)
        #expect(model.windowFrame.width == 289)

        // Mismo estado, alas más anchas: la ventana debe enterarse igualmente.
        model.setCompactContent(CompactContent(trailing: .init(systemImage: "calendar", text: "5 min", accessibilityLabel: "")))
        #expect(model.windowFrame.width == 393)
        #expect(notifications == 2)

        model.setCompactContent(CompactContent())
        #expect(model.state == .idle)
    }

    @Test func openingSettingsCollapsesThePanel() throws {
        let (model, cleanup) = try makeModel()
        defer { cleanup() }
        var opened = false
        model.onOpenSettings = { _ in opened = true }
        model.send(.clicked)
        model.openSettings()
        #expect(opened)
        #expect(model.state == .idle)
    }
}
