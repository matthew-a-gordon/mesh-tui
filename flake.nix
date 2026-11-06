{
  description = "Rust TUI for Meshtastic mesh networks";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        mesh-tui = pkgs.rustPlatform.buildRustPackage {
          pname = "mesh-tui";
          version = "0.1.0";
          src = self;
          cargoLock.lockFile = ./Cargo.lock;
        };
        default = mesh-tui;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          # Stdlib sources for rust-analyzer and IDEs (see .envrc).
          RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
          packages = with pkgs; [
            cargo
            clippy
            rustc
            rustfmt
            rust-analyzer
          ];
        };
      });
    };
}
