import Foundation
import Testing
@testable import InterviewAIKit

private func close(_ a: Double, _ b: Double) -> Bool {
    abs(a - b) < 1e-9
}

@Test("All nineteen principles are present, in the reel's order")
func motionPrincipleCountAndOrder() {
    #expect(MotionPrinciple.allCases.count == 19)
    #expect(MotionPrinciple.allCases.first == .exaggeration)
    #expect(MotionPrinciple.allCases.last == .peakEndRule)
    #expect(MotionPrinciple.allCases[3] == .squashAndStretch)
    #expect(MotionPrinciple.allCases[13] == .timing)
}

@Test("Principle raw values are unique, and every name and lesson is non-empty")
func motionPrincipleText() {
    #expect(Set(MotionPrinciple.allCases.map(\.rawValue)).count == 19)
    for principle in MotionPrinciple.allCases {
        #expect(!principle.name.isEmpty)
        #expect(!principle.lesson.isEmpty)
    }
    #expect(MotionPrinciple.squashAndStretch.name == "Squash and Stretch")
    #expect(MotionPrinciple.peakEndRule.name == "Peak-End Rule")
}

@Test("Every named duration respects the timing limit, which respects the Doherty limit")
func motionDurationLimits() {
    #expect(MotionSpec.uiLimit <= MotionSpec.dohertyLimit)
    #expect(close(MotionSpec.dohertyLimit, 0.4))
    #expect(close(MotionSpec.uiLimit, 0.3))
    for duration in [MotionSpec.pressDuration, MotionSpec.swapDuration,
                     MotionSpec.popDuration, MotionSpec.sheetDuration] {
        #expect(duration > 0)
        #expect(duration <= MotionSpec.uiLimit)
    }
}

@Test("Frequency scales duration: keyboard none, frequent less, occasional base, rare more")
func motionDurationForFrequency() {
    let keyboard = MotionSpec.duration(for: .keyboard, base: 0.2)
    let frequent = MotionSpec.duration(for: .frequent, base: 0.2)
    let occasional = MotionSpec.duration(for: .occasional, base: 0.2)
    let rare = MotionSpec.duration(for: .rare, base: 0.2)
    #expect(keyboard == 0)
    #expect(frequent > 0)
    #expect(occasional > 0)
    #expect(rare > 0)
    #expect(keyboard < frequent)
    #expect(frequent < occasional)
    #expect(occasional < rare)
    #expect(close(frequent, 0.1))
    #expect(close(occasional, 0.2))
    #expect(close(rare, 0.3))
    // A long base still caps the frequent case at the press duration.
    #expect(close(MotionSpec.duration(for: .frequent, base: 0.28), MotionSpec.pressDuration))
}

@Test("Stagger delays grow with the index, start at zero, and stop at the cap")
func motionStaggerDelay() {
    #expect(MotionSpec.staggerDelay(index: 0) == 0)
    #expect(MotionSpec.staggerDelay(index: -3) == 0)
    #expect(MotionSpec.staggerDelay(index: 1) < MotionSpec.staggerDelay(index: 2))
    #expect(MotionSpec.staggerDelay(index: 2) < MotionSpec.staggerDelay(index: 3))
    #expect(close(MotionSpec.staggerDelay(index: 2), 2 * MotionSpec.staggerStep))
    #expect(close(MotionSpec.staggerDelay(index: 100), MotionSpec.staggerCap))
    #expect(close(MotionSpec.staggerDelay(index: 1_000), MotionSpec.staggerCap))
}

@Test("Rubber banding starts at zero, grows with the pull, stays under the limit, and keeps the sign")
func motionRubberBand() {
    #expect(MotionSpec.rubberBand(offset: 0, limit: 100) == 0)
    #expect(MotionSpec.rubberBand(offset: 10, limit: 0) == 0)
    #expect(MotionSpec.rubberBand(offset: 10, limit: -5) == 0)
    let small = MotionSpec.rubberBand(offset: 10, limit: 100)
    let large = MotionSpec.rubberBand(offset: 60, limit: 100)
    #expect(small > 0)
    #expect(large > small)
    #expect(large < 100)
    #expect(MotionSpec.rubberBand(offset: 10_000, limit: 100) < 100)
    #expect(close(MotionSpec.rubberBand(offset: -10, limit: 100), -small))
    #expect(MotionSpec.rubberBand(offset: -60, limit: 100) < 0)
}

