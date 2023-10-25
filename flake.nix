{
  description = "Poetry2nix flake";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/master";

    nix-github-actions = {
      url = "github:nix-community/nix-github-actions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  
    flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/1.tar.gz";
  };

  outputs = { self, nixpkgs, flake-utils, nix-github-actions, flake-compat }:
    {
      overlay = import ./overlay.nix;

      githubActions =
        let
          mkPkgs = system: import nixpkgs {
            config = {
              allowAliases = false;
              allowInsecurePredicate = _: true;
            };
            overlays = [ self.overlay ];
            inherit system;
          };
        in
        nix-github-actions.lib.mkGithubMatrix {
          checks = {
            x86_64-linux =
              let
                pkgs = mkPkgs "x86_64-linux";
              in
              import ./tests { inherit pkgs; };

            x86_64-darwin =
              let
                pkgs = mkPkgs "x86_64-darwin";
                inherit (pkgs) lib;
                tests = import ./tests { inherit pkgs; };
              in
              {
                # Aggregate all tests into one derivation so that only one GHA runner is scheduled for all darwin jobs
                aggregate = pkgs.runCommand "darwin-aggregate"
                  {
                    env.TEST_INPUTS = lib.concatStringsSep " " (lib.attrValues (lib.filterAttrs (_: v: lib.isDerivation v) tests));
                  } "touch $out";
              };
          };
        };

      templates = {
        app = {
          path = ./templates/app;
          description = "An example of a NixOS container";
        };
        default = self.templates.app;
      };
    } // (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (_: _: {
              p2nix-tools = pkgs.callPackage ./tools { };
            })
          ];
          config = {
            allowAliases = false;
            permittedInsecurePackages = [
              "python3.8-requests-2.29.0"
              "python3.8-cryptography-40.0.2"
              "python3.9-requests-2.29.0"
              "python3.9-cryptography-40.0.2"
              "python3.10-requests-2.29.0"
              "python3.10-cryptography-40.0.2"
              "python3.11-requests-2.29.0"
              "python3.11-cryptography-40.0.2"
            ];
          };
        };

        poetry2nix = import ./default.nix { inherit pkgs; };
      in
      rec {
        packages = {
          poetry2nix = poetry2nix;
          default = poetry2nix.cli;
        };

        devShells = {
          default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              p2nix-tools.env
              p2nix-tools.flamegraph
              nixpkgs-fmt
              poetry
              niv
              jq
              nix-prefetch-git
              nix-eval-jobs
              nix-build-uncached
            ];
          };
        };

        legacyPackages = poetry2nix;
        defaultPackage = poetry2nix;

        apps = {
          inherit (pkgs) poetry;
          poetry2nix = flake-utils.lib.mkApp { drv = packages.poetry2nix; };
          default = apps.poetry2nix;
        };
      }));
}
