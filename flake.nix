{
  description = "An experimental package manager for Scryer Prolog";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    scryer-prolog = {
      url = "github:mthom/scryer-prolog";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      scryer-prolog,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells = {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              git
              just
              util-linux
              shellcheck
            ] ++ [
              (scryer-prolog.packages.${system}.default.overrideAttrs (
                final: prev: {
                  doCheck = false;
                }
              ))
            ];
          };
        };
      }
    );
}
