{ pkgs, lib }:
context:
let
  settings = context.settings.git or { };
in
{
  programs.git = {
    enable = true;
    settings = {
      init.defaultBranch = settings.default-branch or "main";
      pull.rebase = settings.pull-rebase or true;
      push.autoSetupRemote = true;
    }
    // lib.optionalAttrs (settings ? user-name || settings ? user-email) {
      user =
        lib.optionalAttrs (settings ? user-name) { name = settings.user-name; }
        // lib.optionalAttrs (settings ? user-email) { email = settings.user-email; };
    };
  };
  programs.gh = {
    enable = settings.github-cli or true;
    settings.git_protocol = "https";
  };
}
