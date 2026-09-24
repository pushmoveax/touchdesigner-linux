<div align="center">

<img src="docs/assets/header.png" alt="" width="300">

# TouchDesigner on Linux

**Install TouchDesigner on Linux from nothing, and make it actually start.**

![license](https://img.shields.io/badge/license-MIT-blue)
![platform](https://img.shields.io/badge/platform-Linux-informational)
![via](https://img.shields.io/badge/via-Bottles%20%2B%20Wine-a0522d)

English · [Русский](README.ru.md)

</div>

![TouchDesigner 2025.33070 running on EndeavourOS](docs/assets/touchdesigner-on-linux.jpg)

<div align="center"><sub>

TouchDesigner 2025.33070 · EndeavourOS · KDE Plasma 6.6.5 on Wayland · RTX 2080 Ti · Bottles + Wine

</sub></div>

TouchDesigner has no Linux build. It runs well through Wine — once you get past
the part where it installs fine, launches, and then freezes on the splash screen
with no error, no crash dialog and nothing in the Bottles UI except **Not
responding**. There are five known causes. None of them are discoverable without
a Wine debug log, and the fix for the most common one is a single environment
variable that nobody tells you about.

This repository does the whole thing: installs Bottles, fetches a Wine runner,
creates the bottle, downloads TouchDesigner, installs it, applies every known
fix, and gives you a menu entry. If it still breaks, `td-doctor` tells you which
of the five it is.

## Quick start

You need no Wine knowledge, no Bottles setup, and no TouchDesigner download —
the installer is fetched for you. A Derivative account is **not** required to
download it (you will need a licence, free non-commercial included, to *use* it).

```sh
git clone https://github.com/pushmoveax/touchdesigner-linux.git
cd touchdesigner-linux
./install.sh          # put the commands on your PATH
td-setup              # do everything
```

`td-setup` walks eight steps and tells you what it is doing at each one. Budget
about 3 GB of download, 16 GB of free disk while it runs, and 20-30 minutes
for the install itself. The bottle settles at roughly 9 GB afterwards. To see
the plan without touching anything:

```sh
td-setup --dry-run
```

![td-setup --dry-run](docs/assets/td-setup.png)

Then:

```sh
touchdesigner         # or use the application menu entry
```

<details>
<summary>What td-setup actually does</summary>

1. **Prerequisites** — `curl`, `tar`, `python3`, free disk space, and whether
   your Vulkan driver works. DXVK cannot work without Vulkan, so this is checked
   before anything is downloaded.
2. **Bottles** — installs it from Flathub if you do not have it.
3. **Wine runner and DXVK** — reuses what Bottles already has, or downloads the
   latest [Soda](https://github.com/bottlesdevs/wine) runner and
   [DXVK](https://github.com/doitsujin/dxvk) release.
4. **Bottle** — creates a 64-bit bottle with DXVK enabled.
5. **Installer** — downloads the official TouchDesigner build from
   `download.derivative.ca`, resumable, and verifies the size.
6. **Install** — runs the installer inside the bottle. It is a 7-Zip SFX around
   an Inno Setup installer and the silent switches reach the inner one, so
   nothing needs clicking — but budget **20-30 minutes**: under Wine it unpacks
   ~2.9 GB into the prefix and then writes ~8 GB of small files.
7. **Fixes** — patches the IDS Peak DLLs, and arranges for
   `MIMALLOC_DISABLE_REDIRECT=1` at launch. See
   [`docs/known-issues.md`](docs/known-issues.md) for why.
8. **Launcher** — `touchdesigner` on your PATH plus a desktop entry with the real
   application icon, pinned to the bottle it just built.

Every step checks whether it is already done, so re-running after an interrupted
attempt resumes rather than restarts. A half-finished download continues from
where it stopped.

</details>

### Options you may want

```sh
td-setup --build 2026.10000            # a specific TouchDesigner build
td-setup --installer ~/TD.exe          # an installer you already downloaded
td-setup --bottle my-td                # name the bottle
td-setup --dir 'C:\Apps\TD'            # install somewhere else in the bottle
td-setup --yes                         # no prompts
```

Build numbers come from <https://derivative.ca/download>. Derivative removes old
builds from the download host, so if the default build has aged out `td-setup`
says so and asks for `--build`.

## Already have TouchDesigner installed?

Then skip `td-setup`. This is the other half of the repository:

```sh
td-doctor              # what is wrong with this machine?
td-doctor --log        # why did the last run die?
```

`td-doctor` only ever reads. It inspects your system, GPU, session, bottle,
runner, DXVK, TouchDesigner build and the DLLs known to break, then prints the
exact command for each problem it finds. Nothing changes unless you run it.

![td-doctor](docs/assets/td-doctor.png)

### When it hangs and you have no idea why

```sh
td-launch --debug      # reproduce with a verbose Wine log
td-doctor --log        # match the log against known crash signatures
```

The log is always kept at `~/.local/state/td-linux/last-run.log`, so you can
analyse a crash after closing the terminal. `td-doctor --log` recognises the
mimalloc/DWrite hang, `ids_peak` faults, font-stack faults, unresolved imports
and DXVK device-creation failures, and tells you which one you hit.

## The fixes, in one table

`td-setup` applies all of these. This is what they are.

| Symptom | Cause | Fix |
| --- | --- | --- |
| Hangs on splash, ~`1/72`, no error | `mimalloc-redirect.dll` patches malloc for Wine's `DWrite.dll`, which then faults with `0xc0000005` while enumerating fonts | `MIMALLOC_DISABLE_REDIRECT=1` |
| Dies early in startup, `ids_peak_*.dll` in the backtrace | Wine runs `DllMain` of the bundled IDS Peak camera SDK and it faults | Zero `AddressOfEntryPoint` in those four DLLs |
| Window opens but never becomes interactive (KDE/Wayland) | Wine's Wayland driver | `WAYLAND_DISPLAY=""`, forcing XWayland |
| Compositor stutter or lockups on NVIDIA | driver busy-waiting on the compositor | `__GL_YIELD=USLEEP` |
| UI renders in the wrong font | Wine font substitution | `wine_ui_fixes.tox` |

[`docs/known-issues.md`](docs/known-issues.md) has the detail: log signatures,
why each fix works, and where each one came from.
[`docs/install.md`](docs/install.md) is the same install done by hand, if you
would rather not run a script that installs things.

## The commands

| Command | Does |
| --- | --- |
| `td-setup` | Installs everything from nothing. Idempotent, resumable, `--dry-run`. |
| `td-doctor` | Inspects the machine and prints the fix for each problem. Read-only. |
| `td-doctor --log [FILE]` | Matches a Wine log against known crash signatures. |
| `td-launch` | Starts TouchDesigner with the working environment. Every fix can be disabled individually to bisect a setup. |
| `td-patch-ids-peak` | Zeroes `AddressOfEntryPoint` in the IDS Peak DLLs, with backups and `--restore`. |
| `install.sh` | Puts the above on `PATH`, adds the desktop entry. `--uninstall` reverses it. |

`install.sh` symlinks into `~/.local/bin`, so keep the clone where it is (or
re-run it after moving). It never overwrites a file you wrote yourself —
anything in the way is kept as `.bak`.

Requirements: `bash`, `python3`, `curl`, `tar`, `flatpak`. Optional:
`vulkan-tools` so the doctor can verify Vulkan, `icoutils` so the installer can
pull the icon out of `TouchDesigner.exe`.

## Verified configurations

See [`docs/compatibility.md`](docs/compatibility.md). Adding your machine is the
single most useful contribution — `td-doctor` prints everything the table needs.

## Credits, and what this is not

The fixes are the TouchDesigner-on-Linux community's, not ours. This repository
automates them and adds the diagnosis step that was missing.

- [iswad-lab/TouchDesigner-Linux](https://github.com/iswad-lab/TouchDesigner-Linux)
  — the established automated installer, with multi-version support, icons and
  UI/font fixes. **If you want a polished installer, use theirs.** This project
  overlaps with it deliberately on setup, and differs in going after the
  *diagnosis*: `td-doctor` reads your machine and your Wine log and names the
  failure, instead of applying a fixed list of fixes and hoping.
- [bluejorts' Proton 10 gist](https://gist.github.com/bluejorts/91e86a41099966b11e7248f52ac38e28)
  — where the mimalloc/DWrite hang and `MIMALLOC_DISABLE_REDIRECT=1` were
  documented first.
- [Claudius Coenen, *TouchDesigner on Linux using Bottles and Wine*](https://www.claudiuscoenen.de/2024/09/touchdesigner-on-linux-using-bottles-and-wine/)
  — origin of the `AddressOfEntryPoint` trick for the IDS Peak DLLs.
- Derivative forum threads:
  [Experimental setup via Bottles](https://forum.derivative.ca/t/experimental-setup-touchdesigner-on-linux-via-bottles-2025-10-04/809825),
  [Daily-driver setup](https://forum.derivative.ca/t/running-touchdesigner-on-linux-via-bottles-my-daily-driver-setup/978051),
  [Minor UI fixes on Wine](https://forum.derivative.ca/t/minor-ui-fixes-for-touchdesigner-on-wine-2025-11-29/973692).

TouchDesigner is a product of [Derivative](https://derivative.ca). This project
is unaffiliated with them, and running TouchDesigner on Wine is not something
they support. You still need a licence to use it; the free non-commercial one is
enough.

Artwork: the TouchDesigner icon in the header is taken from `TouchDesigner.exe`
and belongs to Derivative, used here only to identify the application. Tux is by
Larry Ewing, created with The GIMP.

## License

MIT — see [`LICENSE`](LICENSE).
