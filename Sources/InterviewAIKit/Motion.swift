import Foundation

/// The nineteen animation principles from Ben's reel, turned into
/// one place InterviewAI can point at. The reel is a checklist from
/// classic animation and interaction design; this file is what each
/// item means here, in a calm Mac app used under pressure, plus the
/// numbers the app layer builds its animations from. The values live
/// in the Kit so they are testable without a window: the app reads
/// the spec, the Kit decides what the spec is.
///
/// Every animation built from this spec is interruptible by
/// construction: SwiftUI animations retarget when state changes
/// mid-flight, and nothing here asks for a fixed, uninterruptible
/// run. That is the interruptible-motion principle, and it is why
/// there is no "lock input while animating" constant to add.
public enum MotionPrinciple: String, CaseIterable, Sendable {
    case exaggeration
    case originAwareness
    case staggering
    case squashAndStretch
    case rubberBanding
    case dohertyThreshold
    case anticipation
    case fittsLaw
    case slowInSlowOut
    case hicksLaw
    case followThrough
    case arcs
    case vonRestorffEffect
    case timing
    case interruptibleMotion
    case secondaryAction
    case solidDrawing
    case frequencyOfUse
    case peakEndRule

    /// The name the principle goes by, for lists and settings.
    public var name: String {
        switch self {
        case .exaggeration: return "Exaggeration"
        case .originAwareness: return "Origin Awareness"
        case .staggering: return "Staggering"
        case .squashAndStretch: return "Squash and Stretch"
        case .rubberBanding: return "Rubber Banding"
        case .dohertyThreshold: return "Doherty Threshold"
        case .anticipation: return "Anticipation"
        case .fittsLaw: return "Fitts's Law"
        case .slowInSlowOut: return "Slow In, Slow Out"
        case .hicksLaw: return "Hick's Law"
        case .followThrough: return "Follow-through"
        case .arcs: return "Arcs"
        case .vonRestorffEffect: return "Von Restorff Effect"
        case .timing: return "Timing"
        case .interruptibleMotion: return "Interruptible Motion"
        case .secondaryAction: return "Secondary Action"
        case .solidDrawing: return "Solid Drawing"
        case .frequencyOfUse: return "Frequency of Use"
        case .peakEndRule: return "Peak-End Rule"
        }
    }

    /// One line on how InterviewAI applies the principle. Short on
    /// purpose: a lesson you can hold in mind while building a view.
    public var lesson: String {
        switch self {
        case .exaggeration: return "Push feedback a touch past literal so the moment registers, then settle back to true."
        case .originAwareness: return "Grow panels and popovers from the click or tap that opened them, never from an arbitrary centre."
        case .staggering: return "Bring related items in one after another, a beat apart, instead of all at once."
        case .squashAndStretch: return "Squash on impact and stretch in motion so controls feel physical, not pasted on."
        case .rubberBanding: return "Let a pull past the end stretch with growing resistance, then spring back on release."
        case .dohertyThreshold: return "Answer every action within 400 milliseconds so the app never feels like it is thinking about it."
        case .anticipation: return "Wind up a fraction before a big move, so the move itself never comes as a surprise."
        case .fittsLaw: return "Make frequent targets big and close; distance and size decide how fast a target is to hit."
        case .slowInSlowOut: return "Ease at both ends of a move, because motion that starts and stops dead reads as robotic."
        case .hicksLaw: return "Group or trim choices past a handful, because every extra option slows the decision."
        case .followThrough: return "Let the details keep moving a beat after the main element stops, so nothing halts unnaturally."
        case .arcs: return "Move things along a shallow arc, the way real objects travel, not in ruler-straight lines."
        case .vonRestorffEffect: return "Make the one thing that matters look different, because the odd one out is what gets noticed."
        case .timing: return "Keep user-interface animations under 300 milliseconds, without exception."
        case .interruptibleMotion: return "Never trap the user in an animation; a change of mind mid-move cancels or retargets it."
        case .secondaryAction: return "Add one small flourish that backs up the main action without competing with it."
        case .solidDrawing: return "Give flat surfaces depth and volume, through shading and shadow, so they read as solid things."
        case .frequencyOfUse: return "Animate rarely used things most and everyday things least; the hundredth use should be nearly still."
        case .peakEndRule: return "Spend the care on the best moment and the ending, because those are what people remember."
        }
    }
}

