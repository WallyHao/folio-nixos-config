# Koru token styling with the selected Folio palette.
supplied@{ theme }:
let
  p = supplied.theme.colors.palettes.${supplied.theme.colors.appearance or "dark"};
  theme = {
    bg = p.bg0; bg-alt = p.bg1; fg = p.fg; cursor = p.fg;
    accent = p.green; accent-bg = p.bg_visual; accent-bright = p.aqua;
    accent-yellow = p.yellow; accent-yellow-bright = p.orange; muted-alt = p.grey1;
    ansi = { red = p.red; yellow = p.yellow; magenta = p.purple; cyan = p.aqua; };
    ansi-bright.red = p.red;
  };
in
''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>name</key>
      <string>Folio Everforest</string>
      <key>author</key>
      <string>Folio</string>
      <key>settings</key>
      <array>
        <dict>
          <key>scope</key>
          <string>codex.accent</string>
          <key>settings</key>
          <dict>
            <key>foreground</key>
            <string>${theme.accent}</string>
          </dict>
        </dict>
        <dict>
          <key>settings</key>
          <dict>
            <key>background</key>
            <string>${theme.bg}</string>
            <key>foreground</key>
            <string>${theme.fg}</string>
            <key>caret</key>
            <string>${theme.cursor}</string>
            <key>selection</key>
            <string>${theme.accent-bg}</string>
            <key>lineHighlight</key>
            <string>${theme.bg-alt}</string>
            <key>findHighlight</key>
            <string>${theme.ansi.yellow}</string>
            <key>inactiveSelection</key>
            <string>${theme.bg-alt}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key>
          <string>comment, punctuation.definition.comment</string>
          <key>settings</key>
          <dict>
            <key>foreground</key>
            <string>${theme.muted-alt}</string>
            <key>fontStyle</key>
            <string>italic</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key>
          <string>keyword, storage, storage.type, storage.modifier</string>
          <key>settings</key>
          <dict>
            <key>foreground</key>
            <string>${theme.accent-yellow}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key>
          <string>string, string.quoted, string.regexp, constant.character</string>
          <key>settings</key>
          <dict>
            <key>foreground</key>
            <string>${theme.accent-bright}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key>
          <string>constant.numeric, constant.language, constant.other</string>
          <key>settings</key>
          <dict>
            <key>foreground</key>
            <string>${theme.ansi.magenta}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key>
          <string>variable, variable.parameter, variable.other</string>
          <key>settings</key>
          <dict>
            <key>foreground</key>
            <string>${theme.accent-yellow-bright}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key>
          <string>entity.name.function, support.function, meta.function-call</string>
          <key>settings</key>
          <dict>
            <key>foreground</key>
            <string>${theme.accent}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key>
          <string>entity.name.type, entity.name.class, entity.name.tag, support.type, support.class</string>
          <key>settings</key>
          <dict>
            <key>foreground</key>
            <string>${theme.accent-yellow}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key>
          <string>keyword.operator, punctuation, punctuation.separator</string>
          <key>settings</key>
          <dict>
            <key>foreground</key>
            <string>${theme.ansi.cyan}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key>
          <string>markup.inserted, diff.inserted</string>
          <key>settings</key>
          <dict>
            <key>foreground</key>
            <string>${theme.accent-bright}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key>
          <string>markup.deleted, diff.deleted</string>
          <key>settings</key>
          <dict>
            <key>foreground</key>
            <string>${theme.ansi-bright.red}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key>
          <string>markup.changed</string>
          <key>settings</key>
          <dict>
            <key>foreground</key>
            <string>${theme.accent-yellow}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key>
          <string>invalid, invalid.illegal</string>
          <key>settings</key>
          <dict>
            <key>foreground</key>
            <string>${theme.ansi.red}</string>
          </dict>
        </dict>
      </array>
    </dict>
    </plist>
  ''
