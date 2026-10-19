import os
import sys


def main():
    if sys.argv[1:] == ["panel"]:
        if os.geteuid() == 0:
            print(
                "Run folio panel as your desktop user, without sudo.", file=sys.stderr
            )
            return 2
        from .app import Panel

        Panel().run()
        return 0
    if sys.argv[1:] == ["--version"]:
        print("folio-panel 0.1.0")
        return 0
    from .paths import LEGACY

    if sys.argv[1:] in (["--help"], ["-h"], []):
        print(
            "  folio panel                 Open the Wi-Fi, proxy and device control panel",
            flush=True,
        )
    # Compatibility bridge: unified apply/change history is a separate milestone.
    os.execv(LEGACY, [LEGACY, *sys.argv[1:]])


if __name__ == "__main__":
    sys.exit(main())
