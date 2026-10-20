{ pkgs, lib, codex, pi }:
context:
let settings = context.settings."folio-agents:agents" or { };
in {
  imports = lib.optional (settings.codex.enabled or true)
    ((import ./codex/user.nix { inherit pkgs lib; package = codex; })
      (context // { inherit settings; }))
    ++ lib.optional (settings.pi.enabled or false)
      ((import ./pi/user.nix { inherit pkgs lib; package = pi; })
        (context // { inherit settings; }));
}
