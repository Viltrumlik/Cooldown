# Contributing to Cooldown

Thanks for helping! Cooldown deletes files on other people's Macs, so the bar for safety is high and the bar for everything else is low.

## Setup

```bash
git clone https://github.com/Viltrumlik/cooldown.git
cd cooldown
swift test
swift run Cooldown          # quick run, no .app bundle
./scripts/build-app.sh      # real .app in build/
```

You can also open `Package.swift` in Xcode.

## Adding a cache folder

Most new targets are a single `DirectoryTarget` entry in [`Sources/CooldownCore/Targets/Catalog.swift`](Sources/CooldownCore/Targets/Catalog.swift):

```swift
DirectoryTarget(
    info: TargetInfo(
        id: "deno.cache",                   // stable, never rename
        title: "Deno cache",
        detail: "Downloaded modules. Deno fetches them again when needed.",
        group: .javascript,
        risk: .safe,
        enabledByDefault: true
    ),
    roots: ["Library/Caches/deno"],        // relative to ~
    home: home
),
```

Rules:

1. **`detail` says what happens after cleaning**, in one sentence.
2. **`risk: .caution` and `enabledByDefault: false`** for anything that costs a re-download, a slow rebuild or cannot be undone. A test enforces this.
3. **Roots must be inside `~`** and must not be a protected folder (see `PathGuard.protectedRelativePaths`). Never widen `PathGuard` to make a target work.
4. **Prefer the tool's own cache folder** over a parent folder. If a root contains folders owned by another target, exclude them with `excludingNames:`.
5. If a target needs a command (like `xcrun simctl`), implement `CleanTarget` in its own file, keep `scan()` read-only, and make sure the command can't trigger an install prompt on Macs without the tool.

## Pull requests

- Run `swift test` before pushing; CI runs it on macOS too.
- Parsers for command output go in `Monitor/Parsers.swift`, with a test that uses real captured output.
- Keep the UI change small and include a screenshot.

## Reporting a bug

Open an issue with your macOS version, your Mac model (Intel or Apple Silicon), and what you expected to be cleaned compared to what was cleaned.
