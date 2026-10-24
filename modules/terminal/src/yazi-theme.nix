{ palette }: {
  app.overall.bg = palette.bg0;
  mgr = {
    cwd.fg = palette.aqua;
    border_style.fg = palette.grey0;
    find_keyword = {
      fg = palette.yellow;
      bold = true;
    };
    find_position.fg = palette.purple;
    symlink_target.fg = palette.grey1;
    marker_copied = {
      fg = palette.green;
      bg = palette.green;
    };
    marker_cut = {
      fg = palette.red;
      bg = palette.red;
    };
    marker_marked = {
      fg = palette.aqua;
      bg = palette.aqua;
    };
    marker_selected = {
      fg = palette.yellow;
      bg = palette.yellow;
    };
    count_copied = {
      fg = palette.bg0;
      bg = palette.green;
    };
    count_cut = {
      fg = palette.bg0;
      bg = palette.red;
    };
    count_selected = {
      fg = palette.bg0;
      bg = palette.yellow;
    };
  };
  indicator = {
    parent = {
      fg = palette.fg;
      bg = palette.bg1;
    };
    current = {
      fg = palette.fg;
      bg = palette.bg_visual;
      bold = true;
    };
    preview = {
      fg = palette.fg;
      bg = palette.bg1;
    };
  };
  tabs = {
    active = {
      fg = palette.bg0;
      bg = palette.green;
      bold = true;
    };
    inactive = {
      fg = palette.fg;
      bg = palette.bg2;
    };
  };
  mode = {
    normal_main = {
      fg = palette.bg0;
      bg = palette.green;
      bold = true;
    };
    normal_alt = {
      fg = palette.green;
      bg = palette.bg2;
    };
    select_main = {
      fg = palette.bg0;
      bg = palette.blue;
      bold = true;
    };
    select_alt = {
      fg = palette.blue;
      bg = palette.bg2;
    };
    unset_main = {
      fg = palette.bg0;
      bg = palette.red;
      bold = true;
    };
    unset_alt = {
      fg = palette.red;
      bg = palette.bg2;
    };
  };
  status = {
    overall = {
      fg = palette.fg;
      bg = palette.bg1;
    };
    perm_type.fg = palette.aqua;
    perm_read.fg = palette.yellow;
    perm_write.fg = palette.red;
    perm_exec.fg = palette.green;
    perm_sep.fg = palette.grey0;
    progress_label = {
      fg = palette.fg;
      bold = true;
    };
    progress_normal = {
      fg = palette.blue;
      bg = palette.bg2;
    };
    progress_error = {
      fg = palette.red;
      bg = palette.bg2;
    };
  };
  input = {
    border.fg = palette.green;
    title.fg = palette.green;
    value.fg = palette.fg;
    selected.bg = palette.bg_visual;
  };
  pick = {
    border.fg = palette.green;
    active.fg = palette.yellow;
    inactive.fg = palette.fg;
  };
  which = {
    mask.bg = palette.bg1;
    cand.fg = palette.aqua;
    rest.fg = palette.grey1;
    desc.fg = palette.fg;
    separator_style.fg = palette.grey0;
  };
  help = {
    on.fg = palette.aqua;
    run.fg = palette.green;
    desc.fg = palette.fg;
    hovered.bg = palette.bg_visual;
    footer = {
      fg = palette.bg0;
      bg = palette.green;
    };
  };
  filetype.rules = [
    {
      mime = "image/*";
      fg = palette.purple;
    }
    {
      mime = "video/*";
      fg = palette.yellow;
    }
    {
      mime = "audio/*";
      fg = palette.yellow;
    }
    {
      mime = "application/pdf";
      fg = palette.red;
    }
    {
      url = "*/";
      fg = palette.blue;
    }
    {
      url = "*";
      fg = palette.fg;
    }
  ];
}
