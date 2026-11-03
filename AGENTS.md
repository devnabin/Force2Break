# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, Cursor, etc.) working on Fore2Break.

## Rule: comment every update

Every time you change code, put a short comment **at the top of the code you changed**: above the function, type, or block you added or edited.

Format:

```swift
// UPDATE YYYY-MM-DD: <what changed> — <why, in simple words>
```

Examples:

```swift
// UPDATE 2026-11-03: Added a 30-second warning before the break — so the user can finish what they're doing.
private func showBreakWarning() { ... }

// UPDATE 2026-11-03: Focus now restarts after 5 minutes away — time away already rested the eyes.
private func checkForAway(at instant: Date) { ... }
```

- Use today's date.
- Write in simple, plain language that someone new to the code can understand.
- One line is enough. Use two only if the reason really needs it.
- New files get one `UPDATE` comment at the top of the file.
- If code already has an `UPDATE` comment and you change it again, add a new line above the old one. Keep the old one so the history stays readable.
- Shell scripts use `#` instead of `//`.

## Project

Fore2Break is a native macOS menu bar app (Swift, AppKit + SwiftUI, macOS 13+). It times focus sessions and covers every display with a break screen.

| Path | What it is |
| --- | --- |
| `Source/Fore2BreakApp.swift` | App delegate: menu bar, windows, timer loop |
| `Source/Views.swift` | SwiftUI setup popup and break screen |
| `Source/SessionEngine.swift` | Focus/break state machine (no UI) |
| `Source/AutoResumeGate.swift`, `AwayDetector.swift`, `CallHold.swift`, `DailyRounds.swift` | Small testable logic pieces |
| `Source/ActivitySource.swift`, `CallSource.swift` | Read system state (input counts, display/camera/mic in use) |
| `Tests/` | Standalone test programs, one per logic file |

## Build and test

```bash
./build.sh                  # builds dist/Fore2Break.app
./test.sh                   # runs all unit tests
RUN_UI_TESTS=1 ./test.sh    # also runs the app's integration tests (briefly shows break screens)
```

- Run `./test.sh` and `./build.sh` before saying a change is done.
- New logic goes in a small struct with its own test file in `Tests/`, added to `test.sh`.
- New system frameworks must be added to both `swiftc` lines in `build.sh`.

## Commits

- Commit only when the user asks.
- Write commit messages in simple, easy-to-understand language: a `FEATURE:` or `FIX:` title, then a short plain explanation of what changed for the user.
