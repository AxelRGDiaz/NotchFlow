import CoreGraphics
import Testing
@testable import NotchKit

@Suite struct NotchGeometryTests {
    /// Valores reales de un MacBook Air 13" M3 en modo escalado 1710×1112.
    static let airM3 = ScreenDescriptor(
        displayID: 1,
        frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
        safeAreaTop: 38,
        auxiliaryTopLeft: CGRect(x: 0, y: 1074, width: 751, height: 38),
        auxiliaryTopRight: CGRect(x: 960, y: 1074, width: 750, height: 38),
        menuBarHeight: 39,
        isBuiltIn: true
    )
    static let external = ScreenDescriptor(
        displayID: 2,
        frame: CGRect(x: 1710, y: 0, width: 2560, height: 1440),
        menuBarHeight: 25
    )

    @Test func detectsPhysicalNotch() {
        let g = NotchGeometry(screen: Self.airM3)
        #expect(g.hasPhysicalNotch)
        #expect(g.notchRect == CGRect(x: 751, y: 1074, width: 209, height: 38))
        #expect(g.leadingSpace == 751)
        #expect(g.trailingSpace == 750)
    }

    @Test func fallsBackToVirtualNotchOnScreensWithoutOne() {
        let g = NotchGeometry(screen: Self.external)
        #expect(!g.hasPhysicalNotch)
        #expect(g.notchRect.height == 25)
        #expect(g.notchRect.maxY == Self.external.frame.maxY)
        #expect(g.notchRect.midX == Self.external.frame.midX)
    }

    @Test func virtualNotchUsesDefaultHeightWhenMenuBarIsHidden() {
        var screen = Self.external
        screen.menuBarHeight = 0
        #expect(NotchGeometry(screen: screen).notchRect.height == 24)
    }

    @Test func prefersNotchedThenBuiltInThenFirstScreen() {
        var builtInNoNotch = Self.airM3
        builtInNoNotch.safeAreaTop = 0
        #expect(NotchGeometry.preferredScreen(from: [Self.external, Self.airM3]) == Self.airM3)
        #expect(NotchGeometry.preferredScreen(from: [Self.external, builtInNoNotch]) == builtInNoNotch)
        #expect(NotchGeometry.preferredScreen(from: [Self.external]) == Self.external)
        #expect(NotchGeometry.preferredScreen(from: []) == nil)
    }

    @Test func compactFrameWithoutWingsIsExactlyTheNotch() {
        let g = NotchGeometry(screen: Self.airM3)
        #expect(g.compactFrame(leadingWing: 0, trailingWing: 0, maxWing: 120) == g.notchRect)
    }

    @Test func compactWingsAreClampedToMaximum() {
        let g = NotchGeometry(screen: Self.airM3)
        let frame = g.compactFrame(leadingWing: 500, trailingWing: 40, maxWing: 120)
        #expect(frame == CGRect(x: 631, y: 1074, width: 209 + 120 + 40, height: 38))
        #expect(g.compactFrame(leadingWing: -10, trailingWing: -10, maxWing: 120) == g.notchRect)
    }

    @Test func expandedFrameHangsFromTopCenteredOnNotch() {
        let g = NotchGeometry(screen: Self.airM3)
        let frame = g.expandedFrame(contentSize: CGSize(width: 560, height: 240))
        #expect(frame.maxY == 1112)
        #expect(frame.height == 278)
        #expect(frame.width == 560)
        #expect(abs(frame.midX - g.notchRect.midX) <= 0.5)
    }

    @Test func expandedFrameStaysInsideTheScreen() {
        let narrow = ScreenDescriptor(displayID: 3, frame: CGRect(x: 100, y: 0, width: 400, height: 300))
        let frame = NotchGeometry(screen: narrow).expandedFrame(contentSize: CGSize(width: 680, height: 500))
        #expect(narrow.frame.contains(frame))
    }
}
