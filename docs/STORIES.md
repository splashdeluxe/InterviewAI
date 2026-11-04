# InterviewAI user stories

Every screen in the catalogue maps to a story below or to the Dropped
list. There is
no paywall story, because there is no paywall: no licence, trial, quota,
account, or store code exists in this app.

## M1 Live loop

### S-001 Start listening and see both sides transcribed
As the user, I press Start Listening on the Live page and both the other
side of the call and my own voice appear as labelled transcript lines.
Acceptance:
- [manual] System audio and microphone are captured at the same time.
- [manual] Lines are labelled Them and Me, partial lines update in place.
- [self] Starting with no permissions shows the Permissions tab, not a crash.
- [unit] A finished line is never rewritten by a later partial.
Status: doing
UX:
- Flow: Live page, Start Listening, or Command-Shift-L -> status turns to Listening -> lines appear
- Surface: sidebar page plus the overlay panel (S-002)
- States: empty "Nothing heard yet"; error names the missing permission with an Open Settings button
- Words: "Start Listening", "Stop", tooltip "Start or stop listening (Command-Shift-L)"
- Access: full keyboard path, VoiceOver labels name the channel

### S-002 Get a suggested answer in the floating overlay
As the user, I open the overlay during a call and a suggested answer
streams in when the other side finishes a question.
Depends: S-001
Acceptance:
- [manual] The overlay floats above Zoom, Teams, and Meet and never takes focus from the call.
- [self] When a Them line settles, an answer starts on its own (Auto Answer on) or waits for Command-1 (off).
- [snap] Overlay snapshots show transcript left, answer right, action row under the answer.
- [unit] The answer prompt contains the mode prompt, the pinned context, and the recent transcript.
Status: doing
UX:
- Flow: Command-Shift-H shows or hides -> Command-1 to 7 run actions -> Escape closes the ask box first
- Surface: non-activating floating panel (a tool kept open beside the work)
- States: empty "Ask, or wait for the next question"; loading streams word by word; error shows inline with Retry
- Words: "What Should I Say", "Clarify", "Recap", "Follow-Up", "Answer", "Code Hint", "Brainstorm"
- Access: every action also in the Interview menu with its shortcut

### S-003 Ask a typed question during the call
As the user, I type a question in the overlay ask box and the answer uses
the live transcript and my context files.
Depends: S-002
Acceptance:
- [manual] Return sends, the answer streams into the answer area.
- [unit] The typed question is sent with the transcript window, not instead of it.
Status: doing

### S-004 Pick a mode and add custom context
As the user, I switch the active mode on the Modes page and paste custom
context that is used in every answer while that mode is active.
Acceptance:
- [snap] Modes page lists the nine built-in modes and my own.
- [self] The active mode survives a restart.
- [unit] The mode prompt and custom context appear in the built prompt.
Status: doing
UX:
- Flow: sidebar Modes -> pick a mode -> it is active everywhere at once
- Surface: sidebar page (a place people come back to)
- States: empty custom context shows "No custom context yet" with an editor right there
- Words: "Use This Mode", "Custom Context", "Add Mode"
- Access: prompt editor is a plain text view, VoiceOver "Mode prompt"

### S-005 Ground answers in my resume and job description
As the user, I add my resume, a job description, and notes on the Context
page, and answers use them without any gate or unlock.
Acceptance:
- [snap] Context page has an Add File button, a file list, and a pin control per file.
- [unit] Pinned files are always in the prompt; other files are ranked by keyword score against the question.
- [self] Removing a file removes it from the next prompt.
Status: doing
UX:
- Flow: Context page -> Add File -> the file appears and is pinned if its name says resume or job
- Surface: sidebar page
- States: empty "No context yet" with "Add File"; a file that cannot be read shows its error inline
- Words: "Add File", "Pinned", "Remove"
- Access: file picker is the standard open panel

### S-006 Use a local model, or my own key
As the user, I pick Ollama with a local model, or an OpenAI-compatible
endpoint with my own key, in Settings, Providers.
Acceptance:
- [self] Test Connection reports the real result from the endpoint.
- [unit] The key is stored in the Keychain, never in UserDefaults or a file.
- [snap] Providers tab shows endpoint, model, and key fields, and no plan or price anywhere.
Status: doing

### S-007 A finished call becomes a saved meeting
As the user, I stop listening and the call is saved under Meetings with
its transcript, my notes, a summary, and a follow-up draft.
Depends: S-001
Acceptance:
- [self] The meeting survives a restart (SwiftData store).
- [manual] Summary and follow-up are written by the model on Stop, and can be regenerated.
- [snap] Meeting detail shows Transcript, Notes, and Summary tabs.
Status: doing