/// How often the user will meet an animation. Frequency decides how
/// much animation it earns: keyboard actions are met hundreds of
/// times a day and earn none, a rare first-run moment can carry the
/// most. This is the frequency-of-use principle as a type.
public enum MotionFrequency: Sendable {
    case keyboard
    case frequent
    case occasional
    case rare
}

/// Where an appearing element grows from: the trigger that opened
/// it. Origin awareness as a type, so a popover or sheet says its
/// anchor instead of silently defaulting to the centre.
public enum MotionOrigin: Sendable {
    case top
    case topLeading
    case topTrailing
    case bottom
    case center
    case leading
    case trailing
}

/// The numbers behind every animation in the app. One spec, so a
/// press in the overlay and a press in Settings feel like the same
/// app, and so the limits the principles set — respond within the
/// Doherty threshold, keep interface animation under the timing
/// limit — are checked in one place instead of per view.
public enum MotionSpec {
    /// The Doherty threshold: an action answered inside this many
    /// seconds feels instant, so no response may take longer.
    public static let dohertyLimit: Double = 0.4

    /// The timing principle as a limit: no user-interface animation
    /// runs longer than this. Every named duration below respects
    /// it, and any base duration handed to `duration(for:base:)`
    /// for an interface animation must be picked so its result
    /// respects it too — the frequency scaling alone does not clamp
    /// an oversized base into line.
    public static let uiLimit: Double = 0.3

    /// Button press feedback: the fastest named move in the app.
    public static let pressDuration: Double = 0.12

    /// A content swap, such as an answer arriving in place.
    public static let swapDuration: Double = 0.18

    /// A popover or palette appearing from its origin.
    public static let popDuration: Double = 0.22

    /// A sheet arriving: the largest common move, still in limit.
    public static let sheetDuration: Double = 0.28

    /// The gap between one staggered item and the next.
    public static let staggerStep: Double = 0.03

    /// No item waits longer than this, however long the list: the
    /// cap keeps staggering from turning into a slow procession.
    public static let staggerCap: Double = 0.24

    /// How far a control scales down while pressed.
    public static let pressScale: Double = 0.97

    /// Squash on impact: wider and shorter for one beat.
    public static let squashScaleX: Double = 1.04
    public static let squashScaleY: Double = 0.92

    /// Stretch in motion: narrower and taller while travelling.
    public static let stretchScaleX: Double = 0.98
    public static let stretchScaleY: Double = 1.03

    /// The wind-up scale just before a big move: anticipation.
    public static let anticipationScale: Double = 0.94

    /// The overshoot scale for a rare, deliberate moment of
    /// emphasis: exaggeration, kept to one small step past true.
    public static let exaggerationScale: Double = 1.12

    /// The smallest target a pointer should have to hit, in
    /// points. Fitts's law as a floor: bigger is faster to acquire,
    /// so nothing interactive ships smaller than this.
    public static let minimumHitTarget: Double = 32.0

    /// Hick's law as a count: past this many choices in one place,
    /// group them instead of adding another row of options.
    public static let maxChoicesBeforeGrouping: Int = 7

    /// The delay before a secondary action follows the main move:
    /// follow-through's beat, as a number the app can share.
    public static let secondaryActionDelay: Double = 0.06

    /// The damping for the spring that lets details settle after
    /// the main element stops: under-damped enough to overshoot a
    /// little, damped enough to stop. Follow-through, as a spring.
    public static let followThroughSpringDamping: Double = 0.55

    /// The shadow strength that gives a floating surface its
    /// volume: solid drawing, kept faint so panels stay calm.
    public static let solidShadowOpacity: Double = 0.12

