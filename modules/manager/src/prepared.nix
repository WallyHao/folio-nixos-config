{ prepared, identities }:
let
  digest = value: builtins.hashString "sha256" (builtins.toJSON value + "\n");
  preferences = let values = prepared.configuration."folio-environment:environment".preferences or { };
    in if prepared.scope == "user" then builtins.removeAttrs values [ "scheme" "appearance" ] else values;
  resolvedPreferences = {
    values = prepared.systemDescriptor.preferences // preferences;
    origins = builtins.mapAttrs (
      name: _:
      if prepared.scope == "system" then
        "system-configuration"
      else if builtins.hasAttr name preferences then
        "user-configuration"
      else
        "system-default"
    ) resolvedPreferences.values;
  };
  valid =
    prepared.format or null == 1
    && builtins.elem (prepared.scope or null) [
      "system"
      "user"
    ]
    && prepared.configuration."folio-environment:environment".scope == prepared.scope
    &&
      prepared.systemDescriptor.environment == prepared.configuration."folio-environment:environment".name
    &&
      prepared.systemDescriptor.platform
      == prepared.configuration."folio-environment:environment".platform
    && prepared.configurationDigest == digest prepared.configuration
    && prepared.descriptorDigest == digest prepared.systemDescriptor
    && prepared.models == identities.models.${prepared.scope}
    && prepared.tools == identities.tools
    && prepared.resolvedPreferences == resolvedPreferences;
in
if valid then
  prepared
else
  throw "Folio: invalid frozen input format, digest, scope or model/tool identity"
