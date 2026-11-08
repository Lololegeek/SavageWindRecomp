# Updating Savage Wind

An update only replaces Savage Wind's own files. Your game files (copied at setup), the game code built from them,
the caches, saves and settings stay where they are.

## Windows

Run `Update Savage Wind.bat` in your Savage Wind folder (next to `savagewind.exe`). It:

1. reads the newest release on GitHub (`Lololegeek/SavageWindRecomp`, then `Revivedx/SavageWindRecomp` if that one
   has none) and stops if you have it already;
2. waits for Savage Wind to be closed;
3. downloads `SavageWind-<version>-windows.zip` and copies its files over your folder. `swgen\`, `zig\`,
   `gamelib-src\` and `colour-luts\` are mirrored (files an older version left there are removed). Nothing else is
   deleted, and it never touches `extracted\`, `swgame.dll` and its `.id`, `cache\`, saves, settings or logs;
4. starts Savage Wind with `SAVAGEWIND_AUTO_REBUILD=1`. If the new version's game code is different, the start screen
   builds it again from the files you copied already. There's no copy and no extraction, and every piece of game code
   whose C didn't change comes from `cache\gamecode\`.

Options (pass them to the `.bat` or to `update.ps1`):

| option | |
|---|---|
| `-Stable` | releases only, no pre-releases |
| `-Repo owner/name` | another repository's releases |
| `-Zip file.zip` | a release zip you downloaded already |
| `-From folder` | a folder built with `make dist` (`build\dist\Savage Wind`) |
| `-Check` | only says whether there's an update |
| `-Backup` | keeps the replaced files in `update-backup\<old version>\` |
| `-NoLaunch` | doesn't start Savage Wind afterwards |
| `-Force` | installs even when the version is the same |

The version installed is written to `savagewind-version.txt`.

No GitHub account or token is needed: the releases are public, read through GitHub's API without signing in. That
API allows 60 requests an hour per IP address, and a check uses one or two; if you hit the limit (on a shared
network), a token in `GITHUB_TOKEN` raises it, and nothing else uses it.

If the folder is older than the updater, copy `tools\update.ps1` and `tools\Update Savage Wind.bat` next to
`savagewind.exe` once.

## Linux (AppImage)

Your data lives in `$XDG_DATA_HOME/savagewind` (`~/.local/share/savagewind`), not in the AppImage, so an update is
only a new AppImage:

```sh
tools/update.sh path/to/Savage_Wind-<version>-x86_64.AppImage
```

It downloads the newest AppImage for your CPU next to the old one, keeps the old one as `.old`, and starts the new one
with `SAVAGEWIND_AUTO_REBUILD=1`. `SAVAGEWIND_REPO`, `SAVAGEWIND_STABLE=1` and `SAVAGEWIND_NO_LAUNCH=1` work like the
Windows options.

## Building the game code again without the updater

`SAVAGEWIND_AUTO_REBUILD=1` also works on its own: when the start screen says "Game code built for another version"
or "Game code not built yet" and the copied game files are complete, it starts building right away instead of waiting
for Set up game files.
