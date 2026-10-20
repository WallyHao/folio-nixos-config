import os
import sys


def main():
    if sys.argv[1:] in (["panel"], ["--serve"]):
        if os.geteuid() == 0:
            print(
                "Run folio panel as your desktop user, without sudo.", file=sys.stderr
            )
            return 2
        from .server import launch, serve

        return serve() if sys.argv[1:] == ["--serve"] else launch()
    if sys.argv[1:] == ["--version"]:
        print("folio-panel 0.2.0")
        return 0
    from .paths import LEGACY

    if sys.argv[1:] in (["--help"], ["-h"], []):
        print(
            "  folio panel                 Open the local web control panel in your browser",
            flush=True,
        )
    # Compatibility bridge: unified apply/change history is a separate milestone.
    os.execv(LEGACY, [LEGACY, *sys.argv[1:]])


if __name__ == "__main__":
    sys.exit(main())
