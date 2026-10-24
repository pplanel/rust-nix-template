{
  description = "";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Crane is a pure library flake and no longer takes a nixpkgs input
    crane.url = "github:ipetkov/crane";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    rust-overlay,
    crane,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [(import rust-overlay)];
        };
        inherit (pkgs) lib;

        # 1. Toolchain definition (or use pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml)
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = ["rust-src" "rust-analyzer" "clippy" "rustfmt"];
        };

        # 2. Initialize Crane
        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        # 3. Base workspace source for dependency caching and workspace-wide checks
        src = craneLib.cleanCargoSource ./.;

        commonArgs = {
          inherit src;
          strictDeps = true;

          buildInputs = with pkgs;
            [
              # Add C/system libs here (e.g., openssl)
            ]
            ++ lib.optionals stdenv.hostPlatform.isDarwin [
              pkgs.libiconv
            ];

          nativeBuildInputs = with pkgs; [
            pkg-config
          ];
        };

        # 4. Compile all workspace 3rd-party dependencies once
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        # Shared args for individual workspace crates
        individualCrateArgs =
          commonArgs
          // {
            inherit cargoArtifacts;
            inherit (craneLib.crateNameFromCargoToml {inherit src;}) version;
            doCheck = false; # Tests are run once across the workspace in `checks`
          };

        # Helper to isolate source trees per crate so changing crate A doesn't rebuild crate B
        fileSetForCrate = crateFiles:
          lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions ([
                ./Cargo.toml
                ./Cargo.lock
                (craneLib.fileset.commonCargoSources ./crates/common)
                (craneLib.fileset.commonCargoSources ./crates/domain)
                (craneLib.fileset.commonCargoSources ./crates/server)
                (craneLib.fileset.commonCargoSources ./crates/my-workspace-hack) # Uncomment if using cargo-hakari
              ]
              ++ crateFiles);
          };

        # 5. Define individual workspace crate derivations
        server = craneLib.buildPackage (individualCrateArgs
          // {
            pname = "server";
            cargoExtraArgs = "-p server";
            src = fileSetForCrate [
              (craneLib.fileset.commonCargoSources ./crates/server)
            ];
          });
      in {
        formatter = pkgs.nixfmt-rfc-style;

        # Build checks run via `nix flake check`
        checks = {
          inherit server;

          workspace-clippy = craneLib.cargoClippy (commonArgs
            // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            });

          workspace-fmt = craneLib.cargoFmt {
            inherit src;
          };

          workspace-nextest = craneLib.cargoNextest (commonArgs
            // {
              inherit cargoArtifacts;
              partitions = 1;
              partitionType = "count";
            });

          workspace-hakari = craneLib.mkCargoDerivation {
            inherit src;
            pname = "workspace-hakari";
            cargoArtifacts = null;
            doInstallCargoArtifacts = false;
            nativeBuildInputs = [pkgs.cargo-hakari];
            buildPhaseCargoCommand = ''
              cargo hakari generate --diff
              cargo hakari manage-deps --dry-run
              cargo hakari verify
            '';
          };
        };

        packages = {
          inherit server;
          default = server;
        };

        devShells.default = craneLib.devShell {
          checks = self.checks.${system};

          # rustToolchain is automatically included by craneLib.devShell
          packages = with pkgs; [
            cargo-edit
            cargo-watch
            cargo-nextest
            cargo-hakari
            cargo-release
            git-cliff
            cocogitto
          ];
        };
      }
    );
}
