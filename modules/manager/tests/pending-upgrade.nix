{ pkgs }:
let
  configuration = {
    "folio-environment:environment" = {
      account = "fixture";
      scope = "user";
    };
  };
  digest = builtins.hashString "sha256" (builtins.toJSON configuration + "\n");
  identities = {
    models.user = [ ];
    tools = {
      libyang = "fixture";
    };
  };
  bootstrap = pkgs.writeTextDir "identities.json" (builtins.toJSON identities);
  input = {
    format = 1;
    scope = "user";
    inherit configuration;
    configurationDigest = digest;
    inherit (identities) tools;
    models = identities.models.user;
  };
  retained = pkgs.writeTextDir "folio-input.json" (builtins.toJSON input);
  corrupt = pkgs.writeTextDir "folio-input.json" (
    builtins.toJSON (
      input
      // {
        configuration = {
          altered = true;
        };
      }
    )
  );
  closure = pkgs.writeTextDir "folio-home.json" (
    builtins.toJSON {
      format = 1;
      scope = "user";
      account = "fixture";
      home = "/home/fixture";
      configurationDigest = digest;
      bootstrap = toString bootstrap;
    }
  );
in
pkgs.runCommand "folio-pending-upgrade-check"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.bash
      pkgs.jq
      pkgs.coreutils
    ];
    ROLLBACK_SOURCE = ../runtime/operations/rollback.sh;
    FIXTURE_BOOTSTRAP = bootstrap;
    FIXTURE_RETAINED = retained;
    FIXTURE_CORRUPT = corrupt;
    FIXTURE_CLOSURE = closure;
    FIXTURE_DIGEST = digest;
  }
  ''
    python3 ${./test_pending_upgrade.py}
    touch $out
  ''
