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

## A saved project never opens (DirectWrite) — unsolved

**Symptom.** TouchDesigner starts and shows its splash, but a project passed on
the command line or opened from disk never appears. The splash sits at roughly
99%, or the process exits without a dialog and you are left with TouchDesigner's
default startup network instead of your work — which reads as "it opened the
wrong project".

Trivial projects open fine. This is not about your file: TouchDesigner's own
shipped samples reproduce it.

| Project | Size | Result |
| --- | --- | --- |
| `Samples/Setup/Base/NewProject.toe` | 770 B | opens in ~20 s |
| `Samples/Setup/Example/NewProject.toe` | 1.8 KB | opens (this is the default startup network) |
| `Samples/DomeViewer/DomeViewer_LinesDemo.toe` | 122 KB | never opens |
| a project saved from the UI | 87 KB | never opens |

**Log signature.** At the default log level:

```text
fixme:dwrite:dwritefactory3_GetSystemFontCollection checking for system font updates not implemented
err:seh:NtRaiseException Unhandled exception code c0000005 flags 0 addr 0x6ffffff82418
```

With `td-launch --debug`, the first exception unwinds through DirectWrite:

```text
Exception 0xc0000005
  ntdll.dll  + 0x52418
  ntdll.dll  + 0x267E8
  DWrite.dll + 0x2B08A
  DWrite.dll + 0x406C3
  libTD.dll  + 0x159C81C
```

**Cause.** `DWrite.dll + 0x406C3` is the same frame that appears in the
mimalloc/DWrite hang above. `MIMALLOC_DISABLE_REDIRECT=1` does not cure this
one; it only moves the faulting allocation out of mimalloc and into ntdll's
heap. The bug is in Wine's DirectWrite, reached from TouchDesigner's own UI
rendering, and the more interface a project brings with it the more reliably it
is hit.

**Fix.** None known. What was tried, each on a prefix whose health was confirmed
by opening the 770 B template immediately afterwards:

| Attempt | Result |
| --- | --- |
| `MIMALLOC_DISABLE_REDIRECT=1` | already applied; insufficient |
| `WINEDLLOVERRIDES=dwrite=d` | worse — startup stops earlier |
| 72 host fonts copied into the prefix | no change |
| `wine_ui_fixes.tox` injected via `toeexpand`/`toecollapse` | no change |

The `.tox` injection is worth explaining, because it looks like it should help:
it switches Text TOPs to the Scalable renderer, which avoids DirectWrite. It
cannot help here for two reasons. Its script runs from `onStart`, which is after
the load that crashes, and the sample that reproduces the crash contains no
Text TOPs at all.

Running the same prefix under a newer Wine was also tried and is **not** listed
above: the newer Wine upgraded the prefix and broke it outright, so that result
says nothing. If you have a spare prefix, that experiment is still worth doing
properly.

If you can open large projects on your machine, please say so in a
[compatibility report](../../issues/new?template=compatibility-report.yml) —
knowing which Wine, driver or desktop avoids this is the fastest way to a fix.

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

**Cause.** Wine's font substitution does not pick the fonts TouchDesigner
expects.

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
