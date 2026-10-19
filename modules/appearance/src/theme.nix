{ context }:
let
  settings = context.settings."folio-appearance:appearance" or { };
  override = key: builtins.hasAttr key settings && settings.${key} != "inherit";
  resolve = key: if override key then settings.${key} else context.globals.${key};
  colors = builtins.fromJSON (builtins.readFile ./colors.json);
in {
  colors = colors // { appearance = resolve "appearance"; };
  font-family = resolve "font-family";
  font-size = resolve "font-size";
  cursor-size = settings.cursor-size or 28;
  origins = builtins.listToAttrs (map (name: {
    inherit name;
    value = if override name then "module-configuration" else context.preferenceOrigins.${name};
  }) [ "appearance" "font-family" "font-size" ]);
}
