{ pkgs }:
# Keep this patch scoped to the reviewed upstream version. An upgrade requires
# checking the focus-ring lifecycle and its regression tests again.
assert pkgs.lib.assertMsg (
  pkgs.niri.version == "26.04"
) "Folio: review the focus-fade patch before upgrading Niri beyond 26.04";
pkgs.niri.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./niri-focus-fade.patch ];
  env = (old.env or { }) // {
    NIRI_BUILD_COMMIT = "Folio focus-fade";
  };
})
