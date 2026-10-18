{ prepared, identities }:
let
  digest = value: builtins.hashString "sha256" (builtins.toJSON value + "\n");
  valid =
    prepared.format or null == 1
    && builtins.elem (prepared.scope or null) [
      "system"
      "user"
    ]
    && prepared.configuration."folio-environment:environment".scope == prepared.scope
    && prepared.configurationDigest == digest prepared.configuration
    && prepared.descriptorDigest == digest prepared.systemDescriptor
    && prepared.models == identities.models.${prepared.scope}
    && prepared.tools == identities.tools;
in
if valid then
  prepared
else
  throw "Folio: invalid frozen input format, digest, scope or model/tool identity"
