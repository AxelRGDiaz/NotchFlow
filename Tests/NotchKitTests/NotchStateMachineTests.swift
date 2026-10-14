import Testing
@testable import NotchKit

@Suite struct NotchStateMachineTests {
    typealias Machine = NotchStateMachine

    @Test func hoverSchedulesOpenAndExpandsWhenDelayElapses() {
        var m = Machine()
        #expect(m.handle(.pointerEntered) == [.scheduleOpen(after: 0.25)])
        #expect(m.state == .idle)
        #expect(m.handle(.openDelayElapsed) == [])
        #expect(m.state == .expanded(pinned: false))
    }

    @Test func leavingBeforeDelayCancelsOpen() {
        var m = Machine()
        _ = m.handle(.pointerEntered)
        #expect(m.handle(.pointerExited) == [.cancelOpen])
        // Aunque el temporizador llegue tarde, no debe abrir.
        _ = m.handle(.openDelayElapsed)
        #expect(m.state == .idle)
    }

    @Test func zeroHoverDelayExpandsImmediately() {
        var m = Machine(config: .init(hoverOpenDelay: 0))
        #expect(m.handle(.pointerEntered) == [])
        #expect(m.state.isExpanded)
    }

    @Test func hoverDisabledRequiresClick() {
        var m = Machine(config: .init(opensOnHover: false))
        #expect(m.handle(.pointerEntered) == [])
        #expect(m.state == .idle)
        #expect(m.handle(.clicked) == [.cancelOpen])
        #expect(m.state.isExpanded)
    }

    @Test func clickDisabledIsIgnored() {
        var m = Machine(config: .init(opensOnClick: false))
        _ = m.handle(.clicked)
        #expect(m.state == .idle)
    }

    @Test func pointerExitClosesAfterDelayUnlessPointerReturns() {
        var m = Machine()
        _ = m.handle(.clicked)
        #expect(m.handle(.pointerExited) == [.scheduleClose(after: 0.6)])
        #expect(m.handle(.pointerEntered) == [.cancelClose])
        _ = m.handle(.closeDelayElapsed)
        #expect(m.state.isExpanded)

        _ = m.handle(.pointerExited)
        _ = m.handle(.closeDelayElapsed)
        #expect(m.state == .idle)
    }

    @Test func pinnedPanelIgnoresPointerExitButNotDismiss() {
        var m = Machine()
        _ = m.handle(.clicked)
        #expect(m.handle(.pinToggled) == [.cancelClose])
        #expect(m.handle(.pointerExited) == [])
        _ = m.handle(.closeDelayElapsed)
        #expect(m.state == .expanded(pinned: true))
        _ = m.handle(.dismissRequested)
        #expect(m.state == .idle)
    }

    @Test func unpinningWithPointerOutsideSchedulesClose() {
        var m = Machine()
        _ = m.handle(.toggleRequested)
        _ = m.handle(.pinToggled)
        #expect(m.handle(.pinToggled) == [.scheduleClose(after: 0.6)])
    }

    @Test func staysOpenOnExitWhenConfigured() {
        var m = Machine(config: .init(closesOnPointerExit: false))
        _ = m.handle(.clicked)
        #expect(m.handle(.pointerExited) == [])
        #expect(m.state.isExpanded)
    }

    @Test func activityTogglesBetweenIdleAndCompact() {
        var m = Machine()
        _ = m.handle(.activityChanged(hasActivity: true))
        #expect(m.state == .compact)
        _ = m.handle(.activityChanged(hasActivity: false))
        #expect(m.state == .idle)
    }

    @Test func collapsingReturnsToCompactWhileThereIsActivity() {
        var m = Machine()
        _ = m.handle(.toggleRequested)
        _ = m.handle(.activityChanged(hasActivity: true))
        #expect(m.state.isExpanded)
        _ = m.handle(.toggleRequested)
        #expect(m.state == .compact)
    }
}
