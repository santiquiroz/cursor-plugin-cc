// Turns cursor-agent's stream-json into a compact progress log, line by line, so a run cut by
// the timeout still shows what it did. Non-JSON lines (errors cursor-agent prints) pass through.
const readline = require("readline");

const NOISE = /^(Connection lost|Retry attempt)/;

function oneLine(value, max) {
  const text = String(value || "").replace(/\s+/g, " ").trim();
  return text.length > max ? text.slice(0, max) + "..." : text;
}

function failureOf(result) {
  if (!result) return "";
  if (result.rejected) return result.rejected.reason || "rejected";
  if (result.permissionDenied) return result.permissionDenied.error + ": " + result.permissionDenied.command;
  if (result.error) return result.error.error || result.error.errorMessage || result.error.message || JSON.stringify(result.error);
  return "";
}

function targetOf(args) {
  return args.command || args.path || args.pattern || args.globPattern || args.query || args.toolName
    || Object.values(args).find((value) => typeof value === "string");
}

function assistantText(event) {
  const content = (event.message || {}).content || [];
  return content.filter((part) => part && part.type === "text").map((part) => part.text).join("");
}

function toolCallLine(event) {
  const calls = event.tool_call || {};
  const kind = Object.keys(calls)[0] || "tool";
  const body = calls[kind] || {};
  const name = kind.replace(/ToolCall$/, "");
  if (event.subtype === "started") return "  > " + name + " " + oneLine(targetOf(body.args || {}), 160);
  const failure = failureOf(body.result);
  return failure ? "  x " + name + ": " + oneLine(String(failure).split("\n")[0], 220) : "";
}

function resultLine(event) {
  const seconds = Math.round((event.duration_ms || 0) / 1000);
  return "[cursor-rescue] " + (event.is_error ? "error" : "done") + " in " + seconds + "s, session " + event.session_id;
}

function render(line) {
  let event;
  try {
    event = JSON.parse(line);
  } catch (e) {
    return line.trim() && !NOISE.test(line) ? line : "";
  }
  if (!event || typeof event !== "object") return "";
  if (event.type === "assistant") return assistantText(event);
  if (event.type === "tool_call") return toolCallLine(event);
  if (event.type === "result") return resultLine(event);
  return "";
}

readline.createInterface({ input: process.stdin }).on("line", (line) => {
  const out = render(line);
  if (out) console.log(out);
});
