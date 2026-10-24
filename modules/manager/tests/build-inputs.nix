# Rebuilding a captured source can change wrappers without changing runtime
# dependencies. Offline guests also need the native tools and development outputs.
{ pkgs }:
[
  pkgs.stdenvNoCC
  pkgs.shellcheck-minimal
  pkgs.lndir
  pkgs.perl
  pkgs.python3
  pkgs.makeWrapper
  pkgs.makeBinaryWrapper
  pkgs.stdenv
  pkgs.stdenv.cc
  pkgs.pkg-config
  pkgs.curl
  pkgs.libxslt.bin
  pkgs.libxml2.bin
  pkgs.libcap-text-verifier
  pkgs.curl.bin
  pkgs.curl.dev
  pkgs.libssh2.dev
  pkgs.libxslt.dev
  pkgs.libxml2.dev
  pkgs.texinfo
  pkgs.python3Minimal
  pkgs.jansson.dev
  pkgs.libyang.dev
  # Font changes rebuild the GTK shortcut helper. Its build requires the
  # development outputs, which are absent from an activated runtime closure.
  pkgs.gtk3.dev
  pkgs.gobject-introspection.dev
  pkgs.wrapGAppsHook3
]
