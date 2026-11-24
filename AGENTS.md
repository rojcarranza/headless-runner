# headless-runner: notes for agents

Scripts that turn a Mac into a work computer for Infinitary tasks and iOS CI.
The README explains how a person runs them; this file says how to change them.

- Clone projects to `~/Dev/github.com/<owner>/<repo>` (this repository to
  `~/Dev/github.com/rojcarranza/headless-runner`). Scripts clone only through
  `lib/clone.sh`, so every computer uses the same place. A project script
  uses `clone_latest`, so a rerun of the `projects` stage runs GitHub's newest
  `main`.
- No script names one computer. The computer's name is the short name of the
  user running `./setup.sh`; per-computer facts live in `machines/<name>.json`.
- No secret in any file: no password, token or private key. `setup.sh` asks the
  password once and keeps it in `HR_PASSWORD` in memory; headless reads it
  through its `cmd:` store. Sign-ins stay the person's steps.
- Xcode's version is pinned in `pins.env`. headless, runner-up, no-mistakes and gh-axi
  are pinned in `machine/flake.nix` and `machine/flake.lock`; change both
  together (the machine stage runs headless's scripts from the commit in
  `flake.lock`). Do not edit `machine/flake.lock` by hand:
  `nix flake lock path:$PWD/machine`. The gate only evaluates the flake and
  never builds gh-axi: a gh-axi bump needs a new `pnpmDeps` hash in
  `machine/gh-axi.nix` and a real `nix build` of it (also for aarch64-darwin).
- Plain `gh` stays only for `gh auth login` and `gh auth setup-git`, which
  gh-axi has no command for; every other GitHub call goes through `gh-axi`.
- The gate is `./scripts/check.sh`: `bash -n`, shellcheck, the secret scan, the
  script tests in `tests/` (stand-ins print what macOS prints) and the machine
  flake evaluating for `aarch64-darwin`. It runs on Linux (with zsh). What only
  a run on a real Mac proves is listed in the README under "What the checks
  cannot prove".
- Pull requests go through the no-mistakes gate, like the rest of this setup.
