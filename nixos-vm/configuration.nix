# This is just a sample setup!
#
# It's very barebones and no hardening is applied. The runner
# can easily run out of storage because of the limited size
# of the QCOW2.

{ pkgs, lib, config, ... }:
{
  imports = [
    ./arc-runner.nix
  ];

  documentation.enable = false;
  networking.hostName = "runner";

  # For EOL'd node.js version depended by github-runner
  nixpkgs.config.allowInsecurePredicate = x: (x.pname or "") == "nodejs";

  arc-runner.enable = true;

  # For ease of debugging
  services.getty.autologinUser = "root";

  programs.nix-ld = {
    enable = true;
    package = lib.mkIf (pkgs ? nix-ld-rs) pkgs.nix-ld-rs;
  };
}
