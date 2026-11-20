import SwiftUI

/// The rail's drawn glyphs, ported from run 1 of the icon
/// workflow: generated as animated SVG prototypes, picked,
/// and rebuilt here as native shapes. Each glyph draws in
/// a 32-unit space and strokes in its tint, so it follows
/// the rail's selected and hover states and both
/// appearances the way the SF Symbols did. At rest every
/// glyph is complete and still. On hover the moves play
/// inside the glyph: the waveform ripples, the clock's
/// hand sweeps, the arcs radiate, the document's lines
/// redraw. The card's tip and the magnifier's search stay
/// whole-glyph moves, applied by the rail button around
/// this view, as they were in the prototype.
struct RailGlyph: View {
    let page: SidebarItem
    let hovered: Bool
    let playCount: Int
    let reduceMotion: Bool
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 32
            ZStack {
                switch page {
                case .live:
                    WaveformGlyph(hovered: hovered, reduceMotion: reduceMotion, tint: tint, unit: unit)
                case .meetings:
                    ClockGlyph(playCount: playCount, reduceMotion: reduceMotion, tint: tint, unit: unit)
                case .modes:
                    ModesGlyph(hovered: hovered, reduceMotion: reduceMotion, tint: tint, unit: unit)
                case .context:
                    DocGlyph(playCount: playCount, reduceMotion: reduceMotion, tint: tint, unit: unit)
                case .intelligence:
                    CardGlyph(tint: tint, unit: unit)
                case .ask:
                    GlassGlyph(tint: tint, unit: unit)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// The corner menu's glyph, drawn the same way: three
/// lines in the glyphs' 32-unit space. On hover the
/// lines stagger, the outer two sliding one way and the
/// middle the other, on the rail's glide. It lays out at
/// a fixed size instead of reading one through a
/// GeometryReader, so it stays a plain fixed label.
struct MenuGlyph: View {
    let hovered: Bool
    let reduceMotion: Bool
    let tint: Color

    /// The glyph only ever sits in the menu button's
    /// 28 pt frame, so its unit is that frame over 32.
    private let unit: CGFloat = 28.0 / 32.0

    var body: some View {
        ZStack {
            line(dy: -5.5, dx: slide(-2))
            line(dy: 0, dx: slide(2))
            line(dy: 5.5, dx: slide(-2))
        }
        .frame(width: 28, height: 28)
        .animation(RailTiming.glide, value: hovered)
        .accessibilityHidden(true)
    }

    private func slide(_ amount: CGFloat) -> CGFloat {
        hovered && !reduceMotion ? amount : 0
    }

    private func line(dy: CGFloat, dx: CGFloat) -> some View {
        Capsule()
            .fill(tint)
            .frame(width: unit * 14, height: unit * 2.4)
            .offset(x: unit * dx, y: unit * dy) // grid: ok the offsets place the lines inside the drawn glyph's 32-unit space
    }
}

/// A stroked path drawn in the glyphs' 32-unit space: the
/// builder works in design coordinates and the shape
/// scales them into whatever frame it is given. The
/// struct is nonisolated with a sendable builder so its
/// Shape conformance stays out of the main actor, as the
/// compiler requires.
private nonisolated struct GlyphPath: Shape {
    let build: @Sendable (inout Path) -> Void

    func path(in rect: CGRect) -> Path {
        var path = Path()
        build(&path)
        let scale = rect.width / 32
        return path.applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}

/// Live: five bars. While hovered they ripple in sequence
/// on the prototype's 2.6 second cycle; at rest they stand
/// at full height.
private struct WaveformGlyph: View {
    let hovered: Bool
    let reduceMotion: Bool
    let tint: Color
    let unit: CGFloat

    private let heights: [CGFloat] = [8, 14, 20, 12, 7]

    var body: some View {
        if hovered && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                bars(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            bars(at: nil)
        }
    }

    private func bars(at time: Double?) -> some View {
        HStack(spacing: unit * 3.3) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(tint)
                    .frame(width: unit * 2.2, height: unit * heights[index])
                    .scaleEffect(y: scale(index: index, time: time), anchor: .center)
            }
        }
    }

    private func scale(index: Int, time: Double?) -> CGFloat {
        guard let time else { return 1 }
        let phase = 2 * Double.pi * (time - 0.18 * Double(index)) / 2.6
        return CGFloat(0.725 - 0.275 * cos(phase))
    }
}

/// Meetings: a clock. The minute hand sweeps one full
/// turn per play, slow and smooth; the hour hand rests
/// at twenty past, as drawn in the prototype.
private struct ClockGlyph: View {
    let playCount: Int
    let reduceMotion: Bool
    let tint: Color
    let unit: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint, lineWidth: unit * 2.2)
                .frame(width: unit * 22, height: unit * 22)
            GlyphPath { path in
                path.move(to: CGPoint(x: 16, y: 16))
                path.addLine(to: CGPoint(x: 21, y: 18.5))
            }
            .stroke(tint, style: StrokeStyle(lineWidth: unit * 2.2, lineCap: .round))
            if reduceMotion {
                minuteHand(angle: 0)
            } else {
                // The third phase resets to zero in a blink:
                // at 360 the hand points the same way, so the
                // reset is invisible and the next play sweeps
                // from rest again.
                PhaseAnimator([0.0, 360.0, 0.0], trigger: playCount) { angle in
                    minuteHand(angle: angle)
                } animation: { angle in
                    angle == 360 ? .easeInOut(duration: 1.6) : .linear(duration: 0.01)
                }
            }
            Circle()
                .fill(tint)
                .frame(width: unit * 2.8, height: unit * 2.8)
        }
    }

    private func minuteHand(angle: Double) -> some View {
        ZStack {
            Capsule()
                .fill(tint)
                .frame(width: unit * 2.2, height: unit * 6.5)
                .offset(y: -unit * 3.25) // grid: ok the offset places a part inside the drawn glyph's 32-unit space
        }
        .frame(width: unit * 32, height: unit * 32)
        .rotationEffect(.degrees(angle))
    }
}

