{
  pkgs,
  lib,
  tools,
}:
import (pkgs.path + "/nixos/lib/make-disk-image.nix") {
  inherit pkgs lib;
  config = pkgs.folio.systemConfiguration.config;
  name = "folio-uefi-image";
  baseName = "folio";
  format = "qcow2";
  partitionTableType = "efi";
  installBootLoader = true;
  touchEFIVars = false;
  diskSize = "auto";
  additionalSpace = "2048M";
  copyChannel = false;
  additionalPaths = [ pkgs.folio.source ] ++ pkgs.folio.lockedInputs;
  postVM = ''
    mkdir -p $out/bin
    cat >$out/bin/run-folio-vm <<'SCRIPT'
    #!${pkgs.runtimeShell}
    set -euo pipefail
    export PATH=${pkgs.coreutils}/bin
    umask 0077
    id=''${1:-portable}
    image=$(dirname "$(dirname "$(readlink -f "$0")")")
    state=''${XDG_STATE_HOME:-$HOME/.local/state}/folio/vm/jobs/$id
    [[ "$id" =~ ^[a-z][a-z0-9-]{0,63}$ ]] || exit 2
    mkdir -p "$state"
    if [[ ! -f "$state/job.json" ]]; then
      printf '{"id":"%s","phase":"ready","image":"%s"}\n' "$id" "$image" |
        ${pkgs.folio.atomicWrite}/bin/folio-atomic-write "$state/job.json"
    fi
    ${pkgs.jq}/bin/jq -e --arg image "$image" '.image==$image' "$state/job.json" >/dev/null || {
      echo 'VM job ID is bound to another image; select a new ID or explicitly clean up the stopped job' >&2
      exit 4
    }
    exec ${tools}/bin/folio-vm-tool start "$id"
    SCRIPT
    chmod +x $out/bin/run-folio-vm
  '';
}
