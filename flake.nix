{
  description = "Folio: module-owned NixOS configuration through YANG and sysrepo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: import ./modules/manager/src/outputs.nix { inherit inputs; };
}
