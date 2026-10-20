."folio-environment:environment".modules |= map(
  if .name == "agents" and has("folio-agents:agents") then
    ."folio-agents:agents" |= (
      if has("dsh") and has("pi") then
        error("Both dsh and pi settings exist; resolve them before migration")
      elif has("dsh") then
        .pi = {enabled:(.dsh.enabled // false)} | del(.dsh)
      else . end)
  else . end)
