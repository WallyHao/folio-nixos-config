{ context }:
let
  settings = context.settings;
  override = key: builtins.hasAttr key settings && settings.${key} != "inherit";
  resolve = key: if override key then settings.${key} else context.globals.${key};
  colors = context.theme;
in
{
  colors = colors // {
    appearance = context.globals.appearance;
  };
  font-family = resolve "font-family";
  font-size = resolve "font-size";
  cursor-size = settings.cursor-size or 42;
  origins = builtins.listToAttrs (
    map
      (name: {
        inherit name;
        value =
          if
            !(builtins.elem name [
              "appearance"
              "scheme"
            ])
            && override name
          then
            "module-configuration"
          else
            context.preferenceOrigins.${name};
      })
      [
        "scheme"
        "appearance"
        "font-family"
        "font-size"
      ]
  );
}
