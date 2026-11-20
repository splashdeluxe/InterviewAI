import InterviewAIKit
import SwiftUI

/// The design system for the redesign (docs/DESIGN.md).
///
/// Direction: Achromatic Ledger, adapted to a native Mac app. The chrome
/// holds no color. The one hue is the accent the user picked in Settings,
/// and it is spent on data only: the live answer rail, the "Me" speaker
/// label, the active mode check. Type is the system font, as Apple ships
/// it.
///
/// Motion, the literal round (2026-11-20): the user asked for all 19
/// animation principles in, literally, instead of the old fade-only
/// rule. So surfaces now carry real volume, presses squash and stretch,
/// things grow from where they were tapped, lists stagger in, and the
/// status dot pulses. Two limits still hold, because the principles
/// themselves demand them: nothing runs over MotionSpec.uiLimit
/// (300 ms, the Timing principle, well inside the 400 ms Doherty
/// threshold), and reduced motion flattens every effect back down.
enum Surface {
    /// The window ground: a Cool Blue wash in light mode, a deep plum
    /// step under the panels in dark mode (trend palette, 2026-11-12).
    static let canvas = Color(light: 0xE8F4FC, dark: 0x241419)
    /// Panels on the canvas. Plum Noir itself in dark mode.
    static let panel = Color(light: 0xFFFFFF, dark: 0x351E28)
    /// A filled control or a selected row.
    static let inset = Color(light: 0xDCEBF5, dark: 0x422630)
    /// The resting fill of a button: white in light mode (it pops on the
    /// Cool Blue canvas and reads by its border on white panels), a clear
    /// two-step lift over the plum panel in dark mode. Buttons filled
    /// with `inset` vanished into the trend surfaces (2026-11-12).
    static let control = Color(light: 0xFFFFFF, dark: 0x57384A)
    /// The border that carries a control on a same-tone ground.
    static let controlBorder = Color(light: 0x141414, dark: 0xFFFFFF).opacity(0.16)
    /// The near-black of the one primary action. White in dark mode.
    static let ink = Color(light: 0x141414, dark: 0xF2F2F7)
    /// Text on the ink action.
    static let onInk = Color(light: 0xFFFFFF, dark: 0x17181A)
    /// A 1 pt split between surfaces.
    static let hairline = Color.primary.opacity(0.09)
    /// Recording red. Used for the status dot only.
    static let live = Color.red
}

enum Radius {
    static let control: CGFloat = 6
    static let card: CGFloat = 8
    static let overlay: CGFloat = 20
}

/// Every animation the app uses, in one place.
///
/// Interruptible motion: every value here is a plain SwiftUI
/// `Animation`, so a new state change retargets a running animation
/// instead of queueing behind it, and none of them ever blocks input.
/// They are applied with `.animation(_:value:)`, never with a
/// `withAnimation` block that other work has to wait on.
///
/// Frequency of use: how much animation a moment earns depends on how
/// often it happens. Keyboard actions get none, frequent actions get
/// the press only, occasional surfaces get pops and sheets, and the
/// exaggerated spring is saved for rare, first-time moments.
enum Motion {
    /// Button press feedback: 120 ms, out fast.
    static let press = Animation.easeOut(duration: MotionSpec.pressDuration)

