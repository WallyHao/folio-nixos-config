"""Focused regression checks for selection spans and streaming ANSI state."""

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
source = Path(
    os.environ.get(
        "FOLIO_CODEX_COLORS", Path(__file__).resolve().parents[1] / "src/codex/colors.py"
    )
)
spec = importlib.util.spec_from_file_location("codex_colors", source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

FG = b"38;2;211;198;170"
BG = b"48;2;76;55;67"
BLUE_BG = b"\x1b[48;2;99;168;248m"


def color_filter():
    return module.ColorFilter("#a7c080", "#4c3743", "#d3c6aa")


class SelectionColors(unittest.TestCase):
    def test_slash_menu(self):
        output = color_filter().feed(b"\x1b[38;2;0;0;46;48;2;99;168;248m/resume")
        self.assertIn(BG, output)
        self.assertIn(FG, output)
        self.assertTrue(output.endswith(b"/resume"))

    def test_resume_span_foregrounds(self):
        for foreground in (b"30", b"38;5;0", b"38;2;39;46;51", b"38;2;68;43;57", b"39"):
            with self.subTest(foreground=foreground):
                f = color_filter()
                f.feed(BLUE_BG)
                output = f.feed(b"\x1b[" + foreground + b"mConversation")
                self.assertEqual(output, b"\x1b[" + foreground + b";" + FG + b"mConversation")

    def test_foreground_before_background(self):
        f = color_filter()
        f.feed(b"\x1b[30m")
        self.assertEqual(f.feed(BLUE_BG), b"\x1b[" + BG + b";" + FG + b"m")

    def test_leaving_selection_restores_requested_foreground(self):
        for background in (b"49", b"48;2;39;46;51", b"48;5;0", b"40"):
            with self.subTest(background=background):
                f = color_filter()
                f.feed(BLUE_BG + b"\x1b[38;2;68;43;57mSelected")
                self.assertEqual(
                    f.feed(b"\x1b[" + background + b"mNormal"),
                    b"\x1b[" + background + b";38;2;68;43;57mNormal",
                )

    def test_reset_and_normal_error_colors(self):
        f = color_filter()
        f.feed(BLUE_BG + b"\x1b[30mSelected")
        self.assertEqual(f.feed(b"\x1b[0m"), b"\x1b[0;39m")
        error = b"\x1b[38;2;230;126;128mError\x1b[39m"
        self.assertEqual(f.feed(error), error)

    def test_fragmented_stream(self):
        data = b"\x1b[30m" + BLUE_BG + b"A\x1b[38;2;68;43;57mB\x1b[49mC\x1b[0m"
        expected = color_filter().feed(data)
        for width in (1, 2, 7, 19):
            f = color_filter()
            self.assertEqual(
                b"".join(f.feed(data[i : i + width]) for i in range(0, len(data), width))
                + f.finish(),
                expected,
            )

    def test_osc_and_control_sequences_are_untouched(self):
        data = b"\x1b]0;title\x1b[30m\x07\x1b[2J\x1b[3;4H"
        self.assertEqual(color_filter().feed(data), data)

    def test_non_terminal_preserves_output_arguments_and_exit_status(self):
        data = b"\x1b[38;2;99;168;248m unchanged\n"
        result = subprocess.run(
            [
                sys.executable,
                str(source),
                "--accent",
                "#a7c080",
                "--selection",
                "#4c3743",
                "--selection-text",
                "#d3c6aa",
                "--",
                sys.executable,
                "-c",
                "import sys; assert sys.argv[1] == 'a b'; sys.stdout.buffer.write(sys.stdin.buffer.read()); sys.exit(7)",
                "a b",
            ],
            input=data,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 7)
        self.assertEqual(result.stdout, data)
        self.assertEqual(result.stderr, b"")

    def test_light_palette_and_protocol_payloads(self):
        f = module.ColorFilter("#8da101", "#f0f2d4", "#5c6a72")
        self.assertEqual(f.feed(b"\x1b[38;2;99;168;248m"), b"\x1b[38;2;141;161;1m")
        f = color_filter()
        data = b"\x1bPpayload\x1b[38;2;99;168;248m\x1b\\" + b"\x1b_Gimage\x1b[30m\x1b\\"
        self.assertEqual(b"".join(f.feed(bytes([byte])) for byte in data), data)


if __name__ == "__main__":
    unittest.main()
