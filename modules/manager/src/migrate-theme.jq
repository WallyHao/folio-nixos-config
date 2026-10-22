# Keep system theme selection and discard legacy per-user theme preferences.
."folio-environment:environment" |= (
  if .scope == "user" and has("preferences") then
    .preferences |= del(.scheme, .appearance)
  else . end
)