    /// A content swap (an answer arriving, a placeholder leaving).
    /// Under 200 ms. Reduced motion keeps the fade and drops the
    /// curve, since there is no movement to drop.
    static func contentSwap(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.15)
            : .timingCurve(0.23, 1, 0.32, 1, duration: MotionSpec.swapDuration)
    }

    /// Origin awareness, as an animation: a surface grows out of
    /// where it was summoned from. The anchor itself rides on the
    /// transition (see `motionPop(anchor:)`); this is the timing —
    /// a quick ease-out pop, scale from 0.95 with a fade, never
    /// from scale(0), because nothing in the world appears from
    /// nothing.
    static let pop = Animation.easeOut(duration: MotionSpec.popDuration)

    /// Slow in, slow out: a sheet or a page settles at both ends
    /// instead of snapping at one of them. The longest standard
    /// animation in the app, still under the 300 ms Timing limit.
    static let sheet = Animation.easeInOut(duration: MotionSpec.sheetDuration)

    /// Rubber banding and follow-through, as an animation: a spring
    /// tuned to overshoot its target and spring back, so a thing
    /// that lands keeps moving for a beat and then settles. That
    /// overshoot is the follow-through; the spring back is the
    /// rubber band.
    static let rubberBand = Animation.spring(
        response: MotionSpec.uiLimit,
        dampingFraction: MotionSpec.followThroughSpringDamping
    )

    /// Exaggeration, kept for rare and first-time moments only (the
    /// Frequency principle): a spring loose enough to overshoot
    /// visibly before it settles, so the one moment that matters
    /// reads bigger than life. Never on a frequent action.
    static let exaggerated = Animation.spring(
        response: MotionSpec.popDuration,
        dampingFraction: MotionSpec.followThroughSpringDamping
    )

    /// Anticipation: the small wind-up before a main action lands.
    /// Same timing as the press, named for the moments that charge
    /// up first (a press squashing before its action fires).
    static let anticipation = Animation.easeOut(duration: MotionSpec.pressDuration)

    /// Staggering: the animation for the `index`th thing in a set
    /// that arrives one after another instead of all in unison.
    /// The delay comes from the Kit, capped so a long list never
    /// keeps the user waiting. Reduced motion means no stagger at
    /// all: no delay, and a zero-length animation so the content
    /// is simply there.
    static func stagger(index: Int, reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .linear(duration: 0)
            : .easeOut(duration: MotionSpec.swapDuration)
                .delay(MotionSpec.staggerDelay(index: index))
    }

    /// Frequency of use, as a duration: feed a base duration and
    /// the frequency a moment happens at, and the Kit hands back
    /// how long that moment is allowed to animate for — nothing
    /// for keyboard actions, less for frequent ones, the full
    /// base only for rare ones.
    static func frequency(_ frequency: MotionFrequency, base: TimeInterval) -> TimeInterval {
        MotionSpec.duration(for: frequency, base: base)
    }
}

extension View {
    /// A panel on the canvas: panel fill, one hairline, and — solid
    /// drawing, from the literal round — a soft shadow, so a flat
    /// panel reads as a thing with volume sitting on the canvas
    /// instead of a drawing of one. The user asked for this on the
    /// panels themselves, not only on floating surfaces, so panels
    /// get it even though the shadow is on every card: it is kept
    /// faint (the Kit's solidShadowOpacity) so the Ledger still
    /// reads quiet at rest.
    func panelSurface(radius: CGFloat = Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(Surface.panel, in: shape)
            .overlay(shape.strokeBorder(Surface.hairline, lineWidth: 1))
            .shadow(color: Color.black.opacity(MotionSpec.solidShadowOpacity), radius: 8, x: 0, y: 4)
    }

    /// Origin awareness: this view pops in from `anchor` — the
    /// place it grew out of, a tapped button, the top of the
    /// window — instead of fading in from an arbitrary centre.
    /// Scale starts at 0.95 with a fade, timed by `Motion.pop`.
    func motionPop(anchor: UnitPoint = .center) -> some View {
        modifier(MotionPopModifier(anchor: anchor))
    }

    /// Staggering, for a set whose arrival is driven by the
    /// caller's `appeared` state: this item fades and rises in
    /// after the ones before it, by its index.
    func staggered(index: Int, appeared: Bool) -> some View {
        modifier(StaggeredModifier(index: index, appeared: appeared))
    }

    /// Staggering, self-driven: the same arrival, flipped on by
    /// the view's own first appearance. For rows in a list, where
    /// no parent keeps an appeared flag per row.
    func staggered(index: Int) -> some View {
        modifier(StaggeredOnAppearModifier(index: index))
    }

    /// Arcs: this view arrives and leaves along a curve instead
    /// of a straight slide (see `AnyTransition.arcIn`).
    func arcIn() -> some View {
        modifier(ArcInModifier())
    }
}

/// The transition behind `motionPop(anchor:)`. Reduced motion
/// drops the scale and keeps a plain fade, timed the same.
private struct MotionPopModifier: ViewModifier {
    let anchor: UnitPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(
            .asymmetric(
                insertion: reduceMotion
                    ? .opacity
                    : .scale(scale: 0.95, anchor: anchor).combined(with: .opacity),
                removal: .opacity
            )
        )
    }
}

