{ pkgs, lib, codex, dsh }:
context:
let settings = context.settings."folio-agents:agents" or { };
in {
  imports = lib.optional (settings.codex.enabled or true)
    ((import ./codex/user.nix { inherit pkgs lib; package = codex; })
      (context // { inherit settings; }));
  home.packages = lib.optional (settings.dsh.enabled or false) dsh;
}
