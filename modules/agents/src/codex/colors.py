# Adapted from Sylphy modules/codex/src/codex-colors.py at
# 9cba023d90c4485b33a91e2d12724b6920580580.
"""Run Codex in a PTY and replace its fixed TUI accents with the shared palette.

Known RGB accents are changed, and text on selection fills stays readable.
OSC, image protocols, input, and other escape sequences pass through untouched.
Non-terminal invocations use exec.
"""

import argparse
import errno
import os
import pty
import selectors
import signal
import termios
import tty


class ColorFilter:
    def __init__(self, accent, selection, selection_text):
        def rgb(value):
            return tuple(str(int(value[i : i + 2], 16)).encode() for i in (1, 3, 5))

        blues = ((b"99", b"168", b"248"), (b"164", b"205", b"251"), (b"28", b"100", b"200"))
        self.selection_backgrounds = set(blues) | {rgb(selection)}
        self.selection_text = [b"38", b"2", *rgb(selection_text)]
        self.selected = False
        self.foreground = [b"39"]
        self.colors = {
            **{(b"38", color): rgb(accent) for color in blues},
            **{(b"48", color): rgb(selection) for color in blues},
            (b"38", (b"0", b"0", b"46")): rgb(selection_text),
        }
        self.state = "text"
        self.pending = bytearray()
        self.string_kind = None

    def sgr(self, sequence):
        parts = sequence[2:-1].split(b";")
        was_selected = self.selected
        index = 0
        while index < len(parts):
            code = parts[index]
            if code in (b"", b"0"):
                self.selected = False
                self.foreground = [b"39"]
            elif code == b"39" or code.isdigit() and (30 <= int(code) <= 37 or 90 <= int(code) <= 97):
                self.foreground = [code]
            elif code == b"49" or code.isdigit() and (40 <= int(code) <= 47 or 100 <= int(code) <= 107):
                self.selected = False
            if code in (b"38", b"48", b"58"):
                if parts[index + 1 : index + 2] == [b"2"] and index + 4 < len(parts):
                    original = tuple(parts[index + 2 : index + 5])
                    key = (code, original)
                    if key in self.colors:
                        parts[index + 2 : index + 5] = self.colors[key]
                    if code == b"48":
                        self.selected = original in self.selection_backgrounds
                    elif code == b"38":
                        self.foreground = parts[index : index + 5]
                    index += 5
                    continue
                if parts[index + 1 : index + 2] == [b"5"] and index + 2 < len(parts):
                    if code == b"48":
                        self.selected = False
                    elif code == b"38":
                        self.foreground = parts[index : index + 3]
                    index += 3
                    continue
            index += 1
        # Ratatui emits background and per-span foreground changes separately.
        # Resume titles can override the row's foreground with thread colors.
        # Remember the requested foreground so leaving the fill restores it.
        if self.selected:
            parts.extend(self.selection_text)
        elif was_selected:
            parts.extend(self.foreground)
        return b"\x1b[" + b";".join(parts) + b"m"

    def feed(self, data):
        out = bytearray()
        for byte in data:
            if self.state == "text":
                if byte == 27:
                    self.pending.append(byte)
                    self.state = "escape"
                else:
                    out.append(byte)
            elif self.state == "escape":
                self.pending.append(byte)
                if byte == ord("["):
                    self.state = "csi"
                else:
                    out.extend(self.pending)
                    self.pending.clear()
                    self.string_kind = byte
                    self.state = "string" if byte in b"]PX^_" else "text"
            elif self.state == "csi":
                self.pending.append(byte)
                if 0x40 <= byte <= 0x7E:
                    sequence = bytes(self.pending)
                    out.extend(self.sgr(sequence) if byte == ord("m") else sequence)
                    self.pending.clear()
                    self.state = "text"
                elif len(self.pending) > 4096:
                    out.extend(self.pending)
                    self.pending.clear()
                    self.state = "text"
            else:
                out.append(byte)
                if self.state == "string_escape":
                    self.state = "text" if byte == ord("\\") else "string"
                elif byte == 27:
                    self.state = "string_escape"
                elif byte == 7 and self.string_kind == ord("]"):
                    self.state = "text"
        return bytes(out)

    def finish(self):
        return bytes(self.pending)


def write_all(fd, data):
    while data:
        size = os.write(fd, data)
        data = data[size:]


def run(command, colors):
    if not os.isatty(0) or not os.isatty(1):
        os.execvp(command[0], command)

    original = termios.tcgetattr(0)
    size = termios.tcgetwinsize(0)
    pid, master = pty.fork()
    if pid == 0:
        termios.tcsetwinsize(0, size)
        os.execvp(command[0], command)

    def resize(_signum, _frame):
        termios.tcsetwinsize(master, termios.tcgetwinsize(0))

    def forward(signum, _frame):
        try:
            os.killpg(pid, signum)
        except ProcessLookupError:
            pass

    previous = {sig: signal.getsignal(sig) for sig in (signal.SIGWINCH, signal.SIGTERM, signal.SIGHUP, signal.SIGINT)}
    signal.signal(signal.SIGWINCH, resize)
    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(sig, forward)

    try:
        tty.setraw(0)
        with selectors.DefaultSelector() as selector:
            selector.register(0, selectors.EVENT_READ)
            selector.register(master, selectors.EVENT_READ)
            running = True
            while running:
                for key, _ in selector.select():
                    try:
                        data = os.read(key.fd, 65536)
                    except OSError as error:
                        if key.fd == master and error.errno == errno.EIO:
                            running = False
                            break
                        raise
                    if not data:
                        if key.fd == master:
                            running = False
                            break
                        selector.unregister(0)
                        continue
                    if key.fd == master:
                        write_all(1, colors.feed(data))
                    else:
                        write_all(master, data)
        write_all(1, colors.finish())
    finally:
        termios.tcsetattr(0, termios.TCSADRAIN, original)
        os.close(master)
        for sig, handler in previous.items():
            signal.signal(sig, handler)
    _, status = os.waitpid(pid, 0)
    exit_code = os.waitstatus_to_exitcode(status)
    return exit_code if exit_code >= 0 else 128 - exit_code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("accent", "selection", "selection-text"):
        parser.add_argument(f"--{name}", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser.error("a command is required after --")
    return run(command, ColorFilter(args.accent, args.selection, args.selection_text))


if __name__ == "__main__":
    raise SystemExit(main())
