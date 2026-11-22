# headless-runner

Scripts that turn a Mac, such as a MacBook Air, into a work computer: it takes
tasks from Infinitary's first mate and runs iOS CI and nightly jobs. One
command, `bash setup.sh`, does it. It stops only where you must sign in.

It is built on two projects by Kun Chen, which carry most of the knowledge:

- [headless](https://github.com/kunchenguid/headless) puts a Mac in an
  unattended state over SSH: never asleep, signs itself in after a restart,
  SSH by key only, Tailscale. Pinned at `e9168b7`.
- [runner-up](https://github.com/kunchenguid/runner-up) takes GitHub Actions
  jobs and runs them on your own machines. Pinned at `v0.1.13`.
- [no-mistakes](https://github.com/kunchenguid/no-mistakes), the pre-push check
  tool, at `v1.111.0` (the version the dotfiles pin).

Kun's write-up of the approach (a small bootstrap, then nix-darwin with
declarative Homebrew, owned small Macs as CI runners, fixed job slots) is the
reason the setup is layered this way. Versions are in `machine/flake.nix` with
`machine/flake.lock` (headless, runner-up, no-mistakes) and `pins.env` (Xcode).

## Run it

Before the scripts, two things only you can do at the Mac:

1. In System Settings, Users & Groups, **add an administrator** (for example
   `thirdmate`) and sign in as it. Make it in System Settings, not with a
   script: that gives it the secure token FileVault and updates need. The
   user's short name becomes the computer's name, its Tailscale name and its
   runner-up pool.
2. In Safari, sign in to GitHub, download this repository (Code, Download ZIP)
   and open the folder in Terminal.

Then:

```sh
bash setup.sh
```

It asks for the user's password once (hidden, kept in memory for the run) and
opens each sign-in page for you. Run it again if it stops (from the clone it makes at `~/Dev/github.com/rojcarranza/headless-runner` once the `runner-up` stage has run); finished stages are
skipped. The stages, in order:

| Stage | What runs | What only you do |
| --- | --- | --- |
| `account` | Checks admin and secure token, turns on Remote Login, makes the user's SSH key and `~/Dev/github.com` | Paste the public key of the computer that will add this one in Infinitary (once) |
| `machine` | headless: Nix, FileVault off, auto sign-in, never asleep (lid closed too), key-only SSH, Tailscale, the shared CI tools, and a Rancher Desktop defaults profile so its first-run window never stops a nightly | Approve the Tailscale page it opens; turn off key expiry for the computer in Tailscale's admin page |
| `xcode` | Xcode from the App Store (27.1 or later), license, first launch, iOS platform, the iPhone 18 Pro and iPad Pro 11-inch (M5) simulators. Device Hub is part of Xcode | Sign in to the App Store |
| `runner-up` | Installs runner-up as a login agent with one host place on this Mac; makes this repository a clone at `~/Dev/github.com/rojcarranza/headless-runner` | Sign in to GitHub (`gh` shows a code) |
| `projects` | Runs every script in `projects/`; `praiselineup.sh` clones PraiseLineup, its backend and the dotfiles, links the review gate (`no-mistakes init`), makes the gate simulator, runs the gate unit tests and a trial nightly (the real nightly with `--no-post`, into a scratch folder; up to six hours) | Nothing |
| `restart` | Restarts once; the Mac signs itself back in and `verify.sh` runs by itself, with a notification | Nothing |

Other forms: `bash setup.sh STAGE` runs one stage again, `bash setup.sh --no-restart`
skips the restart, `bash setup.sh --list` shows what is done. `./verify.sh` reads
every setting back and changes nothing.

Last, on the computer where the first mate lives, add the new computer in
Infinitary by its Tailscale name (Infinitary's `docs/devices.md`). Infinitary
sends its own copy to the new computer, so nothing of it is installed here. Then
sign it in to Claude and GitHub through its setup card.

## Where projects live

Every computer keeps projects at `~/Dev/github.com/<owner>/<repo>`, and
`DEV_HOME` points at `~/Dev/github.com`. Scripts clone only through
`lib/clone.sh`. Infinitary's own task working copies stay in Infinitary's folder.

## Keeping work running while you use another account

Infinitary starts work whenever the new user is signed in, including while
another user is at the screen (Infinitary's `docs/helper.md`, "In the
background"). runner-up and the nightly run in that same signed-in session.

- Use **Switch User** to reach your own account. Never **Log Out** of the new
  user: that stops its work until the next restart signs it back in.
- `./verify.sh`, run over SSH while you are in another account, reports that
  another user is at the screen and that runner-up and the simulator service
  still answer for the new user.
- Unproven: iOS simulator UI tests may stall while another user has the screen.
  If the check above shows that, the nightly needs the new user at the screen.

## Running an app's own GitHub Actions jobs here

runner-up serves only this repository until you add another. To let an app's
workflows run on this Mac: add the app's `owner/repo` to `github.repos` in
`~/Library/Application Support/runner-up/config.json` (a running runner-up
applies the edit), then ask for this Mac in the workflow with
`runs-on: <the computer's name>`, which is the new user's short name and
runner-up's pool. Check it with `runner-up check-config`. Each job runs as the
new user, in its session (see Security notes).

## Adding an app

One script per app in `projects/`, run by the `projects` stage. Start from
`projects/praiselineup.sh`: clone through `lib/clone.sh`, then make what its
checks need.

## Running it again, changing it, undoing it

- Run `bash setup.sh` again any time; every stage is safe to repeat. A second Mac
  needs no code change: sign in there as its own administrator and run it.
- `machines/<name>.json` holds one computer's public settings (user, host name,
  public SSH keys, auto sign-in). Edit it, then `bash setup.sh machine`.
- Undo: turn off auto sign-in in `machines/<name>.json` (`"autoLogin": false`)
  and run `bash setup.sh machine`; stop runner-up with
  `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.github.runner-up.plist`;
  remove headless with its nix-darwin uninstaller. Delete the user in System
  Settings to remove everything it owns.

## Checks

`./scripts/check.sh` is the gate: `bash -n`, shellcheck, a secret scan, the
script tests in `tests/` and the flake evaluating for an Apple silicon Mac. It
runs on Linux or a Mac and spends no GitHub Actions minutes.

What the checks cannot prove (they run on Linux with stand-ins for macOS
commands): that headless, Xcode, Homebrew, launchd and `systemsetup` behave on
the Air as the scripts expect. Only a run of `bash setup.sh` on the Air and its
`verify.sh` prove that. The manual workflow `.github/workflows/check.yml` runs
`verify.sh` on a named computer through runner-up.

## Security notes

- No secret is stored in this repository or on the Mac by these scripts. The
  password lives in memory for one `setup.sh` run.
- FileVault is turned off and auto sign-in is on, so the Mac works after any
  restart; anyone holding the Air can read every account's files on it.
- SSH takes keys only; only the keys in `keys/` and the user's own key get in.
- runner-up's host place runs a job as the new user, in its session: jobs can
  reach that user's files and saved passwords. Use it only for jobs you trust.