### S-008 Permissions are visible and fixable in one place
As the user, I see the state of Microphone, Speech Recognition, and
Screen Recording on the Permissions tab, with a button to the right
System Settings pane.
Acceptance:
- [snap] Permissions tab lists the three permissions with live states.
- [self] A missing permission never crashes capture; the Live page explains it.
Status: doing

## M2 Organise

### S-009 Search and reopen past meetings
As the user, I search Meetings by title or transcript text and reopen any
meeting.
Acceptance:
- [snap] Meetings page groups by day, like the reference launcher.
- [unit] Search matches transcript text, not only titles.
Status: todo

### S-010 Edit notes during and after a call
As the user, I type notes on the Live page while listening, and they are
saved with the meeting.
Depends: S-007
Acceptance:
- [self] Notes typed during a call appear in the saved meeting unchanged.
Status: todo

### S-011 Create and delete my own modes
As the user, I add a mode with my own prompt and delete it again.
Depends: S-004
Acceptance:
- [unit] Built-in modes can be duplicated but not deleted.
Status: todo

### S-018 Calendar, read-only (added 2026-11-03 on the user's ask)
As the user, I connect my calendar once and see my upcoming meetings on
the Live page. I start listening from an event with one click, and the
saved meeting carries the event's title, its attendee list, and a link
back to the event. The app never creates or changes an event.
Depends: S-001, S-010
Acceptance:
- [manual] With access granted, the next 7 days of events appear on the
  Live page, earliest first, and Refresh reloads them.
- [manual] Starting from an event saves the meeting under the event
  title, with the event id stored and attendees in the notes.
- [self] Without access, the Live page shows the connect or settings
  hint and no event data.
Status: doing

## M3 Ask

### S-012 Ask across all meetings and context
As the user, I ask a question on the Ask page and the answer cites the
meetings and files it used.
Acceptance:
- [unit] The prompt includes the best-matching meetings by keyword score.
- [snap] The answer names its sources under the text.
Status: todo

## M4 Speed

### S-013 Run every action from the keyboard
As the user, I run listening, overlay, and the seven overlay actions from
global shortcuts, listed in the Interview menu.
Acceptance:
- [manual] Command-Shift-L, Command-Shift-H, Command-1 to 7, Command-Shift-S all work while another app is frontmost.
- [self] A shortcut that fails to register is reported on the General tab, not silently.
Status: doing

### S-014 Screenshot the front window and ask about it
As the user, I press Command-Shift-S and the front window's screenshot is
sent with my next question to a vision-capable model.
Depends: S-003
Acceptance:
- [manual] The captured window is the call or coding window in front, never InterviewAI itself.
- [self] A text-only model gets a clear note that the screenshot was left out.
Status: todo

### S-015 Menu bar control
As the user, I start and stop listening and show the overlay from the
menu bar item.
Acceptance:
- [snap] The menu shows Listening state and the three main actions.
Status: todo

## M5 Polish

### S-016 Light and dark snapshots of every page
As the user, I can run tools/snap.sh and get a light and dark PNG of every
sidebar page and Settings tab.
Acceptance:
- [snap] One PNG per page and mode in /tmp/InterviewAI-shots.
Status: doing

### S-017 Accent colour and calm windows
As the user, I pick an accent in Settings, Appearance, and windows open
with no focus ring and no empty scroll bars.
Acceptance:
- [snap] Snapshots pass tools/grid-lint.sh and the layout check.
Status: todo

### S-019 Intelligence page (added 2026-11-03 on the user's ask)
As the user, I open the Intelligence page and generate the layers that
ground my answers: a profile from my resume, talking points with honest
gap answers for a job description, a company brief (with live web
results when I add my own Tavily key), and a cover letter. The newest
talking points are fed into my live answers. None of it is gated.
Depends: S-003, S-012
Acceptance:
- [unit] The four prompts carry the resume and job description text and
  the honesty rule; Tavily responses parse into results.
- [manual] Generating each kind stores a document listed on the page,
  with Copy and Delete.
- [self] Live answers include the newest talking points in their
  context.
Status: doing

