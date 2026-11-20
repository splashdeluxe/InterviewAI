# Motion: all 19 principles, in the app

On 2026-11-20 Nils asked for all 19 animation principles from Ben's
(@bendoescareer) reel put into InterviewAI, literally — not the
trimmed subset that was first proposed. This file is the map of
where each one lives, so a future change can keep them all true.

The numbers live in the Kit (`Sources/InterviewAIKit/Motion.swift`,
`MotionSpec`), with tests. The animations live in the app
(`Sources/InterviewAI/UI/DesignSystem.swift`, `Motion`). Two limits
hold across all of it: no interface animation runs over 300 ms, and
reduced motion flattens every effect.

| Principle | Where it lives |
| --- | --- |
| Exaggeration | The listening dot pulses past its true size; the primary button settles on an overshooting spring |
| Origin awareness | The command palette grows from the top of the window; `motionPop(anchor:)` anchors any pop to its trigger |
| Staggering | Sidebar rows, palette rows, calendar chips, suggestions and Session Controls choices arrive one after another, 30 ms apart, capped |
| Squash and stretch | Every button style squashes wider and shorter when pressed; the answer rail stretches while an answer is live |
| Rubber banding | `Motion.rubberBand` spring — palette landing, answer rail, Meetings list settle; the overlay collapse runs on the same duration |
| Doherty threshold | Every response lands inside 400 ms; the slowest standard animation is 280 ms |
| Anticipation | The press squash is the wind-up before an action; suggestion tags start at the anticipation scale |
| Fitts's law | Palette rows and Session Controls choices keep at least the Kit's 32 pt minimum hit target |
| Slow in, slow out | `Motion.sheet` ease-in-out for pages and sheets; the overlay collapse keeps the strong ease-in-out curve |
| Hick's law | Choices are grouped past seven (the Kit's cap); the palette footer teaches only three keys |
| Follow-through | Springs overshoot and settle after the state change has already landed — rail, palette, lists |
| Arcs | Page switches and the overlay suggestion card travel the `arcIn` transition instead of a straight slide |
| Von Restorff effect | One thing looks different per surface: the red live dot, the accent answer rail, the ink End Session button |
| Timing | All durations come from `MotionSpec`; the largest is 0.28 s, under the 300 ms limit |
| Interruptible motion | Every animation is a plain SwiftUI `Animation` applied with `.animation(_:value:)`; a new state retargets it, input is never blocked |
| Secondary action | The dot's halo and the rail's glow follow the main move a beat later (the Kit's 60 ms delay) |
| Solid drawing | Panels carry a faint shadow and read as solid things on the canvas, not flat drawings |
| Frequency of use | `MotionSpec.duration(for:base:)` — keyboard actions get no animation, frequent ones get less, rare ones may take more |
| Peak-end rule | Session Controls shows what the session will be remembered by — duration, lines heard, last answer — at the moment the user ends it |

Three honest scopings:

- The overlay's collapse is an AppKit frame animation, which has no
  spring API. It runs on the Kit's sheet duration with the strong
  ease-in-out curve; the literal spring is on the SwiftUI surfaces.
- Meetings list rows recycle as they scroll, so they do not carry
  per-row stagger state. The list settles in on the rubber-band
  spring, and the stagger timing is spent on the detail tab swap.
- `MotionSpec.rubberBand(offset:limit:)` and `arcOffset(t:)` are
  spec maths with tests. No app surface owns pull-past-the-end drag
  geometry (overlay dragging is deliberately 1:1), and the arc is a
  fixed transition, so both are expressed in the app as the spring
  and the transition rather than as calls to those functions.
