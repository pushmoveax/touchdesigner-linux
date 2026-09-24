# Contributing

## The most useful contribution

A compatibility report. Run `td-doctor`, paste the output into a
[compatibility report](../../issues/new?template=compatibility-report.yml), and
say which TouchDesigner features you actually exercised. The matrix in
`docs/compatibility.md` is only as good as the machines in it.

## A new failure mode

If `td-doctor --log` says *"access violation, module not recognised"*, that is
worth an issue. Include:

- the `td-doctor` output,
- the first exception and the ~40 lines after it:
  `grep -n -m1 -A 40 'c0000005' <log>`,
- what you had already tried.

Please do not attach the whole 40 MB `+seh` log. The window around the first
exception is what identifies the module.

Adding a signature to `td-doctor` is a few lines in the *Log analysis* section —
a `grep` against the window around the first fault, plus a `fix` line.

## A setup step that does not work on your distro

`td-setup` is verified on Arch/EndeavourOS with Bottles from Flathub. If a step
fails somewhere else, the useful report is: which step number, the command it
printed, and what the command said. Steps are deliberately separate and
idempotent, so "step 3 fails, steps 1-2 are fine" is a complete bug report.

## Code

- Bash, `set -uo pipefail`, tabs, no external dependencies beyond
  `bash`/`python3`/`curl`/`tar`/coreutils. `shellcheck` clean.
- `td-doctor` is read-only. Anything that changes the system belongs in
  `td-setup`, `td-launch`, `td-patch-ids-peak` or `install.sh`, and anything
  that modifies a file makes a `.bak` first and offers a way back.
- Every step of `td-setup` checks whether it is already done, and every
  download resumes. Someone on a bad connection should be able to re-run it
  instead of starting over.
- Every fix needs a `--check`-style dry run, and a sentence in
  `docs/known-issues.md` explaining *why* it works. "It fixed it for me" is how
  this problem space got so confusing.
- Credit the source of a fix. Most of these were found by someone else.

## Testing

There is no CI: this cannot be tested without a GPU, a Wine prefix and a
licensed TouchDesigner. Before opening a PR, run on a real machine:

```sh
bash -n bin/td-setup bin/td-doctor bin/td-launch install.sh lib/td-common.sh
shellcheck -x bin/td-setup bin/td-doctor bin/td-launch install.sh lib/td-common.sh
python3 -m py_compile bin/td-patch-ids-peak

td-doctor
td-launch --dry-run
td-setup --dry-run
td-patch-ids-peak <prefix> --check
```

`--dry-run` and `--check` must be safe to run on a working install, and must not
change anything. That property is the point of the tools.

To exercise `td-setup` for real without disturbing a working install, give it
its own bottle and leave your launcher alone:

```sh
td-setup --bottle td-test --yes --skip-launcher
td-launch --bottle td-test          # confirm it starts
rm -rf ~/.var/app/com.usebottles.bottles/data/bottles/bottles/td-test
```
