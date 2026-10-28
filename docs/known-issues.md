# Known issues

Each section: what you see, what it looks like in a Wine log, why it happens,
and what to do.

`td-setup` applies all of these when it installs TouchDesigner, and `td-doctor`
checks for all of them on an install you already have. This page is the
reasoning behind both, and what you need if you are fixing things by hand —
see [`install.md`](install.md) for the manual route.

---

## Hangs on the splash screen (`mimalloc` + `DWrite`)

**Symptom.** The splash screen stops, usually on a line like

```
1/72 insert a new node along a wire
```

No error, no crash dialog. The process is still alive and one thread is burning
CPU. Bottles' task manager says **Not responding**. Killing and restarting
always stops in the same place.

**Log signature.** With `WINEDEBUG=+seh`:

```
warn:seh:dispatch_exception backtrace: --- Exception 0xc0000005.
  addr=00006FFFFF1D248B
  mimalloc.dll + 0x248B
  DWrite.dll + 0x2AB2A
  DWrite.dll + 0x406C3
  libTD.dll + ...
```

An access violation whose innermost frame is `mimalloc.dll`, reached through
`DWrite.dll`.

**Cause.** TouchDesigner ships its own allocator, `mimalloc.dll`, plus
`mimalloc-redirect.dll`. The redirect DLL rewrites the malloc/free imports of
*every* module in the process, not just TouchDesigner's own. Wine 10's
`DWrite.dll` (DirectWrite, the font stack) allocates in a way the redirection
does not survive, so when a project load triggers font enumeration, the
redirected allocation dereferences an invalid address. TouchDesigner's structured
exception handler catches the fault but cannot recover, and the load never
finishes — which is why it presents as a hang and not a crash.

Wine 9-based runners are not affected, which is why "it used to work" and
"downgrade your runner" both show up as folk advice.

**Fix.** mimalloc itself provides the off switch:

```sh
MIMALLOC_DISABLE_REDIRECT=1
```

mimalloc then manages only TouchDesigner's own allocations and leaves everybody
else, including Wine's DirectWrite, alone. Nothing is deleted or patched, and
TouchDesigner still gets its allocator. `td-launch` sets this by default;
`TD_KEEP_MIMALLOC=1` turns it back off if you want to reproduce the bug.

Do **not** delete `mimalloc.dll`. TouchDesigner links against it.

---

## A real project never opens (Wine 11 runners)

**Symptom.** TouchDesigner starts, the splash screen reaches **99%** with your
project's name on it, and stops there. No error, no dialog. The process stays
alive but uses **no CPU at all** — every thread is parked. Waiting does not help;
it is a deadlock, not slow loading.

An empty or near-empty project still opens normally, which makes it look like
TouchDesigner is healthy and your file is broken. It is not.

**Measured on `soda-11.0-10`,** launched with `MIMALLOC_DISABLE_REDIRECT=1`:

| Project | Size | Result |
| --- | --- | --- |
| `Samples/Setup/Base/NewProject.toe` | 770 B | opens in 20 s |
| `Samples/Setup/Example/NewProject.toe` | 1 858 B | opens in 20 s |
| a project saved from the UI | 87 KB | 99%, deadlocked |
| a real community project | 120 KB | 99%, deadlocked |
| `Samples/DomeViewer/DomeViewer_LinesDemo.toe` | 122 KB | exits without a dialog |

**Cause.** Wine 11's DirectWrite corrupts the process heap while TouchDesigner
rasterises interface text during the load. The damage surfaces either as a
deadlock on an allocator lock, or as a crash the next time that heap is touched.

With `WINEDEBUG=+seh` the crash form appears instead of the hang, and the
backtrace is explicit:

```text
Exception 0xc0000005
  ntdll.dll  + 0x52418      <- RtlFreeHeap + 0x2A8
  ntdll.dll  + 0x267E8      <- RtlFreeHeap
  DWrite.dll + 0x2B08A      <- glyphrunanalysis_CreateAlphaTexture
  DWrite.dll + 0x406C3      <- rendertarget_DrawGlyphRun
  libTD.dll  + 0x159C81C
```

The faulting instruction is `testb $0x1, 0x7(%rax)` — the heap walking a block
header while freeing. `rax` is the block pointer plus a block size of `0xFF140`,
roughly a megabyte, which puts the "next block" outside the committed segment.
The size field had been overwritten: a buffer overflow earlier in DirectWrite's
glyph rasterisation, not a bad pointer at the free site.

`MIMALLOC_DISABLE_REDIRECT=1` does not cure this. It only decides *which*
allocator dies — with the redirect on, the same backtrace ends in
`mimalloc.dll + 0x2693` instead of `RtlFreeHeap`.

