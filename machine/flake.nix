{
  description = "A Mac that takes tasks and iOS CI: headless layer plus the tools every task needs";

  inputs = {
    # Pinned by flake.lock to the commits in ../pins.env.
    headless.url = "github:kunchenguid/headless/e9168b7977b39c488241fbfb62bbb12268cd2862";
    nixpkgs.follows = "headless/nixpkgs";
    nix-darwin.follows = "headless/nix-darwin";
    # These two keep their own nixpkgs: runner-up needs a newer Go than most.
    runner-up.url = "github:kunchenguid/runner-up/v0.1.13";
    no-mistakes.url = "github:kunchenguid/no-mistakes/v1.111.0";
  };

  outputs = inputs@{ headless, nix-darwin, ... }: {
    # headless's apply step builds darwinConfigurations.machine.
    darwinConfigurations.machine = nix-darwin.lib.darwinSystem {
      specialArgs = { inherit inputs; };
      modules = [ headless.darwinModules.headless ./machine.nix ];
    };
  };
}
