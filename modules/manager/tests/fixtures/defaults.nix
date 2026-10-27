{ scope }:
{
  "folio-environment:environment" = {
    name = "portable";
    platform = "x86_64-linux";
    inherit scope;
    preferences = {
      font-family = "Maple Mono NF CN";
      font-size = 16;
    }
    // (
      if scope == "system" then
        {
          scheme = "everforest";
          appearance = "dark";
        }
      else
        { }
    );
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
            name = "terminal";
            enabled = true;
          }
          {
            name = "network";
            enabled = true;
          }
          {
            name = "workspace";
            enabled = true;
          }
          {
            name = "applications";
            enabled = true;
          }
          {
            name = "appearance";
            enabled = true;
          }
          {
            name = "desktop";
            enabled = true;
          }
          {
            name = "devices";
            enabled = true;
          }
          {
            name = "system";
            enabled = true;
            "folio-system:system".time-zone = "Asia/Shanghai";
          }
          {
            name = "vm";
            enabled = true;
          }
        ]
      else
        [
          {
            name = "appearance";
            enabled = true;
            "folio-appearance:appearance".cursor-size = 42;
          }
          {
            name = "input";
            enabled = true;
          }
          {
            name = "neovim";
            enabled = true;
          }
          {
            name = "agents";
            enabled = true;
            "folio-agents:agents".pi.enabled = true;
          }
          {
            name = "workspace";
            enabled = true;
          }
          {
            name = "desktop";
            enabled = true;
          }
          {
            name = "devices";
            enabled = true;
          }
          {
            name = "applications";
            enabled = true;
            "folio-applications:applications".app = [
              {
                name = "zen";
                ref = "app/app.zen_browser.zen/x86_64/stable";
                selected = true;
              }
              {
                name = "obs";
                ref = "app/com.obsproject.Studio/x86_64/stable";
                selected = true;
              }
            ];
          }
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
            groups = [
              "folio-operators"
              "kvm"
              "video"
            ];
            login-shell = "bash";
          }
        ];
      }
  );
}
