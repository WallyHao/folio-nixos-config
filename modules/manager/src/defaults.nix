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
          { name = "terminal"; enabled = true; }
          { name = "network"; enabled = true; }
          { name = "applications"; enabled = true; }
          { name = "appearance"; enabled = true; }
          { name = "desktop"; enabled = true; }
          { name = "devices"; enabled = true; }
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
          { name = "appearance"; enabled = true; }
          { name = "input"; enabled = true; }
          { name = "emacs"; enabled = true; }
          { name = "agents"; enabled = true; "folio-agents:agents".pi.enabled = true; }
          { name = "desktop"; enabled = true; }
          { name = "devices"; enabled = true; }
          {
            name = "applications";
            enabled = true;
            "folio-applications:applications".app = [
              { name = "zen"; ref = "app/app.zen_browser.zen/x86_64/stable"; selected = true; }
              { name = "obs"; ref = "app/com.obsproject.Studio/x86_64/stable"; selected = true; }
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
