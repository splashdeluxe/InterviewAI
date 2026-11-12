import Foundation
import Testing
@testable import InterviewAIKit

@Test("A drag with no pointer movement keeps the window origin")
func dragNoMovement() {
    let origin = CGPoint(x: 800, y: 600)
    #expect(PanelDrag.movedOrigin(startOrigin: origin, startMouse: CGPoint(x: 900, y: 700), mouse: CGPoint(x: 900, y: 700)) == origin)
}

@Test("The window follows the pointer delta exactly, both directions")
func dragFollowsDelta() {
    let moved = PanelDrag.movedOrigin(
        startOrigin: CGPoint(x: 800, y: 600),
        startMouse: CGPoint(x: 900, y: 700),
        mouse: CGPoint(x: 850, y: 760)
    )
    #expect(moved == CGPoint(x: 750, y: 660))
}

@Test("The grab point stays under the cursor: origin plus grab offset is the pointer")
func dragKeepsGrabPoint() {
    let startOrigin = CGPoint(x: 100, y: 200)
    let startMouse = CGPoint(x: 130, y: 260) // grabbed 30 right, 60 up from the origin
    let mouse = CGPoint(x: 400, y: 500)
    let moved = PanelDrag.movedOrigin(startOrigin: startOrigin, startMouse: startMouse, mouse: mouse)
    #expect(moved.x + 30 == mouse.x)
    #expect(moved.y + 60 == mouse.y)
}

@Test("The header band is the top of the window, not the middle or bottom")
func headerBandTopOnly() {
    #expect(PanelDrag.isInHeaderBand(y: 520, contentHeight: 520))
    #expect(PanelDrag.isInHeaderBand(y: 480, contentHeight: 520))
    #expect(!PanelDrag.isInHeaderBand(y: 470, contentHeight: 520))
    #expect(!PanelDrag.isInHeaderBand(y: 0, contentHeight: 520))
}

@Test("A collapsed window is all header; points outside the window never count")
func headerBandCollapsedAndOutside() {
    #expect(PanelDrag.isInHeaderBand(y: 20, contentHeight: 58))
    #expect(PanelDrag.isInHeaderBand(y: 58, contentHeight: 58))
    #expect(!PanelDrag.isInHeaderBand(y: 600, contentHeight: 520))
    #expect(!PanelDrag.isInHeaderBand(y: -5, contentHeight: 520))
}

@Test("A press on a reported button frame does not start a drag")
func dragSkipsButtonFrames() {
    let stopButton = CGRect(x: 400, y: 486, width: 64, height: 24)
    #expect(!PanelDrag.shouldStartDrag(point: CGPoint(x: 420, y: 498), contentHeight: 520, exclusions: [stopButton]))
    #expect(PanelDrag.shouldStartDrag(point: CGPoint(x: 60, y: 498), contentHeight: 520, exclusions: [stopButton]))
}

@Test("The padding around a button counts as the button")
func dragSkipsButtonPadding() {
    let closeButton = CGRect(x: 500, y: 486, width: 24, height: 24)
    // 4 points left of the button's edge: inside the 6 point pad.
    #expect(!PanelDrag.shouldStartDrag(point: CGPoint(x: 496, y: 498), contentHeight: 520, exclusions: [closeButton]))
    // 10 points left: clear of the pad, a normal drag.
    #expect(PanelDrag.shouldStartDrag(point: CGPoint(x: 490, y: 498), contentHeight: 520, exclusions: [closeButton]))
}

@Test("Below the header band nothing drags, exclusions or not")
func dragOnlyInBand() {
    #expect(!PanelDrag.shouldStartDrag(point: CGPoint(x: 60, y: 300), contentHeight: 520, exclusions: []))
    #expect(PanelDrag.shouldStartDrag(point: CGPoint(x: 60, y: 510), contentHeight: 520, exclusions: []))
}
