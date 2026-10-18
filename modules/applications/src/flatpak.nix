{ pkgs, lib, context, configurationDigest }:
let
  settings = context.settings."folio-applications:applications" or { };
  application = app:
    if app.name == "zen" then import ./apps/zen.nix { inherit pkgs lib context app; }
    else if app.name == "obs" then import ./apps/obs.nix { inherit app; }
    else throw "Folio: unsupported application identity";
in
{
  format = 1;
  scope = "user";
  inherit configurationDigest;
  account = context.identity.account;
  home = context.identity.home;
  applications = map application (settings.app or [ ]);
}
