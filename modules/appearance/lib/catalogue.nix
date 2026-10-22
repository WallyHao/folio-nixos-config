{
  everforest = builtins.fromJSON (builtins.readFile ./everforest.json);
  graphite = builtins.fromJSON (builtins.readFile ./graphite.json);
}
