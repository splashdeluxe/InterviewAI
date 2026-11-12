import Foundation

/// The maths behind dragging the overlay panel by its header.
/// Kept pure and in the Kit so the behaviour is testable: the
/// AppKit side only has to feed it points.
///
/// Two rounds of issue #3 failed on event delivery inside the
/// non-activating panel (a SwiftUI gesture, then an AppKit
/// performDrag in a representable view). Round 3 watches the
/// events themselves, before any view sees them, and moves the
/// window by hand. The window follows the pointer's screen-space
/// delta exactly, so the spot the user grabbed stays under the
/// cursor for the whole drag: direct manipulation, 1:1.
public enum PanelDrag {
    /// The header band height: a press this close to the top of
    /// the window's content starts a drag (unless it lands on a
    /// control, which the caller checks first).
    public static let headerBandHeight: CGFloat = 46

    /// New window origin for a drag that started with the pointer
    /// at `startMouse` and the window at `startOrigin`, with the
    /// pointer now at `mouse`. Screen coordinates throughout.
    public static func movedOrigin(startOrigin: CGPoint, startMouse: CGPoint, mouse: CGPoint) -> CGPoint {
        CGPoint(
            x: startOrigin.x + (mouse.x - startMouse.x),
            y: startOrigin.y + (mouse.y - startMouse.y)
        )
    }

    /// Whether a y position (AppKit window coordinates, origin at
    /// the bottom left) falls in the header band at the top of a
    /// window whose content is `contentHeight` tall. A window no
    /// taller than the band (the collapsed overlay) is all header.
    public static func isInHeaderBand(y: CGFloat, contentHeight: CGFloat, bandHeight: CGFloat = headerBandHeight) -> Bool {
        guard y >= 0, y <= contentHeight else { return false }
        return y >= contentHeight - bandHeight
    }
}

extension PanelDrag {
    /// Breathing room around a reported control frame: a press a
    /// few points off the visible button still counts as aiming
    /// at the button, not at the drag surface.
    public static let exclusionPadding: CGFloat = 6

    /// Whether a press starts a drag: inside the header band and
    /// clear of every exclusion rect. The exclusions exist because
    /// the header's buttons are SwiftUI views, not NSControls, so
    /// the event monitor cannot spot them in the hit chain (round
    /// 3's blind spot: the drag worked, the header buttons were
    /// swallowed as drags). The view therefore reports its own
    /// button frames, and this stays a pure, testable decision.
    /// Point and rects are AppKit content coordinates (y up).
    public static func shouldStartDrag(point: CGPoint, contentHeight: CGFloat, exclusions: [CGRect]) -> Bool {
        guard isInHeaderBand(y: point.y, contentHeight: contentHeight) else { return false }
        return !exclusions.contains {
            $0.insetBy(dx: -exclusionPadding, dy: -exclusionPadding).contains(point)
        }
    }
}
