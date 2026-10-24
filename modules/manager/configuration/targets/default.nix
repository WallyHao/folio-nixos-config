{ catalogue }:
{
  portable = import ./portable.nix;
  folio = import ./folio.nix { inherit catalogue; };
}
