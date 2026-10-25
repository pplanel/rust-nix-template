{
  description = "Modern multi-crate Rust workspace using Nix Flakes, Crane, and Rust-Overlay";

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
    (flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [(import rust-overlay)];
        };
        inherit (pkgs) lib;

        # 1. Toolchain definition
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
            ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
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
            doCheck = false; # Tests run across workspace in `checks`
          };

        # Base shared sources: changes outside these won't trigger rebuilds for individual crates
        fileSetForCrate = crateFiles:
          lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions ([
                ./Cargo.toml
                ./Cargo.lock
                (craneLib.fileset.commonCargoSources ./crates/common)
                (craneLib.fileset.commonCargoSources ./crates/domain)
                (craneLib.fileset.commonCargoSources ./crates/my-workspace-hack)
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

        # 6. Minimal OCI container image
        server-container = pkgs.dockerTools.buildLayeredImage {
          name = "server";
          tag = server.version;
          created = "now";

          contents = [
            pkgs.cacert
            pkgs.tzdata
            server
          ];

          config = {
            Entrypoint = ["${lib.getExe server}"];
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "TZDIR=${pkgs.tzdata}/share/zoneinfo"
              "RUST_LOG=info"
            ];
            User = "65534:65534"; # nobody
          };
        };
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
          inherit server server-container;
          default = server;
        };

        devShells.default = craneLib.devShell {
          checks = self.checks.${system};

          packages = with pkgs; [
            sd
            just
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
    ))
    // {
      # Top-level (system-independent) output for `nix flake init -t`
      templates.default = {
        path = ./.;
        description = "Multi-crate Rust workspace with Crane, cargo-hakari, Cocogitto, and git-cliff";
        welcomeText = ''
          # Rust Workspace Template Initialized
          1. Run `direnv allow` (or `nix develop`) to enter the devShell.
          2. Run `just init <project-name> <github-owner>` to configure workspace identifiers and hooks.
        '';
      };
    };
}
