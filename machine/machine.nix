# What every task and iOS app needs, on top of the headless layer.
# settings.json (one per computer, from machines/<name>.json) holds the
# headless options: user, hostName, sshKeys, autoLogin, tailscale, extras.
{ inputs, pkgs, ... }:
let
  system = "aarch64-darwin";
in
{
  headless = builtins.fromJSON (builtins.readFile ./settings.json);

  nixpkgs.hostPlatform = system;
  system.stateVersion = 6;

  environment.systemPackages = [
    inputs.runner-up.packages.${system}.default
    inputs.no-mistakes.packages.${system}.default
    pkgs.git
    pkgs.gh
    pkgs.python3
    pkgs.jq
    pkgs.shellcheck
  ];

  # Homebrew itself is installed by stages/machine.sh before the switch.
  # Rancher Desktop gives Docker, which PraiseLineup's scripts open themselves;
  # mas installs Xcode from the App Store.
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };
    brews = [ "mas" ];
    casks = [ "rancher" ];
  };

  # On a laptop, "never sleep" is not enough: the lid closing still sleeps it.
  # headless's own extras (power, Spotlight, Siri) stay as they are.
  system.activationScripts.postActivation.text = ''
    echo >&2 "headless-runner: keeping the Mac awake with the lid closed..."
    /usr/bin/pmset -a disablesleep 1
  '';
}