@Test("An arc is flat at both ends, peaks in the middle, and clamps stray values")
func motionArcOffset() {
    #expect(MotionSpec.arcOffset(t: 0) == 0)
    #expect(MotionSpec.arcOffset(t: 1) == 0)
    #expect(close(MotionSpec.arcOffset(t: 0.5), 1))
    #expect(MotionSpec.arcOffset(t: 0.25) > 0)
    #expect(MotionSpec.arcOffset(t: 0.25) < 1)
    #expect(MotionSpec.arcOffset(t: -1) == 0)
    #expect(MotionSpec.arcOffset(t: 2) == 0)
}

@Test("Hick's factor grows as choices grow, and is zero with no choices")
func motionHickDecisionFactor() {
    #expect(MotionSpec.hickDecisionFactor(choices: 0) == 0)
    #expect(MotionSpec.hickDecisionFactor(choices: -2) == 0)
    #expect(MotionSpec.hickDecisionFactor(choices: 1) < MotionSpec.hickDecisionFactor(choices: 3))
    #expect(MotionSpec.hickDecisionFactor(choices: 3) < MotionSpec.hickDecisionFactor(choices: 7))
    #expect(close(MotionSpec.hickDecisionFactor(choices: 7), 3))
}

@Test("Fitts's index falls as the target grows, and a missing target returns the sentinel")
func motionFittsIndex() {
    let narrow = MotionSpec.fittsIndex(distance: 100, targetWidth: 10)
    let wider = MotionSpec.fittsIndex(distance: 100, targetWidth: 20)
    let widest = MotionSpec.fittsIndex(distance: 100, targetWidth: 40)
    #expect(narrow > wider)
    #expect(wider > widest)
    #expect(MotionSpec.fittsIndex(distance: 0, targetWidth: 32) == 0)
    #expect(close(MotionSpec.fittsIndex(distance: 100, targetWidth: 0), 1_000))
    #expect(close(MotionSpec.fittsIndex(distance: 100, targetWidth: -1), 1_000))
}

@Test("The peak-end score is the average of the peak and the ending")
func motionPeakEndScore() {
    #expect(close(MotionSpec.peakEndScore(peak: 8, end: 4), 6))
    #expect(close(MotionSpec.peakEndScore(peak: 5, end: 5), 5))
    #expect(close(MotionSpec.peakEndScore(peak: 0, end: 10), 5))
}

@Test("The distinctive index picks the outlier, the first on a tie, and nil when empty")
func motionDistinctiveIndex() {
    #expect(MotionSpec.distinctiveIndex(values: []) == nil)
    #expect(MotionSpec.distinctiveIndex(values: [1, 1, 1, 10, 1]) == 3)
    #expect(MotionSpec.distinctiveIndex(values: [-9, 1, 1, 1]) == 0)
    #expect(MotionSpec.distinctiveIndex(values: [0, 10]) == 0)
    #expect(MotionSpec.distinctiveIndex(values: [4]) == 0)
}

@Test("Squash widens and flattens, stretch narrows and tallens, around the press scale")
func motionSquashAndStretch() {
    #expect(MotionSpec.squashScaleX > 1)
    #expect(1 > MotionSpec.stretchScaleX)
    #expect(MotionSpec.squashScaleX > 1 && 1 > MotionSpec.stretchScaleX)
    #expect(MotionSpec.squashScaleY < 1)
    #expect(1 < MotionSpec.stretchScaleY)
    #expect(MotionSpec.squashScaleY < 1 && 1 < MotionSpec.stretchScaleY)
    #expect(MotionSpec.pressScale < 1)
    #expect(MotionSpec.anticipationScale < MotionSpec.pressScale)
    #expect(MotionSpec.exaggerationScale > 1)
}

@Test("The shared constants behind the remaining principles are sane")
func motionSharedConstants() {
    #expect(MotionSpec.minimumHitTarget == 32)
    #expect(MotionSpec.maxChoicesBeforeGrouping == 7)
    #expect(MotionSpec.secondaryActionDelay > 0)
    #expect(MotionSpec.secondaryActionDelay < MotionSpec.pressDuration)
    #expect(MotionSpec.followThroughSpringDamping > 0)
    #expect(MotionSpec.followThroughSpringDamping < 1)
    #expect(MotionSpec.solidShadowOpacity > 0)
    #expect(MotionSpec.solidShadowOpacity < 1)
    #expect(MotionSpec.easeOutCurve.count == 4)
    #expect(MotionSpec.easeInOutCurve.count == 4)
    #expect(MotionSpec.staggerStep > 0)
    #expect(MotionSpec.staggerCap >= MotionSpec.staggerStep)
}
