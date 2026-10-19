"use strict";
// Exercise real native libraries without an API key or model request.
const assert = require("node:assert/strict");
const path = require("node:path");
const [root, shell] = process.argv.slice(2);
const koffi = require(path.join(root, "koffi"));
const getpid = koffi.load("libc.so.6").func("int getpid(void)");
assert.equal(getpid(), process.pid);
const sharp = require(path.join(root, "sharp"));
assert.ok(sharp.versions.vips);
const pty = require(path.join(root, "node-pty"));
const child = pty.spawn(shell, ["--noprofile", "--norc", "-c", "printf folio-native-pty"], {
  name: "xterm", cols: 80, rows: 24, env: process.env,
});
let output = "";
const timer = setTimeout(() => { child.kill(); process.exitCode = 1; }, 10000);
child.onData(data => { output += data; });
child.onExit(({exitCode}) => {
  clearTimeout(timer);
  assert.equal(exitCode, 0);
  assert.ok(output.includes("folio-native-pty"));
});