/// Modes: a person with two arcs beside them. While
/// hovered the arcs radiate, fading out and back in
/// sequence on the prototype's 2.8 second cycle; at
/// rest they stand at full strength.
private struct ModesGlyph: View {
    let hovered: Bool
    let reduceMotion: Bool
    let tint: Color
    let unit: CGFloat

    var body: some View {
        if hovered && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                glyph(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            glyph(at: nil)
        }
    }

    private func glyph(at time: Double?) -> some View {
        ZStack {
            Circle()
                .stroke(tint, lineWidth: unit * 2.2)
                .frame(width: unit * 8, height: unit * 8)
                .offset(x: -unit * 4.5, y: -unit * 5.5) // grid: ok the offset places a part inside the drawn glyph's 32-unit space
            GlyphPath { path in
                path.move(to: CGPoint(x: 4.5, y: 27))
                path.addCurve(to: CGPoint(x: 11.5, y: 20.5),
                              control1: CGPoint(x: 5.3, y: 22.8),
                              control2: CGPoint(x: 7.9, y: 20.5))
                path.addCurve(to: CGPoint(x: 18.5, y: 27),
                              control1: CGPoint(x: 15.1, y: 20.5),
                              control2: CGPoint(x: 17.7, y: 22.8))
            }
            .stroke(tint, style: StrokeStyle(lineWidth: unit * 2.2, lineCap: .round))
            arc(radius: 4.5)
                .opacity(arcOpacity(index: 0, time: time))
            arc(radius: 8)
                .opacity(arcOpacity(index: 1, time: time))
        }
    }

    private func arc(radius: CGFloat) -> some View {
        // The clockwise flag reads backwards in this
        // y-down space: false is what bulges the arc away
        // from the person, as drawn in run 1. True wraps it
        // through the figure instead. The pair sits a
        // little further from the head than run 1 had them,
        // and smaller: Nils read the first port's waves as
        // too big and too close to the mouth.
        GlyphPath { path in
            path.addArc(center: CGPoint(x: 23.5, y: 14.5),
                        radius: radius,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(90),
                        clockwise: false)
        }
        .stroke(tint, style: StrokeStyle(lineWidth: unit * 2.2, lineCap: .round))
    }

    private func arcOpacity(index: Int, time: Double?) -> Double {
        guard let time else { return 1 }
        let phase = 2 * Double.pi * (time - 0.4 * Double(index)) / 2.8
        return 0.575 - 0.425 * cos(phase)
    }
}

/// One step of the document's redraw: how far each of
/// its two text lines is drawn.
private struct DocPhase: Equatable {
    var first: Double
    var second: Double

    static let rest = DocPhase(first: 1, second: 1)
    static let wiped = DocPhase(first: 0, second: 0)
    static let firstDrawn = DocPhase(first: 1, second: 0)
}

