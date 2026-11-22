# headless-runner: notes for agents

Scripts that turn a Mac into a work computer for Infinitary tasks and iOS CI.
The README explains how a person runs them; this file says how to change them.

- Clone projects to `~/Dev/github.com/<owner>/<repo>` (this repository to
  `~/Dev/github.com/rojcarranza/headless-runner`). Scripts clone only through
  `lib/clone.sh`, so every computer uses the same place.
- No script names one computer. The computer's name is the short name of the
  user running `./setup.sh`; per-computer facts live in `machines/<name>.json`.
- No secret in any file: no password, token or private key. `setup.sh` asks the
  password once and keeps it in `HR_PASSWORD` in memory; headless reads it
  through its `cmd:` store. Sign-ins stay the person's steps.
- Versions are pinned in `pins.env` and in `machine/flake.lock`; change a pin in
  both places. Do not edit `machine/flake.lock` by hand: `nix flake lock path:$PWD/machine`.
- The gate is `./scripts/check.sh`: `bash -n`, shellcheck, the secret scan, the
  script tests in `tests/` (stand-ins print what macOS prints) and the machine
  flake evaluating for `aarch64-darwin`. It runs on Linux. What only a run on a
  real Mac proves is listed in the README under "What the checks cannot prove".
- Pull requests go through the no-mistakes gate, like the rest of this setup.