/// The state behind `staggered(index:appeared:)`: hidden and
/// dropped a step until `appeared`, then in place, with the
/// animation delayed by index. Reduced motion shows the content
/// at once, with no offset and no delay.
private struct StaggeredModifier: ViewModifier {
    let index: Int
    let appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8) // grid: ok the staggered entrance rises 8 pt into place
            .animation(Motion.stagger(index: index, reduceMotion: reduceMotion), value: appeared)
    }
}

/// The self-driven stagger: a row flips its own appeared state
/// when it first shows, so a list can stagger without a parent
/// tracking every row.
private struct StaggeredOnAppearModifier: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8) // grid: ok the staggered entrance rises 8 pt into place
            .animation(Motion.stagger(index: index, reduceMotion: reduceMotion), value: appeared)
            .onAppear { appeared = true }
    }
}

/// The modifier behind `arcIn()`: it only attaches the
/// transition; the animation itself rides on the container's
/// `.animation(_:value:)`, so a page switch can be interrupted
/// and retargeted like everything else.
private struct ArcInModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.transition(.arcIn)
    }
}

extension AnyTransition {
    /// Arcs: a page does not travel in a straight line. It enters
    /// stepped in from the trailing side and lifted, and leaves
    /// stepped out the other way and dropped, so across a switch
    /// the eye reads one curved path — the visible chord of the
    /// arc — instead of a flat slide. Opacity rides along so the
    /// curve never reads as a hard cut.
    static var arcIn: AnyTransition {
        .asymmetric(
            insertion: .offset(x: 16, y: -8).combined(with: .opacity), // grid: ok the arc transition's entry step, 16 across and 8 up
            removal: .offset(x: -16, y: 8).combined(with: .opacity) // grid: ok the arc transition's exit step, mirroring the entry
        )
    }
}

/// The recording state, in one place: a dot, red while listening,
/// and — since the literal round — pulsing while it listens. This
/// used to say "No pulse. Status is read, not performed." The user
/// ordered all 19 principles in literally, so the dot now performs:
/// the pulse is the Exaggeration principle (it swells past its
/// resting size, to the Kit's exaggerationScale) and its halo is
/// the secondary action, following the same beat a fraction later.
/// Reduced motion puts the performance back: a plain static dot.
struct StatusDot: View {
    let listening: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        ZStack {
            // The halo: the secondary action. It swells with the
            // dot but its animation is delayed a beat, so it reads
            // as a flourish behind the main action, not a copy of it.
            Circle()
                .fill(Surface.live.opacity(listening ? 0.24 : 0))
                .frame(width: 8, height: 8)
                .scaleEffect(pulsing && !reduceMotion ? CGFloat(MotionSpec.exaggerationScale) : 1)
                .animation(
                    listening && !reduceMotion
                        ? .easeInOut(duration: MotionSpec.sheetDuration)
                            .delay(MotionSpec.secondaryActionDelay)
                            .repeatForever(autoreverses: true)
                        : Motion.press,
                    value: pulsing
                )
            Circle()
                .fill(listening ? Surface.live : Color.secondary.opacity(0.45))
                .frame(width: 8, height: 8)
                .scaleEffect(pulsing && !reduceMotion ? CGFloat(MotionSpec.exaggerationScale) : 1)
                .animation(
                    listening && !reduceMotion
                        ? .easeInOut(duration: MotionSpec.sheetDuration)
                            .repeatForever(autoreverses: true)
                        : Motion.press,
                    value: pulsing
                )
        }
        .accessibilityLabel(listening ? "Listening" : "Not listening")
        .onAppear { pulsing = listening }
        .onChange(of: listening) { _, isListening in pulsing = isListening }
    }
}