### S-020 Redesign: Achromatic Ledger (added 2026-11-03 on the user's ask)
As the user, I work in an app whose chrome holds no color: flat panels
on a blue-grey ground, hairlines instead of shadows, an ink primary
action, and my accent spent on live data only (the answer rail, the
"Me" label, the active mode). Buttons answer on press, keyboard
actions never animate, and the overlay uses the opacity I set.
Direction and tokens: docs/DESIGN.md, UI/DesignSystem.swift.
Depends: S-016, S-017
Acceptance:
- [snap] Every page and the overlay use the tokens in DesignSystem.swift;
  no view hard-codes a hex color.
- [snap] Snapshots pass in light and dark; press feedback is 120 ms
  ease-out at scale 0.97; the answer swap fades in 180 ms.
- [manual] One live session on the Mac: the rail reads as the live
  element, and the overlay opens at the set opacity.
Status: doing

### S-021 Profile page in Interview Pilot's style (added 2026-11-03 on the user's ask)
As the user, I keep one structured profile for the role I am chasing,
the way Interview Pilot does: sources first, standing instructions
the copilot applies to every answer, extra background the resume
misses, and the generated sections under it. The old Intelligence page
was four loose generators, and its resume picker silently fell back
to any file, so a generation could run on the wrong document.
Depends: S-019
Acceptance:
- [self] The pickers only offer files of the matching kind (resume,
  job); there is no cross-kind fallback.
- [self] Build Profile runs About You, then Talking Points, then
  Company Intel (when a company is named), in one run.
- [self] Every generated section can be edited in place, copied, and
  deleted.
- [self] Standing instructions and extra background are stored as
  documents and reach live answers ahead of the talking points
  (AppModel.profileContext).
- [manual] One Build Profile run on the Mac against the real resume
  and a real job description.
Status: doing

### S-022 Whisper engine (added 2026-11-03 on the user's ask, Handy route)
As the user, I can pick Whisper instead of Apple Speech for both
channels: the Handy stack's engine family (Whisper, pause-cut chunks),
running fully on my Mac through WhisperKit (MIT). Apple Speech stays
the light default; Whisper is stronger with accents and crosstalk and
needs no Speech Recognition permission.
Acceptance:
- [self] Settings, Speech: an engine picker and, for Whisper, a model
  picker with a Download / Load action.
- [self] Audio feeds a ChunkPolicy per channel: speech is cut on a
  0.9 second pause after 4 seconds, hard-capped at 15 seconds, and
  pure silence is dropped, never transcribed.
- [self] ChunkPolicy is unit tested (pause cut, hard cap, silence).
- [manual] One live session on Whisper: lines land a few seconds after
  they are spoken, in both channels.
Status: doing

### S-023 Parakeet Ultra engine (Nils's pick, 2026-11-03)
As a user I want Parakeet Ultra running as the transcription engine, so
lines land faster and cleaner than Whisper on European languages.
Parakeet Ultra is Moondream's post-trained Parakeet v3 (CC-BY-4.0),
run on the Neural Engine through FluidAudio (Apache-2.0). It is the
default engine; Whisper and Apple Speech stay as choices.
Acceptance:
- [self] Settings, Speech: engine picker with Parakeet Ultra first,
  and a Download / Load action (one-time, about 650 MB).
- [self] Same ChunkPolicy cutting as Whisper; the 15 second cap
  matches Parakeet's window. Language is auto-detected (25 European
  languages; Indonesian is not covered, and Settings says so).
- [manual] One live session on Parakeet Ultra in both channels.
Status: doing

### S-024 About, menu, update check, icon (Nils's asks, 2026-11-03)
As a user I want a real About screen, Settings in the menu, a check
for updates, and an icon of our own.
Acceptance:
- [self] App menu and menu bar icon carry About InterviewAI,
  Settings…, and Check for Updates…. About shows the icon, the
  version, the clean-room note, and the model credits.
- [self] The update check reads the repo's latest GitHub release and
  compares versions; one quiet check a day at launch, never a modal.
  The repo is private, so a signed-out check reports that plainly.
- [self] The icon is our own waveform mark (Icon/AppIcon.icon),
  compiled by tools/make_icon.sh on the build.sh route.
Status: doing

## Later

- Region screenshot cropper (11-cropper.png) instead of whole-window capture.
- Custom overlay buttons described in words (18-settings-overlay.png).
- Suggestion strip with Use Suggestion (09-suggestions.png).
- Meeting offer toast when an event is about to start (21-settings-calendar.png).
- Embedding and reranker picks for context ranking (20-settings-retrieval.png).
- Follow-up email send from the meeting page (05-meeting-details.png).

## Dropped

- Plans, pricing, Pro page, hosted API tier, trial modal and meter, quota
  banner (reference sales screens): there is no tier to sell.
