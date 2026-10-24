# Shared immutable palette catalogue; usable without enabling appearance resources.
{
  preferences ? { },
}:
let
  schemes = import ./catalogue.nix;
  name = preferences.scheme or "everforest";
  appearance = preferences.appearance or "dark";
  selected = schemes.${name} or (throw "Folio: unsupported color scheme ${name}");
in
assert builtins.elem appearance [
  "dark"
  "light"
];
selected
// {
  inherit appearance;
  palette = selected.palettes.${appearance};
  semantic = builtins.mapAttrs (_: key: selected.palettes.${appearance}.${key}) selected.roles;
}
