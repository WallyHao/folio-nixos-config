{"folio-applications:execute":({action:$action,application:$application,"request-id":$id,
      "configuration-digest":$digest,"adopt-files":$adopt,offline:$offline} +
      (if $revision=="" then {} else {revision:$revision} end))}
