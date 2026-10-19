{"folio-devices:execute":({action:$action}
  + (if $level==null then {} else {level:$level} end)
  + (if $amount==null then {} else {amount:$amount} end)
  + (if $profile=="" then {} else {profile:$profile} end))}
