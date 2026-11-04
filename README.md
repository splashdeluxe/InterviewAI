# InterviewAI

A free, native Mac interview and meeting copilot. It listens to both sides
of a call, transcribes on the Mac (Parakeet Ultra by default, Whisper or
Apple Speech as the other engines), and streams suggested answers grounded
in your own files, from a local model (Ollama) or your own API key.

No account. No licence. No trial. No quota. No store. There is no code in
this app that could show a paywall, because none was written.

## What it does

- **Live**: system audio (them) and microphone (you) transcribed at the
  same time, on-device. Auto Answer when a question settles, or manual
  actions: What Should I Say, Clarify, Recap, Follow-Up, Answer, Code
  Hint, Brainstorm (Command-1 to Command-7). Optional, in Settings,
  Speech: translate each line as it lands (English, German, Russian,
  Indonesian, Spanish) through your own provider, and tell speakers
  apart on the other side (saved meetings label them Speaker 1,
  Speaker 2, ...). The transcript follows the newest line and stays
  scrollable.
- **Overlay**: a floating panel over Zoom, Teams, or Meet with the live
  transcript, the streaming answer, the action row, an ask box, and
  screenshot attach (Command-Shift-S captures the front window).
- **Modes**: nine built-in modes (General, Technical Interview, Looking
  for Work, Behavioral, Negotiation, Sales, Recruiting, Team Meet,
  Lecture) plus your own, each with custom context.
- **Context**: add your resume, the job description, and notes. Pinned
  files go into every answer; the rest are ranked locally by keyword
  match. Nothing here is gated.
- **Meetings**: every finished call is saved with transcript, notes, a
  summary, and a follow-up draft. Search and Ask search them on the Mac.
- **Calendar (read-only)**: upcoming meetings on the Live page with
  one-click start; the saved meeting takes the event's title, attendee
  list, and a link back to the event. It never writes to your calendar.
- **Profile**: one structured profile for the role you are chasing.
  Sources (a resume and a job description, picked from files of the
  right kind), standing instructions the copilot applies to every
  answer, extra background, and the generated sections: About You,
  Talking Points (fed into live answers, with honest gap answers),
  Company Intel (live web results when you add your own Tavily key),
  and a Cover Letter.
- **Providers**: Ollama locally (free, private), or any OpenAI-compatible
  endpoint with your own key, stored in the Keychain.

## Build and run (Mac)

Needs macOS 14 or later and Xcode (for the Swift toolchain). You never
open Xcode.

```bash
git clone https://github.com/splashdeluxe/InterviewAI.git
cd InterviewAI
./build.sh --open
```

Then:

1. Settings, Providers: leave Ollama, or pick your endpoint and key, and
   Test Connection. For local: `ollama pull llama3.2:3b` first.
2. Settings, Permissions: grant Microphone, Speech Recognition, and
   Screen Recording (that last one is how system audio is heard). The
   Parakeet Ultra and Whisper engines (Settings, Speech) need no Speech
   Recognition grant; download their model there once. Parakeet Ultra is
   the default: the fastest, and the most accurate on its 25 European
   languages. Whisper covers more languages, Indonesian among them.
3. Context page: add your resume and the job description.
4. Live page: Start Listening, or Command-Shift-H for the overlay.

Checks an agent can run:

```bash
swift test --scratch-path ~/Library/Developer/InterviewAI/test-build
tools/selftest.sh     # the app's own checks on a throwaway store
tools/snap.sh         # light and dark PNG of every page and Settings tab
```

## How it was built

The app was catalogued screen by screen, written as user stories, then
built as an original native app one story at a time. The brief is in
`docs/BRIEF.md`, the backlog in `docs/STORIES.md`.

InterviewAI is an original app: it contains no third-party app code,
text, prompts, icons, or branding. Paywall, trial, licence, and
hosted-tier screens were deliberately left out (see the Dropped list in
`docs/STORIES.md`).

## Design

Achromatic Ledger, adapted to a native Mac app, following Emil
Kowalski's design engineering skills: flat panels on a blue-grey
ground, hairlines instead of shadows, an ink primary action, and the
chosen accent spent on live data only. Buttons answer on press;
keyboard actions never animate. The full direction and token list are
in `docs/DESIGN.md`.

## Privacy

Audio is transcribed on the Mac and never recorded. Meetings and context
files live in a local SwiftData store. The only data that leaves the Mac
is the prompt sent to the provider you chose.

## Licence

MIT, for the InterviewAI code. See LICENSE.
