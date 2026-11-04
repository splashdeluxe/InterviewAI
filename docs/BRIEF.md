# InterviewAI

A free, native Mac interview and meeting copilot for one person: Nils. It listens to both sides of a call, transcribes on the Mac, and suggests answers grounded in his own files, with a local model or his own API key. No account, no licence, no trial, no tiers, no paywall anywhere in the code.

## Why

An original native app, built in a set order: screens catalogued first, stories second, original Swift code third. No third-party app code, text, prompts, icons, or branding is used. Structure and behaviour only.

## Main jobs

1. Hear a live call (system audio plus microphone), transcribe both channels on-device, and stream a suggested answer in a floating overlay.
2. Ground answers in his own context: resume, job description, notes, and a mode (interview, looking for work, technical, sales, recruiting, team meet, lecture, negotiation, general).
3. Keep every meeting: transcript, notes, summary, and a follow-up draft, searchable on the Mac.

## Data

- Meeting: title, startedAt, duration, mode, transcript segments (speaker, text, time), notes, summary, followUpDraft.
- Mode: name, system prompt, note template, isBuiltIn.
- ContextFile: name, kind (resume, job description, notes, general), text, isPinned.
- Settings live in UserDefaults. API keys live in the Keychain. Nothing is stored on a server.

## Shape

Sidebar window plus a floating overlay panel. macOS 14 or later. Swift and SwiftUI, SwiftData, no Xcode project. Local data. Works offline with Ollama and Apple Speech. Cloud models are bring-your-own-key only.

## System hooks

- Global shortcuts: Command-Shift-L start or stop listening, Command-Shift-H show or hide the overlay, Command-Shift-A answer now, Command-Shift-S screenshot to answer.
- Menu bar item with the same actions.
- Snapshot mode and a self-test, so an agent can verify every screen from the command line.

## Reference

The screen catalogue and the story list in docs/STORIES.md. They describe what the app must do, screen by screen.

## Look

Native Mac look, system colours, one accent colour picked in Settings. No copied trade dress.

## Not in version one

- Phone mirror, calendar write access (the calendar feature is read-only),
  connectors (Slack, Notion, CRM), share links.
- Hosted API tier, accounts, teams, sync.
- Any form of payment, licence check, trial, quota, or upgrade prompt. InterviewAI has no tier.