- Connectors and share links (22-settings-connections.png): out of scope for a personal app, and they send data off the Mac.
- Phone Mirror (23-settings-phone-mirror.png): out of scope for version one.
- Undetectable mode, process disguise, mouse pass-through (07-overlay.png, 13-settings-general.png): InterviewAI is a normal visible app. It does not help anyone pretend it is not running.
- Review and update modals: updates ship as GitHub releases.
- Startup splash (01-startup.png): a native app does not need one.

## S-025: Translate the transcript as it lands

Status: doing (built 1.3.0; live check with a German call open)

As Nils, I want each transcript line translated into a language I pick, so a call in another language stays readable while it happens.

Acceptance:
- Settings, Speech has "Translate transcripts to": Off (default), English, German, Russian, Indonesian, Spanish.
- Each finished line is translated by the session's provider, one at a time, in order. Local Ollama by default, so nothing leaves the Mac unless my own key's endpoint is the provider.
- The translation is the line shown, in the Live page, the overlay, and the saved meeting. The original stays under it in small type and is what answers and summaries keep using.
- Toggling mid-call takes effect on the next line. Turning it off stops new translations; lines already translated keep theirs.

## S-026: Tell speakers apart on the other side

Status: doing (built 1.3.0; live check with a panel call open)

As Nils, I want a panel call to read as Speaker 1 and Speaker 2, not one "Them", so I can follow who asked what.

Acceptance:
- On by default, switchable in Settings, Speech. While a session runs, the other side's audio is kept in memory as 16 kHz mono (capped at one hour) and never written to disk.
- When the call ends, FluidAudio's diarizer (pyannote segmentation plus speaker embeddings, models downloaded once) works out who spoke when.
- Each saved "them" line is labelled by time overlap: Speaker 1 is whoever is heard first. Lines without timing keep "Them". My own lines stay "Me".
- Labels show in the saved meeting and its exported transcript text.

## S-027: The transcript follows the newest line

Status: doing (built 1.3.0)

As Nils, I want the transcript to run downward with the newest line always in view, and to stay scrollable.

Acceptance:
- New lines append at the bottom; while I am at the bottom, the view follows them, in the Live page and in the overlay.
- If I scroll up to read, new lines do not pull me back down. Scrolling back to the bottom resumes the follow.
- A growing partial line and a landing translation also keep the bottom in view while I am at the bottom.

## S-028: Screen Recording asks once, not every time

Status: doing (built 1.3.0; the signing half needs one Terminal run by Nils)

As Nils, I do not want to be asked for Screen Recording again when the app already has it.

Acceptance:
- Status checks use the preflight API, which never raises the dialog. Opening Settings or the Permissions tab asks nothing.
- Starting listening asks at most once per launch, through CGRequestScreenCaptureAccess, and only when the grant is truly missing for this binary. When it stays missing, the status line explains the fix instead of the capture re-asking on every start.
- build.sh prefers a stable "InterviewAI Local Signing" identity (scripts/create-signing-identity.sh, run once by Nils) so macOS keeps the grant across rebuilds; Apple Development next, ad hoc last.

## S-029: Corner menu in the sidebar foot

Status: doing (built 1.3.0)

As Nils, I want the small menu from the reference he sent, in the bottom-left corner: one round button, one dark card.

Acceptance:
- A round button with the three-lines mark sits at the foot of the sidebar, left of the status strip.
- It opens a dark card: Keyboard Shortcuts (with ⌘/), Report an Issue, a hairline, then Settings (with ⌘,).
- Keyboard Shortcuts opens a window listing the global hotkeys (⌘⇧L, ⌘⇧H, ⌘⇧S), the answer actions (⌘1 to ⌘7), Settings (⌘,), and the list itself (⌘/, also in the app menu).
- Report an Issue opens the repo's new-issue page with the app version already in the template.
- Settings opens the Settings scene, same as ⌘,.

## S-030: Bug round after the first evening of real use (1.3.1)

Status: doing (built 1.3.1)

Nils reported five dead ends in 1.3.0: Auto Answer never fired, the corner menu's Settings and Report an Issue did nothing, the overlay would not open or close, and the overlay's Send did nothing. Checks on his Mac showed: the app had quit with exit code 0 (closing the window quit the app, since terminate-after-last-window-closed was on), the Screen Recording grant did not cover the rebuilt binary so no other-side audio ever arrived (no settled line, so Auto Answer had nothing to fire on), the Settings scene and the overlay toggle both worked from the app menus, and Ollama was running.

