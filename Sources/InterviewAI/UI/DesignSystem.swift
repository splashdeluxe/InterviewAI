import SwiftUI

/// The design system for the redesign (docs/DESIGN.md).
///
/// Direction: Achromatic Ledger, adapted to a native Mac app. The chrome
/// holds no color. Surfaces are flat, split by hairlines, with no shadow
/// at rest. The one hue is the accent the user picked in Settings, and it
/// is spent on data only: the live answer rail, the "Me" speaker label,
/// the active mode check. Type is the system font, as Apple ships it.
///
/// Motion follows the same rule everywhere: press feedback is instant,
/// content swaps are short and fade only, and keyboard actions never
/// animate. Nothing enters from scale(0), nothing eases in.
enum Surface {
    /// The window ground: a blue-grey one step off the panel white.
    static let canvas = Color(light: 0xF2F4F7, dark: 0x17181A)
    /// Panels on the canvas.
    static let panel = Color(light: 0xFFFFFF, dark: 0x232427)
    /// A filled control or a selected row.
    static let inset = Color(light: 0xE9EDF1, dark: 0x2C2C2E)
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
    static let overlay: CGFloat = 12
}

enum Motion {
    /// Button press feedback: 120 ms, out fast.
    static let press = Animation.easeOut(duration: 0.12)

    /// A content swap (an answer arriving, a placeholder leaving). Fade
    /// only, under 200 ms. Reduced motion keeps the fade and drops the
    /// curve, since there is no movement to drop.
    static func contentSwap(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.15)
            : .timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
    }
}

extension View {
    /// A flat panel on the canvas: panel fill, one hairline, no shadow.
    func panelSurface(radius: CGFloat = Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(Surface.panel, in: shape)
            .overlay(shape.strokeBorder(Surface.hairline, lineWidth: 1))
    }
}

/// The recording state, in one place: a plain dot, red while listening.
/// No pulse. Status is read, not performed.
struct StatusDot: View {
    let listening: Bool

    var body: some View {
        Circle()
            .fill(listening ? Surface.live : Color.secondary.opacity(0.45))
            .frame(width: 8, height: 8)
            .accessibilityLabel(listening ? "Listening" : "Not listening")
    }
}

/// The one hue on the Live page: a thin rail at the answer's leading
/// edge. It takes the accent while an answer is live or present, and
/// rests as a hairline the rest of the time.
struct AnswerRail: View {
    let active: Bool

    var body: some View {
        Rectangle()
            .fill(active ? Palette.accent : Surface.hairline)
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

/// The one primary action on a screen: near-black, flat, with press
/// feedback. Pressing scales to 0.97, so the button answers the finger
/// before the action lands.
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
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Motion.press, value: configuration.isPressed)
        }
    }
}

/// A secondary action: no fill, one hairline, the inset tone while pressed.
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
                .background(configuration.isPressed ? Surface.inset : Color.clear,
                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Surface.hairline, lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Motion.press, value: configuration.isPressed)
        }
    }
}

/// A small filled chip: calendar events and the overlay's action row.
/// Selected chips take a pale wash of the accent, because the selection
/// is data, not chrome.
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
                .background(selected ? Palette.accent.opacity(0.14) : Surface.inset,
                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Motion.press, value: configuration.isPressed)
        }
    }
}
