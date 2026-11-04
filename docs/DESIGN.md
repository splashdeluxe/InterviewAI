# Design

The redesign follows Emil Kowalski's design engineering skills
(github.com/emilkowalski/skills) and Apple's fluid interface talks,
set as one direction for this app.

## Direction: Achromatic Ledger, on a Mac

The style was dealt for a work screen, not a page: Achromatic Ledger
(taste-skill app run, seed 84068020). Its move is that the chrome holds
no color at all. InterviewAI adapts it to native macOS:

- The ground is a blue-grey, one step off the panel white. That tint
  comes from the product's world: a quiet room, a call in progress.
- Panels are white (light) or one step up (dark), flat, split by 1 pt
  hairlines. No shadow at rest, no gradients, no glass in the main
  window. The overlay is the one translucent surface, because it floats
  over someone else's app.
- The primary action is near-black ink. In dark mode it flips to near
  white. It is the only filled button on a screen.
- The one hue is the stored accent. It is spent
  on data, never on chrome: the rail at the answer's edge while an
  answer is live, the "Me" speaker label, the active mode check, a
  selected calendar chip.
- Recording red appears in one place: the status dot.
- Type is the system font. Apple's own rules for it (optical sizing,
  tracking, leading) already ship with the OS, so no web font is loaded.
- Radii sit on a tight pair: 6 for controls, 8 for panels, 12 for the
  overlay. Spacing stays on the 4 pt grid in UI/Grid.swift.

## The face

The product names itself at the top of the sidebar: a plain ink square
with a waveform, the name InterviewAI, and the active mode under it as
the scope. The signature element is the answer rail. When an answer is
being written or is on screen, a 3 pt accent bar sits at its leading
edge, in the main window and in the overlay. The rest of the time it
rests as a hairline. It says "this is the live part" without a badge,
a glow, or a colored card.

Each page answers one question first:

- Live: Am I live, in which mode, and what do I press next? The header
  is the session status, not a title poster. Transcript, notes, and
  answer are three flat panels, and the answer panel carries the rail.
- Meetings: What did we say? Rows carry date, length, and mode.
- Profile: What grounds my answers? Sources, standing instructions,
  and the generated sections are panels in two columns.

## Motion

Motion is feedback, and most of it was deleted on purpose.

- Buttons answer on press: scale to 0.97 over 120 ms, ease-out. This is
  Emil's first rule, and it is the only motion a user sees every day.
- An answer arriving swaps content with a fade: 180 ms on the strong
  ease-out curve (0.23, 1, 0.32, 1). No slide, no scale from nothing.
- Keyboard actions never animate. The overlay opens and closes at once,
  because Command-Shift-H is pressed hundreds of times.
- Page switches do not animate. Selecting a sidebar row is navigation,
  not a show.
- The status dot does not pulse. Recording is a state, not a
  performance.
- Reduced motion keeps the fades and drops nothing else, because there
  is no movement left to drop.

## Tokens

All tokens live in Sources/InterviewAI/UI/DesignSystem.swift: Surface
(canvas, panel, inset, ink, onInk, hairline, live), Radius, and Motion,
plus the three button styles (InkButtonStyle, QuietButtonStyle,
ChipButtonStyle), StatusDot, AnswerRail, and the panelSurface()
modifier. Views take colors from there or from Palette, never from a
hex in a view.

## Checked

Built clean in Xcode (no issues), unit tests 9/9 pass, and grid-lint
passes. Snapshot pictures are still blocked by the Mac capture gate on
the debug app, so the pages have not been compared as pictures yet.
The feel checks that code cannot settle (press weight, the fade on a
real answer, the rail in a live call) need one live session on the Mac.
