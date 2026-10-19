."folio-environment:environment".modules |= (
  (map(select(.name == "git")) | first) as $git |
  if $git == null then .
  else
    (map(select(.name == "terminal")) | first) as $terminal |
    if $terminal != null and ($terminal | has("folio-terminal:terminal")) and
       ($terminal."folio-terminal:terminal" | has("git")) then
      error("Both legacy Git and terminal.git settings exist; resolve them before migration")
    elif $git.enabled and $terminal != null and ($terminal.enabled | not) then
      error("Git is enabled but terminal is disabled; resolve terminal selection before migration")
    else
      (if $terminal == null then . + [{name:"terminal", enabled:$git.enabled,
        "folio-terminal:terminal":{
          shell:{enabled:false}, foot:{enabled:false},
          tools:{bat:false,btop:false,eza:false,fd:false,fzf:false,jq:false,ripgrep:false,
                 zoxide:false,unzip:false,unrar:false,chsrc:false,just:false,typst:false}}}]
       else . end) |
      map(if .name == "terminal" then
        ."folio-terminal:terminal".git = (($git."folio-git:git" // {}) + {enabled:$git.enabled})
      else . end) | map(select(.name != "git"))
    end
  end)
