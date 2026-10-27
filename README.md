# BlueSpark for Linux

[BlueSpark](https://github.com/avim2/BlueSpark) (Tekken Tag Tournament 2, natively recompiled from the Xbox 360,
with rollback netcode, ranked and a Tekken 8 style training mode) on Linux and the Steam Deck.

This fork adds only the `linux/` folder. The game itself is the original project's: the installer downloads the newest
official release from [avim2/BlueSpark](https://github.com/avim2/BlueSpark), checks its signature exactly like Start
Here does on Windows, and builds the very same `ttt2.exe` (same compiler, same Microsoft libraries, same translated
code). So **you play online with Windows players**, and every new release of the original reaches you by itself.

## What you need

- **Steam** (Flathub or your distribution's), started once and logged in.
- **Proton**: GE-Proton through **ProtonUp-Qt** (in your software center) is recommended. A GE-Proton build with
  hardware FMA is used first when you have one.
- **Your own copy of the game**: an image of your Tekken Tag Tournament 2 disc (Xbox 360, `.iso`, title 4E4D0859).
- **Your title update 0.0.3.2**: the file `TU_174Q22P_0000008000000.00000000000O2` (about 3 MB) from your Xbox 360's
  hard drive (`Content/0000000000000000/4E4D0859/000B0000/`).
- About 20 GB of free space, and a controller or a keyboard.

No game files are in this repository, and there never will be.

## Install

Open a terminal, paste this line and press Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/weise25/BlueSpark-linux/main/linux/install.sh | bash
```

It asks for your disc image and title update (it finds them by itself when they're in your Downloads, Games or
Documents folder), for Microsoft's license (the build needs Microsoft's C++ libraries, as on Windows) and for your name.
The first time it downloads about 2 GB and takes 5 to 10 minutes. Then Steam has
**Tekken Tag Tournament 2 (BlueSpark)** in its library: press Play.

Everything goes in `~/Games/BlueSpark`. To use another folder, put `BLUESPARK_DIR=/your/folder` in front of `bash`.

## Updates

Nothing to do: each time you start the game from Steam, it checks the original project for a new release, downloads
it, checks it and rebuilds (a window shows the progress, a few minutes). Your saves, profile and settings stay.

## Settings

`~/Games/BlueSpark/rex/userdata/launcher-settings.txt`, one per line, as Start Here writes them on Windows:

| Line | What it does |
| --- | --- |
| `display=windowed-1920x1080` | a window (`borderless` is the default, `fullscreen` the exclusive mode) |
| `online=false` | offline only |
| `keyboard=false` | no keyboard as player 1 |
| `vibration=true` | controller vibration |
| `nointro=false` | the game's own intro |
| `autoupdate=false` | no update check at the start |

Keys, controllers and everything else: the `README.txt` that comes with the game, in `~/Games/BlueSpark`.

## If something goes wrong

The logs are in `~/Games/BlueSpark/data/logs` (install, updates, build) and
`~/Games/BlueSpark/rex/out/build/win-amd64-release/logs` (the game). Running the install line again repairs what's
missing. Report Linux problems here, in this fork's issues, not to the original project.

---

## Deutsch, kurz

1. Steam installieren und einmal starten, mit **ProtonUp-Qt** GE-Proton hinzufügen.
2. Terminal öffnen, die Zeile oben unter **Install** einfügen, Enter.
3. ISO und Title Update auswählen, Microsofts Lizenz bestätigen, Namen eingeben.
4. In Steam **Tekken Tag Tournament 2 (BlueSpark)** starten. Updates kommen von allein, Online-Spiel mit
   Windows-Spielern funktioniert.

## How it works

- `linux/install.sh`: the one-time setup above.
- `linux/play.sh`: what Steam starts. Checks for updates, then starts `ttt2.exe` through Proton with the same
  switches as Start Here's Play TTT2.
- `linux/update.sh`: the original project's feed (`latest.json`), and the Linux scripts from this fork.
- `linux/build.sh`: Start Here's steps 1 to 3. LLVM 20.1.8 and xwin cross-compile the Windows `ttt2.exe` on Linux,
  the code translator `rexglue.exe` runs through Proton's wine, and the same checks as on Windows (the translation
  must match the release byte for byte, every hook must link).
- `linux/tools/`: the disc image extractor, the package signature check, the Steam shortcut.

Keeping this fork in sync: GitHub's **Sync fork** button. The original's files are never changed here, so it never
conflicts.
