{ scope }:
{
  "folio-environment:environment" = {
    name = "portable";
    platform = "x86_64-linux";
    inherit scope;
    preferences = {
      scheme = "everforest";
      appearance = "dark";
      font-family = "Maple Mono NF CN";
      font-size = 16;
    };
    modules = [
      {
        name = "manager";
        enabled = true;
      }
      {
        name = "sysrepo";
        enabled = true;
      }
    ]
    ++ (
      if scope == "system" then
        [
          {
            name = "system";
            enabled = true;
          }
        ]
      else
        [
          {
            name = "terminal";
            enabled = true;
            "folio-terminal:terminal".foot = {
              enabled = true;
              padding = "15x15";
            };
          }
        ]
    );
  }
  // (
    if scope == "user" then
      { account = "folio"; }
    else
      {
        users = [
          {
            name = "folio";
            uid = 1000;
            home = "/home/folio";
            groups = [ "wheel" ];
            login-shell = "bash";
          }
        ];
      }
  );
}
