{ packages }:
context: {
  home.packages = builtins.attrValues packages;
  xdg.configFile."isaac/profile.json".source = ./versions.json;
}
