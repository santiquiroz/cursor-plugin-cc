// Loaded with `node --require` into cursor-agent's own process only (Windows node.exe bundle).
// MSYS2_ARG_CONV_EXCL kept Git Bash from rewriting the task argument; drop it so the commands the
// delegate runs convert POSIX paths again. With CURSOR_RESCUE_FAKE_HOME set, os.homedir() points at
// the plugin's empty home, so Cursor stops importing ~/.claude (plugins, hooks, skills, agents);
// environment variables stay untouched, so those commands still see the real profile.
const os = require("os");
delete process.env.MSYS2_ARG_CONV_EXCL;
delete process.env.MSYS_NO_PATHCONV;
const fakeHome = process.env.CURSOR_RESCUE_FAKE_HOME;
if (fakeHome) os.homedir = () => fakeHome;
