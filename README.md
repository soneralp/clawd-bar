# Clawd Bar

A tiny macOS menu bar app that tells you, at a glance, whether your
[Claude Code](https://claude.com/claude-code) sessions are working, waiting
for you, or done, so you can stop switching back to the terminal to check.

![The four states of the menu bar icon](docs/images/states.png)

| Icon | Meaning |
|------|---------|
| Gray, eyes closed | No Claude Code sessions are running |
| Orange, pulsing | At least one session is working |
| Yellow, with project name | A session needs you: a permission prompt, a question, or an input dialog |
| Green | Every session has finished its turn |

The most urgent state wins. When a session is waiting, its project name
appears next to the icon (`my-app +1` if more than one is waiting).
Click the icon for a per-session list with what each one is doing and for how
long. Clicking a row brings Warp to the front.

## Requirements

- macOS 14 Sonoma or later
- Xcode 15.3 or later (Swift 5.10+) to build
- Claude Code with hooks support

## Install

```sh
git clone <repository-url> clawd-bar
cd clawd-bar
make install          # builds, copies to /Applications and launches
```

Then click the icon and choose **Install Claude Code Hooks…**. Claude Code
reads hooks when a session starts, so restart any sessions that are already
running.

Optional toggles in the menu:

- **Notify When Waiting or Done** sends a macOS notification on those transitions.
- **Play Sound** plays a short chime on the same transitions.
- **Launch at Login** registers the app as a login item.

## How it works

```
Claude Code ──hook event (JSON on stdin)──▶ clawd-hook ──writes──▶ ~/.claude/clawd-bar/sessions/<id>.json
                                                                              │
                                                     Clawd Bar ◀──watches─────┘
```

- **`clawd-hook`** is a small command-line tool bundled inside the app. Claude
  Code runs it for a dozen [hook events](https://code.claude.com/docs/en/hooks)
  such as `UserPromptSubmit`, `PermissionRequest`, `Notification`, `Stop`, and
  `SessionEnd`. It maps each event to a state and atomically writes one JSON
  file per session, under a per-session file lock. It never prints to stdout
  and always exits 0, so it cannot change what Claude does. It does run
  synchronously, which adds a few milliseconds per tool call.
- **Clawd Bar** watches that directory, aggregates the files, and renders the
  icon and menu. Every 15 seconds it also drops sessions whose Claude process
  has exited without sending `SessionEnd`.
- **Installing hooks** adds entries to `~/.claude/settings.json` that call
  `~/.claude/clawd-bar/bin/clawd-hook`, a symlink into the app bundle. Existing
  hooks and settings are preserved, and a symlinked `settings.json` stays a
  symlink. Before the first change, the original file is saved as
  `settings.json.clawd-backup`. If the app is deleted without removing its
  hooks, the hook command quietly does nothing.

## Known limitations

- **Warp tab focus.** Warp has no scripting API for selecting a tab, so clicking
  a row activates Warp but cannot jump to the exact tab.
- **Yellow lingers after approval.** Claude Code does not emit an event when you
  approve a permission prompt. The icon turns orange again when that tool call
  finishes.
- **Interrupting with Esc.** Cancelling a prompt or a running turn sends no
  event. The session keeps its last state until your next message, or until
  Claude Code's idle reminder for a turn that was running.
- **Headless runs count.** `claude -p` invocations from scripts also appear,
  since hooks cannot tell interactive and headless sessions apart.

## Development

```sh
make test             # unit tests for the core logic
make app              # build "build/Clawd Bar.app"
make run              # build and open it
```

The code is split into three targets:

- `ClawdCore`: the platform-independent state machine, storage, and aggregation. Fully unit tested.
- `clawd-hook`: the hook executable.
- `ClawdBar`: the AppKit menu bar app.

## Uninstall

Choose **Remove Claude Code Hooks** from the menu, quit the app, then run
`make uninstall` and delete `~/.claude/clawd-bar`. Running sessions keep
their old hook configuration until they restart.

## License

MIT. Clawd Bar is an independent project and is not affiliated with Anthropic.