    /// The strong ease-out curve, for elements entering or
    /// answering: fast at the start, gentle at the end. Stored as
    /// the four control-point numbers a timing curve takes.
    public static let easeOutCurve: [Double] = [0.23, 1, 0.32, 1]

    /// The strong ease-in-out curve, for elements already on
    /// screen moving between places: slow in, slow out.
    public static let easeInOutCurve: [Double] = [0.77, 0, 0.175, 1]

    /// How long an animation gets, given how often it is met.
    /// Keyboard actions get none, ever. Frequent actions get at
    /// most half the base, capped at the press duration, so the
    /// hundredth use stays quick. Occasional actions get the base.
    /// Rare actions may take half as long again, for the moments
    /// that earn a little ceremony. A non-keyboard result is only
    /// positive when the base is, so callers pass a positive base.
    public static func duration(for frequency: MotionFrequency, base: Double) -> Double {
        switch frequency {
        case .keyboard: return 0
        case .frequent: return min(base / 2, pressDuration)
        case .occasional: return base
        case .rare: return base * 1.5
        }
    }

    /// When the item at `index` in a staggered group should start:
    /// one step per place, capped, and never negative for a stray
    /// negative index.
    public static func staggerDelay(index: Int) -> Double {
        min(Double(max(0, index)) * staggerStep, staggerCap)
    }

    /// Rubber banding: how far a pull past the end is shown, given
    /// how far it was pulled. The shown distance grows with the
    /// pull but with ever more resistance, stays strictly below
    /// `limit` for any finite pull, and keeps the pull's sign, so
    /// releasing it springs back the way it came. A limit that is
    /// not positive shows nothing.
    public static func rubberBand(offset: Double, limit: Double) -> Double {
        guard limit > 0, offset != 0 else { return 0 }
        let pull = abs(offset)
        let shown = (1 - 1 / (pull * 0.55 / limit + 1)) * limit
        return offset < 0 ? -shown : shown
    }

    /// The height of an arc at point `t` along a move, as a
    /// fraction of the arc's peak: nothing at either end, the full
    /// peak in the middle, a parabola in between. `t` is clamped
    /// to the move, so stray values land on the nearest end.
    public static func arcOffset(t: Double) -> Double {
        let clamped = min(1, max(0, t))
        return 4 * clamped * (1 - clamped)
    }

    /// Hick's law as a factor: decision time grows with the log of
    /// the number of choices, so doubling the options never doubles
    /// the factor. No choices, or a stray negative count, is zero.
    public static func hickDecisionFactor(choices: Int) -> Double {
        log2(Double(max(0, choices)) + 1)
    }

    /// Fitts's law as an index of difficulty: the log of distance
    /// over target width, so a nearer or wider target scores lower
    /// and is faster to hit. Distance is clamped at zero. A target
    /// width that is not positive has no meaningful index, so it
    /// returns a large finite sentinel, 1000, instead of infinity:
    /// callers can compare and sort results without special cases.
    public static func fittsIndex(distance: Double, targetWidth: Double) -> Double {
        guard targetWidth > 0 else { return 1_000 }
        return log2(max(0, distance) / targetWidth + 1)
    }

    /// The peak-end rule as a score: what a moment is remembered
    /// as is the average of its peak and its ending, not the sum
    /// of everything in between.
    public static func peakEndScore(peak: Double, end: Double) -> Double {
        (peak + end) / 2
    }

    /// Von Restorff as a lookup: the index of the value that stands
    /// out, meaning the one farthest from the mean of the list.
    /// Nil for an empty list. A tie goes
    /// to the first value that reached the distance, so the answer
    /// is stable for a given list.
    public static func distinctiveIndex(values: [Double]) -> Int? {
        guard !values.isEmpty else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        var bestIndex = 0
        var bestDistance = abs(values[0] - mean)
        for index in values.indices.dropFirst() {
            let distance = abs(values[index] - mean)
            if distance > bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }
}
