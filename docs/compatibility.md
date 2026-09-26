# Verified configurations

Reports from real machines. `td-doctor` prints everything the first table needs.

Please only fill in the feature table for things you actually tried. `?` is a
useful answer and a wrong `✅` wastes someone's evening.

---

## EndeavourOS / KDE Wayland / RTX 2080 Ti

| | |
| --- | --- |
| Distro | EndeavourOS (Arch) |
| Kernel | 7.0.9-arch2-1 |
| Desktop | KDE Plasma, Wayland session |
| GPU | NVIDIA GeForce RTX 2080 Ti |
| Driver | 595.71.05 |
| Wine | Bottles (Flatpak), runner `soda-11.0-10` |
| DXVK | 3.1 |
| VKD3D | vkd3d-proton 3.0.1 |
| NVAPI | dxvk-nvapi 0.9.2 (disabled) |
| Bottle arch | win64, Windows 10 |
| TouchDesigner | 2025.33070 |
| Fixes needed | `MIMALLOC_DISABLE_REDIRECT=1`, IDS Peak entry points zeroed, `WAYLAND_DISPLAY=""`, `__GL_YIELD=USLEEP` |

Without `MIMALLOC_DISABLE_REDIRECT=1` this configuration hangs on the splash
screen every time. With it, TouchDesigner reaches its main window in about
20 seconds.

**What `td-setup` has and has not been through on this machine.** Steps 1-5 ran
for real: prerequisites, bottle creation via `bottles-cli`, runner and DXVK
resolution, and the 2 990 276 456-byte installer download verified against
`Content-Length`. Step 6 ran for 35 minutes and installed 8.5 GB including
`TouchDesigner.exe`, with the silent switches confirmed to reach the inner Inno
Setup process — but it was stopped before the installer returned, so the last
part of step 6 and steps 7-8 have only been exercised against an install that
already existed. If you run `td-setup` end to end, a report saying so is
genuinely useful.

| Feature | Status | Notes |
| --- | --- | --- |
| Startup, new project | ✅ | |
| Save / reopen `.toe` | ✅ | |
| General UI, node editing | ✅ | |
| Heavy operator graphs | ✅ | no stutter reported |
| UI font | ⚠️ | wrong font, `wine_ui_fixes.tox` not installed yet |
| Opening a large `.toe` | ❌ | crashes in Wine's DirectWrite, see known-issues |
| GLSL TOP | ? | untested |
| Render TOP / 3D | ? | untested |
| Movie File In TOP | ? | untested |
| NDI / Syphon-Spout | ? | untested |
| Network DATs (TCP/UDP/OSC/Web) | ? | untested |
| Python extensions, external modules | ? | untested |
| CUDA-dependent operators | ? | untested |

---

## Add yours

Copy the block above, or open a
[compatibility report](https://github.com/pushmoveax/touchdesigner-linux/issues/new?template=compatibility-report.yml)
and paste your `td-doctor` output.

### Template

```markdown
## <distro> / <desktop + session> / <GPU>

| | |
| --- | --- |
| Distro | |
| Kernel | |
| Desktop | |
| GPU | |
| Driver | |
| Wine | |
| DXVK | |
| TouchDesigner | |
| Fixes needed | |

| Feature | Status | Notes |
| --- | --- | --- |
| Startup, new project | | |
| Save / reopen `.toe` | | |
| General UI, node editing | | |
| Heavy operator graphs | | |
| UI font | | |
| GLSL TOP | | |
| Render TOP / 3D | | |
| Movie File In TOP | | |
| NDI / Syphon-Spout | | |
| Network DATs | | |
| Python extensions | | |
| CUDA-dependent operators | | |
```

Legend: ✅ works · ⚠️ works with caveats · ❌ broken · `?` untested
