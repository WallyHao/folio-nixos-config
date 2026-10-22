# Local theme overrides are obsolete; the system owns the shared theme.
."folio-environment:environment".modules |= map(
  if has("folio-appearance:appearance") then
    ."folio-appearance:appearance" |= del(.appearance)
  else . end
)
