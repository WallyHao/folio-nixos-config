{ pkgs, lib }:
context:
let settings = context.settings."folio-git:git" or { };
in {
  programs.git = {
    enable = true;
    settings = {
      init.defaultBranch = settings.default-branch or "main";
      pull.rebase = settings.pull-rebase or true;
      push.autoSetupRemote = true;
    } // lib.optionalAttrs (settings ? user-name) { user.name = settings.user-name; }
      // lib.optionalAttrs (settings ? user-email) { user.email = settings.user-email; };
  };
  programs.gh = { enable = settings.github-cli or true; settings.git_protocol = "https"; };
}
