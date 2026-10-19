{"folio-network:execute":({action:$action}
  + (if $connection=="" then {} else {connection:$connection} end)
  + (if $interface=="" then {} else {interface:$interface} end)
  + (if $node=="" then {} else {node:$node} end)
  + (if $mode=="" then {} else {mode:$mode} end))}
