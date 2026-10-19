."folio-environment:environment".modules |= (
  if any(.[]; .name == "codex") and any(.[]; .name == "agents") then
    error("Both codex and agents selections exist; resolve them before migration")
  else map(if .name == "codex" then
    {name:"agents", enabled:.enabled,
     "folio-agents:agents":{codex:((."folio-codex:codex" // {}) + {enabled:true}),
                            dsh:{enabled:false}}}
  else . end) end)