/// Context: a document with a folded corner. Per play
/// its lines wipe and redraw one after the other; at
/// rest they stand drawn.
private struct DocGlyph: View {
    let playCount: Int
    let reduceMotion: Bool
    let tint: Color
    let unit: CGFloat

    var body: some View {
        ZStack {
            GlyphPath { path in
                path.move(to: CGPoint(x: 9, y: 3.5))
                path.addLine(to: CGPoint(x: 19.5, y: 3.5))
                path.addLine(to: CGPoint(x: 24, y: 8))
                path.addLine(to: CGPoint(x: 24, y: 28.5))
                path.addLine(to: CGPoint(x: 9, y: 28.5))
                path.closeSubpath()
                path.move(to: CGPoint(x: 19.5, y: 3.5))
                path.addLine(to: CGPoint(x: 19.5, y: 8))
                path.addLine(to: CGPoint(x: 24, y: 8))
            }
            .stroke(tint, style: StrokeStyle(lineWidth: unit * 2.2, lineCap: .round, lineJoin: .round))
            if reduceMotion {
                lines(first: 1, second: 1)
            } else {
                PhaseAnimator([DocPhase.rest, .wiped, .firstDrawn, .rest], trigger: playCount) { phase in
                    lines(first: phase.first, second: phase.second)
                } animation: { phase in
                    phase == .wiped ? .linear(duration: 0.16) : .easeInOut(duration: 0.5)
                }
            }
        }
    }

    private func lines(first: Double, second: Double) -> some View {
        ZStack {
            line(from: CGPoint(x: 12.5, y: 15), to: CGPoint(x: 21, y: 15))
                .trim(from: 0, to: first)
                .stroke(tint, style: StrokeStyle(lineWidth: unit * 2.2, lineCap: .round))
            line(from: CGPoint(x: 12.5, y: 20.5), to: CGPoint(x: 18, y: 20.5))
                .trim(from: 0, to: second)
                .stroke(tint, style: StrokeStyle(lineWidth: unit * 2.2, lineCap: .round))
        }
    }

    private func line(from: CGPoint, to: CGPoint) -> GlyphPath {
        GlyphPath { path in
            path.move(to: from)
            path.addLine(to: to)
        }
    }
}

/// Profile: an identity card, person on the left, two
/// text lines on the right. The rail button tips the
/// whole glyph, as the prototype tipped the whole card.
private struct CardGlyph: View {
    let tint: Color
    let unit: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: unit * 2.5, style: .continuous)
                .stroke(tint, lineWidth: unit * 2.2)
                .frame(width: unit * 24, height: unit * 16)
            Circle()
                .stroke(tint, lineWidth: unit * 2.2)
                .frame(width: unit * 5.2, height: unit * 5.2)
                .offset(x: -unit * 4.5, y: -unit * 1.5) // grid: ok the offset places a part inside the drawn glyph's 32-unit space
            GlyphPath { path in
                path.move(to: CGPoint(x: 7.8, y: 21))
                path.addCurve(to: CGPoint(x: 11.5, y: 17.8),
                              control1: CGPoint(x: 8.3, y: 18.9),
                              control2: CGPoint(x: 10.4, y: 17.8))
                path.addCurve(to: CGPoint(x: 15.2, y: 21),
                              control1: CGPoint(x: 12.6, y: 17.8),
                              control2: CGPoint(x: 14.7, y: 18.9))
                path.move(to: CGPoint(x: 18.5, y: 13.5))
                path.addLine(to: CGPoint(x: 24.5, y: 13.5))
                path.move(to: CGPoint(x: 18.5, y: 18))
                path.addLine(to: CGPoint(x: 24.5, y: 18))
            }
            .stroke(tint, style: StrokeStyle(lineWidth: unit * 2.2, lineCap: .round))
        }
    }
}

/// Ask: a magnifier. The rail button moves the whole
/// glyph in its small searching loop.
private struct GlassGlyph: View {
    let tint: Color
    let unit: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint, lineWidth: unit * 2.2)
                .frame(width: unit * 14, height: unit * 14)
                .offset(x: -unit * 2, y: -unit * 2) // grid: ok the offset places a part inside the drawn glyph's 32-unit space
            GlyphPath { path in
                path.move(to: CGPoint(x: 19.3, y: 19.3))
                path.addLine(to: CGPoint(x: 26, y: 26))
            }
            .stroke(tint, style: StrokeStyle(lineWidth: unit * 2.2, lineCap: .round))
        }
    }
}
