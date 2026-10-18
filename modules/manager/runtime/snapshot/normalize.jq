# These lists are ordered-by system in folio-environment@2026-10-18. Do not sort
# arbitrary arrays: later ordered-by user lists must retain their semantics.
."folio-environment:environment" |= (
  .modules |= (map(if has("folio-applications:applications") then
      ."folio-applications:applications" |= (if has("app") then .app |= sort_by(.name) else . end)
    else . end) | sort_by(.name))
  | if has("users") then
      .users |= (map(if has("groups") then .groups |= sort else . end) | sort_by(.name))
    else . end
)
