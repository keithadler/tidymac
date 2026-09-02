# Contributing to Tidy for Mac

Thanks for looking. Tidy for Mac is small on purpose: one Swift package, no dependencies, no Xcode project.
Anything that keeps it that way is welcome.

## Ground rules that keep it family-safe

These are not style preferences; they are the reason people can trust the app. A pull request that
bends one needs a very good argument.

1. **Never delete.** Everything the user removes goes through `FileManager.trashItem`. If macOS
   refuses, report it and move on. `rm`, `removeItem`, and friends are not used on user data.
2. **Every action leaves a receipt.** Anything moved gets a `TidyRecord` in a `TidySession`
   (see `History.swift`), so "What Tidy for Mac did" can put it back.
3. **Pre-checked means regenerable.** Only files an app will rebuild on its own are checked by
   default. If you can't say in one sentence why the file is safe, it belongs in a
   "take a look first" card, unchecked.
4. **No sudo, ever.** If something needs an administrator, hand the user a copyable command
   and say so. The app never asks for a password.
5. **Plain language.** Card titles and explanations are written for someone's parents. No
   jargon in anything a user reads; jargon in code comments is fine.
6. **Say what you don't know.** If a check can't be made on some hardware (SMART on Apple
   Fabric storage, for example), show "not reported" rather than a guess.

## Building

```bash
./build-app.sh --install --run
```

The command line lets you check scanners without a screen (see docs/CLI.md):

```bash
.build/debug/TidyMac scan
.build/debug/TidyMac speed --all --bench --app-updates --updates
.build/debug/TidyMac disk
```

## Adding a cleanup card

1. Add a case to `CleanKind` in `CleanupModel.swift` with title, blurb, icon, safety, and scanning label.
2. Add a `scanX()` in `Scanner.swift` returning `[CleanItem]`. Give every item a `why`.
3. Add a color in `Tidy.color(for:)` in `CleanupView.swift`.
4. Add an alias in `CLI.scanAliases`, then run `tidymac scan` and read the `[x]` lines. Anything pre-checked must survive rule 3 above.

## Adding a Speed card

1. Put the data gathering in `SystemInfo*.swift` as a pure function returning `Sendable` values.
2. Add state and a refresh call to `SpeedModel.swift`.
3. Add the card view to `SpeedView*.swift` using `SpeedCard`, and slot it into the list in `SpeedView.swift`.
4. Add the card to `CLI.speed` (text and `--json`) so it can be verified and scripted from the terminal, and document it in `docs/CLI.md` and `docs/tidymac.1`.

## Translations

Strings live in `Localization/<lang>.lproj/Localizable.strings`, keyed by the English text.
Copy `es.lproj` to start a new language. The build script copies every `.lproj` into the app.