Acceptance:
- Closing the main window no longer quits the app; it stays in the menu bar with hotkeys and any running session alive.
- A blocked Screen Recording start opens the exact Privacy pane where the tick goes, once per launch, and the status line says to quit and reopen after ticking.
- The Live page shows answer errors in red under the Answer heading, like the overlay already did, so a dead provider is never silent.
- Corner menu rows close the card first and run their action a beat later, so the dismissal cannot swallow the open.
- Pending Nils's live retest: Auto Answer on a real other-side line, overlay Send, corner Settings and Report an Issue.

## S-031: Reading and visibility settings from Interview Pilot (1.4.0)

Status: doing (built 1.4.0)

Nils sent a photo of Interview Pilot's settings and asked for the same four in InterviewAI's General tab.

Acceptance:
- Highlight Keywords (Reading, on by default): the bold terms and the figures in an answer get a yellow wash, on the Live page and in the overlay. The split into runs is pure Kit string work and unit-tested; no extra model call.
- Font Size (Reading): a slider from 14 to 24 pt with the value shown; it sets the answer text size on the Live page and in the overlay.
- Show in Dock (Visibility): off switches the app to accessory policy at once and on the next launch; the caption says a screen share can see it.
- Show Menu Bar Icon (Visibility): off removes the menu bar extra; the caption names what the icon is for and warns that the global hotkeys are the way back in when both icons are off.

## S-032: The menu bar icon loop (1.4.1)

Status: doing (built 1.4.1)

After its first healthy run, v1.4.0 stopped opening: every later launch pegged one CPU core, grew past 1.6 GB, and never showed a window. Pausing in the debugger showed the main thread inside SwiftUI's runloop flush, Auto Layout fitting-size work, and notification posts; asking the process for its windows showed exactly one: the NSStatusBarWindow of the menu bar extra. The 1.4.0 Show Menu Bar Icon toggle drove MenuBarExtra isInserted from an @AppStorage in the App struct, and that binding's defaults write-back during scene setup fed the loop. First launch was healthy because the key did not exist yet.

Acceptance:
- The icon flag lives on AppModel as a plain observable property, loaded from defaults once at init; the scene binding and the Settings toggle both go through it, and it writes defaults only on a real change.
- The app launches with a window and an idle CPU, twice in a row.
- Nils's defaults, emptied during the diagnosis bisect, are restored in full.

## S-033: The mic prompt held the whole session (1.4.2)

Status: doing (built 1.4.2)

On a build whose microphone access was not asked yet, Start Listening sat at "Starting" and nothing was heard, not even the other side. The start sequence awaited the microphone permission request before it started either channel, so an unanswered prompt (or one hidden behind another app) blocked the system audio too. The line "The other side will still be transcribed" was already in the code for a denied mic, but that path could never run while the prompt itself was still pending.

Acceptance:
- The other side and the system audio start at once, before any mic request.
- A granted mic starts the microphone right away. An unasked mic asks in the background and joins when allowed, only if that same session is still running.
- A denied mic posts the plain status and the session carries on with the other side only.

## S-034: Security audit fixes (1.4.3)

Status: doing (built 1.4.3)

A security audit of the whole app (report in the research notes, 2026-11-03) found no holes that expose the user: no secrets in source, keys only in the Keychain, no listener or webview, and the update checker only reads. Three small things were worth fixing the same night.

Acceptance:
- Package.resolved from the known-good build is committed, so a fresh clone builds the exact dependency versions that were reviewed, not whatever is newest that day.
- Keychain saves report failure: the store call returns its result, sets an explicit accessibility class, and both Save buttons in Settings show "Save failed" instead of claiming a save that never landed.
- The APP_STORE override only counts when it points into /tmp, matching what the dev tools' own messages promise; any other path is ignored and the real store opens.

## S-035: The Profile page could not see the resume (1.4.4)

Status: doing (built 1.4.4)

The Profile page said "No resume in Context yet." while the Context page held the user's CV, pinned. Context files were kinded from the file name only, and a CV named after its owner (Nils_Effmert.pdf) matches no name rule, so it sat at kind "general" and the Profile pickers, which filter by kind, never offered it.

Acceptance:
- Classification reads the text when the name says nothing: a resume or job description is recognised by its own markers, two or more with a clear winner, so mixed documents stay general (ContextClassifier, unit tested).
- Files already stored as "general" are reclassified once at launch; kinds set by hand afterwards are never touched again.
- The Context page row carries a kind menu (Resume, Job description, Notes, General), so any file can be corrected by hand; picking Resume or Job description also pins it.
- The Profile pickers still only offer files of the right kind.

