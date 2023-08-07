{
  description = "A simple project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    crane = {
      url = "github:ipetkov/crane";
      inputs.flake-compat.follows = "flake-compat";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
    };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-ld-rs = {
      url = "github:nix-community/nix-ld-rs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.flake-compat.follows = "flake-compat";
      inputs.flake-utils.follows = "flake-utils";
    };
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, crane, nixos-generators, nix-ld-rs, ... }: let
    # System types to support.
    supportedSystems = [ "x86_64-linux" "aarch64-linux" ];

    # Rust nightly version.
    nightlyVersion = "2023-07-20";

    buildSampleVm = system: nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        nixos-generators.nixosModules.all-formats
        ./nixos-vm/configuration.nix
        {
          nixpkgs.overlays = [
            nix-ld-rs.overlays.default
          ];
        }
      ];
    };
  in {
    nixosConfigurations.sample-vm = buildSampleVm "x86_64-linux";
  } // flake-utils.lib.eachSystem supportedSystems (system: let
    pkgs = import nixpkgs {
      inherit system;
      overlays = [
        rust-overlay.overlays.default
      ];
    };

    rustNightly = pkgs.rust-bin.nightly.${nightlyVersion}.default.override {
      extensions = [ "rust-src" "rust-analyzer-preview" ];
      targets = [ "x86_64-unknown-linux-musl" "aarch64-unknown-linux-musl" ];
    };

    targetOverrides = {
      "x86_64-linux" = "x86_64-unknown-linux-musl";
      "aarch64-linux" = "aarch64-unknown-linux-musl";
    };

    crossPkgsFor = crossSystem:
      if crossSystem == system then pkgs
      else import nixpkgs {
        localSystem = system;
        crossSystem = crossSystem;
        overlays = [
          rust-overlay.overlays.default
        ];
      };

    buildRunner = pkgs: let
      craneLib = (crane.mkLib pkgs).overrideToolchain rustNightly;
      rustTargetSpec = targetOverrides.${pkgs.system};
      rustTargetSpecUnderscored = builtins.replaceStrings [ "-" ] [ "_" ] rustTargetSpec;
      commonArgs = {
        cargoExtraArgs = "--target ${rustTargetSpec}";
        preBuild = ''
          export CARGO_TARGET_${pkgs.lib.toUpper rustTargetSpecUnderscored}_LINKER=$CC
        '';
      };
    in craneLib.buildPackage (commonArgs // {
      src = craneLib.cleanCargoSource ./.;

      cargoArtifacts = craneLib.buildDepsOnly (commonArgs // {
        src = craneLib.cleanCargoSource ./.;
      });

      doCheck = false;
    });

    buildImage = crossPkgs: let
      package = buildRunner crossPkgs;
      architecture = crossPkgs.go.GOARCH;
    in pkgs.dockerTools.buildImage {
      name = "kubevirt-actions-runner";
      tag = "main";
      copyToRoot = [ package ];
      config = {
        Entrypoint = [ "${package}/bin/kubevirt-actions-runner" ];
        Cmd = [ ];
      };
      inherit architecture;
    };
  in {
    packages = {
      default = buildRunner pkgs;
      image-amd64 = buildImage (crossPkgsFor "x86_64-linux");
      image-arm64 = buildImage (crossPkgsFor "aarch64-linux");
    };
    devShell = pkgs.mkShell {
      nativeBuildInputs = with pkgs; [
        pkg-config
        rustNightly
      ];
      buildInputs = with pkgs; [
        openssl
      ];

      NIX_PATH = "nixpkgs=${pkgs.path}";
    };
  });
}
