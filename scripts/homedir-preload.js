// Loaded with `node --require` into cursor-agent's own process only: os.homedir() then points at
// the plugin's empty home, so Cursor stops importing ~/.claude (plugins, hooks, skills, agents).
// Environment variables are untouched, so the commands the delegate runs see the real profile.
const os = require("os");
const fakeHome = process.env.CURSOR_RESCUE_FAKE_HOME;
if (fakeHome) os.homedir = () => fakeHome;