**Fix.** Use a Wine 9 runner. On the Bottles runner `soda-9.0-1` the same
projects open on the same prefix:

| Project | `soda-11.0-10` | `soda-9.0-1` |
| --- | --- | --- |
| 770 B template | opens, 20 s | opens |
| 87 KB saved project | 99%, deadlocked | opens |
| 120 KB community project | 99%, deadlocked | opens in 70 s |

Install it from
[bottlesdevs/wine](https://github.com/bottlesdevs/wine/releases/tag/soda-9.0-1)
into `~/.var/app/com.usebottles.bottles/data/bottles/runners/`, then set
`Runner: soda-9.0-1` in the bottle — in the Bottles UI, or in `bottle.yml`.
`td-setup` installs this runner; `td-doctor` warns when a bottle is on a Wine 11
runner.

**One wrinkle when you switch.** The first launch after a runner change runs
`wineboot --init`, whose 32-bit `wine.inf` step (`rundll32 ... Wow64Install`)
hangs under `soda-9.0-1` and sits at 0% CPU forever. The 64-bit side of the
prefix is already updated by then and `.update-timestamp` has been written, so
it does not repeat. Kill the stuck `wineboot.exe` and `rundll32.exe`, and launch
TouchDesigner normally.

**If you are testing this yourself**, do not use `WINEDEBUG=+seh`. The tracing
changes the timing enough to turn the deadlock into the heap crash, which makes
runs look inconsistent and sent an earlier version of this page chasing the
wrong cause. Measure at the default log level and judge by whether the main
window appears.

Ruled out along the way, each with a control run afterwards to prove the prefix
was still healthy:

| Attempt | Result |
| --- | --- |
| `MIMALLOC_DISABLE_REDIRECT=1`, both on and off | no change |
| `WINEDLLOVERRIDES=dwrite=d` | worse — startup stops earlier |
| `WINEDLLOVERRIDES=d2d1=d` | no change |
| wined3d instead of DXVK (confirmed in the log) | no change |
| Windows 7 mode | no change |
| `taskset` to one and two cores | no change |
| every host font hidden, via `FONTCONFIG_FILE` and the prefix registry | no change |
| `wine_ui_fixes.tox` injected via `toeexpand`/`toecollapse` | no change |
| Wine 9.22 Staging, in its own prefix | no change — a different build from `soda-9.0-1` |
| Wine 11.9 Staging | cannot run TouchDesigner at all here, so inconclusive |

The `.tox` injection is worth explaining, because it looks like it should help:
it switches Text TOPs to the Scalable renderer, which avoids DirectWrite. Its
script runs from `onStart`, which is after the load that fails.

[iswad-lab/TouchDesigner-Linux](https://github.com/iswad-lab/TouchDesigner-Linux)
reports the same thing independently — Soda 11 "freezes during project load" —
and points at
[DAW-GE-Proton11-6c](https://github.com/KitsuneDev/daw-proton-ge) as a Wine 11
build carrying a DirectWrite glyph-bitmap-cache patch, for anyone who needs
Wine 11 for other reasons.

---

## The file dialog is Wine's, not your desktop's

**Symptom.** TouchDesigner's Open/Save dialog is Wine's reimplementation of the
Windows one: no thumbnails, no places sidebar you recognise, and your files sit
behind `C:` → `users` → `<name>` or a walk down `Z:`.

**Cause.** Wine implements the Windows common dialog itself. Handing the job to
the desktop through `xdg-desktop-portal` exists only as an unmerged patch
series ([Wine bug 51134](https://bugs.winehq.org/show_bug.cgi?id=51134)), so
there is nothing to switch on.

**What helps.**

```sh
td-link-home
```

points the bottle's `Desktop`, `Downloads`, `Documents`, `Pictures`, `Videos`
and `Music` at your real folders and adds an `H:` drive for your home
directory, so the dialog's shortcuts and drive list land where your files
actually are. A folder that already holds something is left alone, and `--undo`
reverses it.

Better still, avoid the dialog: `install.sh` registers `.toe` and `.tox` as file
types and makes TouchDesigner their default application, so you can browse in
Dolphin, Nautilus or Thunar — with previews — and open a project by
double-clicking it.

---

## Crash during startup in `ids_peak_*.dll`

**Symptom.** TouchDesigner dies early, often before any window appears.

**Log signature.** An access violation with `ids_peak_afl.dll`,
`ids_peak_comfort_c.dll`, `ids_peak_ifl.dll` or `ids_peak_ipl.dll` in the
backtrace, or a `+loaddll` trace that stops right after loading one of them.

**Cause.** TouchDesigner bundles the IDS Peak industrial-camera SDK. Wine calls
`DllMain` on those libraries at load time and their initialisation code faults
under Wine.

**Fix.** Zero `AddressOfEntryPoint` in the PE optional header. The loader then
maps the DLL and resolves its exports as usual but never calls `DllMain`, so the
faulting initialisation simply does not run. The field sits at
`*(uint32*)0x3C + 40` in the file.

```sh
td-patch-ids-peak <TouchDesigner bin dir> --check   # look first
td-patch-ids-peak <TouchDesigner bin dir> --apply   # patch, with .bak backups
td-patch-ids-peak <TouchDesigner bin dir> --restore # undo
```

`ids_peak.dll` itself is deliberately left alone: it loads cleanly and is not
part of the established fix. `--include-base` opts into it if you want to
experiment.

If you use an actual IDS Peak camera in TouchDesigner, this patch will most
likely break it. Everyone else loses nothing.

**Note.** This fix and the mimalloc one are independent. Patching the IDS Peak
DLLs does not cure the splash-screen hang, and a machine can need both.

---

## Window opens but never becomes interactive (KDE Plasma / Wayland)

**Symptom.** A TouchDesigner window appears, possibly at a silly size, and never
responds. Or the whole session stutters while TouchDesigner is running.

**Cause.** Wine's native Wayland driver is still young, and TouchDesigner is not
a gentle test case.

**Fix.** Force the X11 path through XWayland:

```sh
WAYLAND_DISPLAY="" wine TouchDesigner.exe
```

`td-launch` does this automatically on a Wayland session;
`TD_KEEP_WAYLAND=1` disables it.

On NVIDIA, also set:

```sh
__GL_YIELD=USLEEP
```

which stops the driver busy-waiting against the compositor. `TD_NO_GL_YIELD=1`
disables it.

---

## The UI renders in the wrong font

**Symptom.** TouchDesigner works, but the interface font is not TouchDesigner's
own — wrong metrics, clipped labels, misaligned parameter names.

**Log signature.** TouchDesigner's Textport says so on every start:

```text
Error Loading Default Mono Font. Failed to load font file. Failed to load .
  Substituted with Times New Roman.
Error Loading Default Font. Failed to load font file. Failed to load .
  Substituted with Times New Roman.
```

**Cause.** Wine's font substitution does not pick the fonts TouchDesigner
expects, so it falls back to Times New Roman for the whole interface.

**Fix.** The community ships a `wine_ui_fixes.tox` that corrects UI font
rendering from inside TouchDesigner. Get it from
[iswad-lab/TouchDesigner-Linux](https://github.com/iswad-lab/TouchDesigner-Linux)
and add it to your palette, or see
[Minor UI Fixes for TouchDesigner on Wine](https://forum.derivative.ca/t/minor-ui-fixes-for-touchdesigner-on-wine-2025-11-29/973692).

Cosmetic only — everything else works without it.

---

## Bottles just says "Not responding"

Not an issue in itself, but the reason these bugs are so hard to pin down: the
Bottles UI gives you no log. Run TouchDesigner through the runner yourself.

```sh
td-launch --debug     # +seh,+tid,+loaddll, tee'd to a log
td-doctor --log       # match the log against known signatures
```

Manually, the same thing is:

```sh
B="$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles/<bottle>"
R="$HOME/.var/app/com.usebottles.bottles/data/bottles/runners/<runner>"

cd "$B/drive_c/TouchDesigner/bin"
WINEPREFIX="$B" WINEDEBUG="+seh,+tid,+loaddll" \
  "$R/bin/wine" TouchDesigner.exe 2>&1 | tee /tmp/td.log
```

Then look for the first exception rather than reading from the top:

```sh
grep -n -m1 -A 40 'c0000005' /tmp/td.log
```

A `+seh` log for one failed startup is 30–40 MB. That is normal.

---

## Red herrings

Things that look alarming in a Wine log and are not your problem:

- **`err:module:use_lsteamclient lsteamclient disabled`** — Wine declining to
  load Steam integration. Irrelevant unless you launched via Steam.
- **`D3D11InternalCreateDevice: Using feature level D3D_FEATURE_LEVEL_10_0`** —
  DXVK reporting the level the application *asked for*, not the level your card
  can do. Not a sign of a broken GPU setup.
- **A wall of `fixme:` lines** — normal Wine noise.
- **Empty bottles that look installed.** A bottle with no TouchDesigner in it is
  indistinguishable from a working one in the Bottles UI. `td-doctor` lists every
  bottle and says which one actually contains `TouchDesigner.exe`.