/// The one hue on the Live page: a thin rail at the answer's leading
/// edge. It takes the accent while an answer is live or present, and
/// rests as a hairline the rest of the time.
///
/// Follow-through: the accent does not snap on. It draws in over
/// the hairline on the rubber-band spring, overshoots, and settles,
/// so the rail keeps moving for a beat after the answer state has
/// already changed. The glow around it is the secondary action: the
/// same spring, delayed by the Kit's secondaryActionDelay, arriving
/// just after the rail itself.
struct AnswerRail: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Surface.hairline)
            Rectangle()
                .fill(Palette.accent)
                .opacity(active ? 1 : 0)
                // Squash and stretch, the rail's share: while an
                // answer is in motion the rail stretches a touch
                // taller and narrower (the Kit's stretch scales),
                // and the rubber-band animation below overshoots
                // that stretch before it settles.
                .scaleEffect(
                    x: active ? CGFloat(MotionSpec.stretchScaleX) : 1,
                    y: active ? CGFloat(MotionSpec.stretchScaleY) : 1
                )
                .animation(reduceMotion ? Motion.contentSwap(reduceMotion: true) : Motion.rubberBand, value: active)
            Rectangle()
                .fill(Palette.accent)
                .opacity(active ? 0.32 : 0)
                .blur(radius: 4)
                .animation(
                    reduceMotion
                        ? Motion.contentSwap(reduceMotion: true)
                        : Motion.rubberBand.delay(MotionSpec.secondaryActionDelay),
                    value: active
                )
        }
        .frame(width: 3) // grid: ok the rail is a 3 pt rule, set in DESIGN.md
    }
}

/// A page title at working size, with its one-line answer underneath.
/// App screens get no hero header: the title is a headline, not a poster.
struct PageHeader<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(.title3.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

/// The one primary action on a screen: near-black, with press
/// feedback. A press is squash and stretch, literally: the button
/// squishes wider and shorter under the finger (the Kit's squash
/// scales), which is also its anticipation — the wind-up that says
/// the action is about to land. On release the exaggerated spring
/// overshoots the settle, because the primary action is the rare,
/// deliberate moment on its screen. The label itself never scales,
/// so the words stay legible through the squash.
struct InkButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        InkLabel(configuration: configuration, compact: compact)
    }

    private struct InkLabel: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration
        let compact: Bool

        var body: some View {
            configuration.label
                .font(.callout.weight(.medium))
                .foregroundStyle(Surface.onInk)
                .padding(.horizontal, compact ? Space.sm : Space.md)
                .padding(.vertical, compact ? Space.xs : Space.sm)
                .background(Surface.ink, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
                .scaleEffect(
                    x: configuration.isPressed ? CGFloat(MotionSpec.squashScaleX) : 1,
                    y: configuration.isPressed ? CGFloat(MotionSpec.squashScaleY) : 1
                )
                .animation(Motion.exaggerated, value: configuration.isPressed)
        }
    }
}

/// A secondary action: no fill, one hairline, the inset tone while
/// pressed. Its press squashes and stretches like the primary's
/// (wider, shorter, the Kit's squash scales) but on the plain press
/// timing — a frequent action earns no exaggerated spring.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietLabel(configuration: configuration)
    }

    private struct QuietLabel: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration

        var body: some View {
            configuration.label
                .font(.callout)
                .foregroundStyle(.primary)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xs)
                .background(configuration.isPressed ? Surface.inset : Surface.control,
                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Surface.controlBorder, lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(
                    x: configuration.isPressed ? CGFloat(MotionSpec.squashScaleX) : 1,
                    y: configuration.isPressed ? CGFloat(MotionSpec.squashScaleY) : 1
                )
                .animation(Motion.press, value: configuration.isPressed)
        }
    }
}

/// A small filled chip: calendar events and the overlay's action row.
/// Selected chips take a pale wash of the accent, because the selection
/// is data, not chrome. Presses squash and stretch on the press
/// timing, like the other buttons.
struct ChipButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        ChipLabel(configuration: configuration, selected: selected)
    }

    private struct ChipLabel: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration
        let selected: Bool

        var body: some View {
            configuration.label
                .font(.callout)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xs)
                .background(selected ? Palette.accent.opacity(0.14) : Surface.control,
                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(selected ? Palette.accent.opacity(0.35) : Surface.controlBorder, lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(
                    x: configuration.isPressed ? CGFloat(MotionSpec.squashScaleX) : 1,
                    y: configuration.isPressed ? CGFloat(MotionSpec.squashScaleY) : 1
                )
                .animation(Motion.press, value: configuration.isPressed)
        }
    }
}