## S-036: Summaries parroted the prompt (1.4.4)

Status: doing (built 1.4.4)

A saved meeting's Summary tab showed "### Shape: Summary: Summary: Summary: Decision: Action item:" instead of a summary: the local 3B model echoed the summary prompt's labelled template back as its answer.

Acceptance:
- The summary prompt is written as plain directions with no labels to echo, and tells the model to start directly with the summary text.
- SummaryCleaner strips a leading scaffolding block (headings, label-only lines, one leading "Summary:" on the first content line) from the stored summary and follow-up, so a bad generation can never be stored as-is (unit tested). The === separator keeps working.

## S-037: The other side failed in silence (1.4.4)

Status: doing (built 1.4.4)

Every saved meeting holds only microphone segments; the system-audio ("them") channel has never produced one, and the code could not say why: unreadable capture buffers were dropped uncounted, conversion failures returned empty blocks that were dropped uncounted, the capture stream had no delegate so a mid-call stop reported nothing, and a stream that started cleanly but delivered no audio looked exactly like a quiet call. LiveSession's segment intake is channel-agnostic and correct, and the microphone works through the same channel classes, so the loss sits between the ScreenCaptureKit stream and the channel's converter, in code that swallowed every failure.

Acceptance:
- The tap counts delivered and unreadable buffers; if buffers arrive but none can be read, the session status says so once.
- The tap is the stream's delegate; a stream that stops mid-call posts the error to the session status.
- Four seconds after a clean start with zero buffers delivered, the session status warns that no audio has arrived.
- Both chunk channels count conversion failures; if nothing at all converts, the session status says so once.
- The microphone path's behaviour is unchanged. Whether the channel now produces segments end to end is proven by the next live test on the signed build, not by this story.

## S-038: The overlay gets its own chrome, reporting moves into the app (1.4.5)

Status: doing (built 1.4.5)

Three complaints from use: the overlay's minimize and close buttons did nothing (a titled panel without closable or miniaturizable in its style mask), the overlay looked off (a system title bar sitting on a clear panel over the material body), and Report an Issue left the app for a browser page. The same round removes the Settings Appearance tab, fixes window sizes, and switches shortcut labels to keyboard symbols.

Acceptance:
- The overlay panel is borderless with one rounded material surface and a hairline. Its header carries collapse and close buttons that work: collapse shrinks the panel to the header bar and back, close hides it, and dragging the header moves it.
- Report an Issue opens a window in the app: a text box, the version, system, and engine attached on their own, and Send. With a GitHub token in the Keychain (Issues access, this repo), Send files the issue through the API and shows its number. Without one, Send opens the same report as a prefilled GitHub page, and the window offers the token field that turns the direct route on.
- Settings has no Appearance tab; the accent stays whatever theme was stored. All shortcut labels use symbols (⌘⇧H, ⌘1) instead of the word Command.
- Settings pages size to the screen's visible height, so the Providers page fits without scrolling on the Mac's display. The About and Shortcuts windows size to their content instead of a guessed height.
- The About window names the author, Nils Effmert, and carries Star and Follow buttons to the GitHub repo and profile.
- All in-app text checked against the Wikipedia signs of AI writing list: no em dashes in strings, no tell vocabulary, no negation tags.

## S-039: Reporting copies the reference window, files itself, and the public numbering starts at 1.0.0

Status: doing

The reference bug window sets the shape: a short form, a screenshot slot, Cancel and Submit. Ours should work the same way, and Submit should file the issue with one click and no token setup for the person reporting. The same round restarts the public version numbering: this app has never had a public release, so the first one is 1.0.0, and the GitHub history starts over from a single commit.

Acceptance:
- The Report window is titled Report a bug: "What went wrong?" text box, a Screenshot section with a Capture screen button and a preview (or "No screenshot attached"), then Cancel and Submit. Submit stays greyed until the text box has text.
- Capture screen steps the report window aside, photographs the main display, and attaches the picture to the report. Remove takes it off again.
- Submit posts the report to a small Cloudflare relay, which files it as a GitHub issue with the label from-app and, when attached, the screenshot stored on an issue-media branch and shown in the issue. The app holds no GitHub token. The token lives only as a secret on the relay: fine-grained, Issues and Contents on this repo only.
- The version is 1.0.0 in the app and the release. The repo history is one fresh commit; the old tags and releases are deleted.
