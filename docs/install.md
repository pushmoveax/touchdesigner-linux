# Installing TouchDesigner on Linux by hand

`td-setup` does all of this for you. This page is the same thing step by step,
for when you would rather not run a script that installs things, or when a step
failed and you want to take over from there.

Everything below was run on EndeavourOS with KDE/Wayland and an NVIDIA card; see
[`compatibility.md`](compatibility.md).

---

## 0. What you need

- A working Vulkan driver. Check with `vulkaninfo --summary`. DXVK is what gives
  TouchDesigner its Direct3D 11, and it is Vulkan underneath — if this is broken,
  nothing else matters.
- About 16 GB of free disk while installing: a 2.8 GB installer, 2.9 GB that the
  self-extracting installer unpacks into the prefix, and roughly 8.3 GB of
  installed files. The temporary copy goes away at the end, so the bottle
  settles at around 9 GB.
- A TouchDesigner licence to *use* it. The free non-commercial one is enough. No
  account is needed to *download* it.

## 1. Bottles

```sh
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y flathub com.usebottles.bottles
```

Other Wine front ends work too — see [Without Bottles](#without-bottles) at the
end — but Bottles is the path this project verifies.

## 2. A Wine runner and DXVK

Open Bottles once and let it download its default components; that is the easy
route. To do it without the GUI, put the tarballs in place yourself:

```sh
data="$HOME/.var/app/com.usebottles.bottles/data/bottles"
mkdir -p "$data/runners" "$data/dxvk"

# Soda runner (Bottles' Wine build). Note the directory is named after the tag,
# not after the tarball's own top-level directory.
curl -fL -o /tmp/soda.tar.xz \
  https://github.com/bottlesdevs/wine/releases/download/soda-11.0-10/soda-11.0-10-x86_64.tar.xz
tar -xf /tmp/soda.tar.xz -C /tmp
mv /tmp/soda-11.0-10-x86_64 "$data/runners/soda-11.0-10"

# DXVK
curl -fL -o /tmp/dxvk.tar.gz \
  https://github.com/doitsujin/dxvk/releases/download/v3.1/dxvk-3.1.tar.gz
tar -xf /tmp/dxvk.tar.gz -C "$data/dxvk"
```

Check the current versions at
[bottlesdevs/wine](https://github.com/bottlesdevs/wine/releases) and
[doitsujin/dxvk](https://github.com/doitsujin/dxvk/releases). Soda 11 is
Wine 10-based, which is also exactly why the mimalloc fix in step 6 is needed.

## 3. A bottle

```sh
flatpak run --command=bottles-cli com.usebottles.bottles new \
  --bottle-name touchdesigner \
  --environment gaming \
  --arch win64 \
  --runner soda-11.0-10 \
  --dxvk dxvk-3.1
```

`--arch win64` matters: TouchDesigner is 64-bit only and a win32 bottle will
never work. `--environment gaming` is what turns DXVK on.

From now on:

```sh
prefix="$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles/touchdesigner"
wine="$HOME/.var/app/com.usebottles.bottles/data/bottles/runners/soda-11.0-10/bin/wine"
```

The runner works from outside the Flatpak sandbox, which is what makes the rest
of this ordinary shell work.

## 4. The installer

Build numbers are listed at <https://derivative.ca/download>. The download host
serves the file directly:

```sh
curl -fL -C - -o ~/TouchDesigner.2025.33070.exe \
  https://download.derivative.ca/TouchDesigner.2025.33070.exe
```

`-C -` makes it resumable, which matters for 2.8 GB. Old builds are removed from
the host, so a build number from an old forum post may 403.

## 5. Install it into the bottle

The installer is a 7-Zip SFX wrapping an Inno Setup 6 installer. The switches
are passed through to the inner installer, so the standard Inno silent switches
do work:

```sh
WINEPREFIX="$prefix" WINEDEBUG=-all WAYLAND_DISPLAY="" \
  "$wine" ~/TouchDesigner.2025.33070.exe \
  /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOICONS '/DIR=C:\TouchDesigner'

# Inno Setup hands off to a child process, so wait for the prefix to go quiet
# instead of trusting wine's exit status.
"$(dirname "$wine")/wineserver" -w
```

Nothing is printed and no window stays on screen, but **budget 20-30 minutes**.
Under Wine this is much slower than on Windows: the outer SFX first extracts
about 2.9 GB into the prefix's `Temp`, and only then does Inno Setup write the
roughly 8 GB of installed files, which is a great many small writes.

You can watch it work from another terminal:

```sh
du -sh "$prefix/drive_c/TouchDesigner"
```

When it is done:

```sh
ls "$prefix/drive_c/TouchDesigner/bin/TouchDesigner.exe"
```

Drop `/VERYSILENT` if you would rather click through the installer.

## 6. The fixes

This is the part that is not obvious, and the reason this repository exists.
[`known-issues.md`](known-issues.md) explains each one.

### mimalloc — the one that causes the splash-screen hang

Nothing to install. TouchDesigner must be *launched* with:

```sh
MIMALLOC_DISABLE_REDIRECT=1
```

Without it, TouchDesigner freezes while loading the project, with an access
violation in `mimalloc.dll` reached through Wine's `DWrite.dll`. With it, it
starts normally.

### IDS Peak camera DLLs

```sh
td-patch-ids-peak "$prefix" --check    # look first
td-patch-ids-peak "$prefix" --apply    # zero the entry points, keeping .bak
```

By hand, for one file, this is just four bytes at `*(uint32*)0x3C + 40`:

```sh
cd "$prefix/drive_c/TouchDesigner/bin"
python3 - <<'PY'
import struct
for name in ("ids_peak_afl.dll", "ids_peak_comfort_c.dll",
             "ids_peak_ifl.dll", "ids_peak_ipl.dll"):
    with open(name, "r+b") as f:
        f.seek(0x3c)
        pe = struct.unpack("<I", f.read(4))[0]
        f.seek(pe + 40)
        old = struct.unpack("<I", f.read(4))[0]
        f.seek(pe + 40)
        f.write(b"\0\0\0\0")
        print(f"{name}: 0x{old:X} -> 0x0")
PY
```

Back the files up first. `td-patch-ids-peak` does that and validates the PE
header before writing; the snippet above does neither.

### Wayland and NVIDIA

Launch with `WAYLAND_DISPLAY=""` on a Wayland session, and `__GL_YIELD=USLEEP`
on NVIDIA.

## 7. Launching

Putting it together, the launch that works:

```sh
cd "$prefix/drive_c/TouchDesigner/bin"
MIMALLOC_DISABLE_REDIRECT=1 \
WINEPREFIX="$prefix" \
WAYLAND_DISPLAY="" \
__GL_YIELD=USLEEP \
  "$wine" TouchDesigner.exe
```

`td-launch` is this, with the paths discovered rather than hardcoded, each fix
individually switchable, and the output kept in a log that `td-doctor --log` can
read afterwards. `install.sh` turns it into a `touchdesigner` command and a menu
entry.

## 8. Check

```sh
td-doctor
```

---

## Without Bottles

Plain Wine works; you lose Bottles' component management.

```sh
export WINEPREFIX="$HOME/.wine-td"
export WINEARCH=win64
wineboot --init
winetricks dxvk                    # simplest way to get DXVK into a prefix
wine ~/TouchDesigner.2025.33070.exe /VERYSILENT '/DIR=C:\TouchDesigner'
```

Then apply the same fixes and use:

```sh
td-doctor --prefix "$WINEPREFIX"
td-launch --prefix "$WINEPREFIX"
```

Both accept `--prefix`, so the diagnosis and the launcher do not care whether
Bottles is involved. Only `td-setup` is Bottles-specific.

Proton (via Steam) also works and is what
[bluejorts' gist](https://gist.github.com/bluejorts/91e86a41099966b11e7248f52ac38e28)
documents; the mimalloc fix is the same environment variable.
