// Loads the addon in TOC order under a stubbed WoW API and runs tests/smoke.lua.
// Also syntax-checks every file as Lua 5.1 and checks that every feat listens
// on a signal some file actually fires.   Usage: npm ci && node run.js
const fs = require("fs");
const path = require("path");
const luaparse = require("luaparse");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");

const root = path.join(__dirname, "..");
const toc = fs.readFileSync(path.join(root, "FiftyDKPMinus.toc"), "utf8");
const files = toc.split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith("#")).map((l) => l.replace(/\\/g, "/"));
let failed = 0;

// 1. Lua 5.1 syntax
const sources = {};
for (const f of files) {
  const full = path.join(root, f);
  if (!fs.existsSync(full)) { console.log(`MISSING ${f}`); failed++; continue; }
  sources[f] = fs.readFileSync(full, "utf8");
  try { luaparse.parse(sources[f], { luaVersion: "5.1" }); }
  catch (e) { console.log(`SYNTAX ${f}: ${e.message}`); failed++; }
}
console.log(`syntax: ${files.length} files`);

// 2. Every feat signal must be fired somewhere
const all = Object.values(sources).join("\n");
const fired = new Set([...all.matchAll(/Fire\(\s*(?:[\w.]+ and )?"([A-Z_]+)"(?: or "([A-Z_]+)")?/g)].flatMap((m) => [m[1], m[2]]).filter(Boolean));
const listened = new Set([...all.matchAll(/signal = "([A-Z_]+)"/g)].map((m) => m[1]));
listened.add("UI_ERROR");
for (const s of listened) if (!fired.has(s)) { console.log(`DEAD SIGNAL ${s}: a feat listens but nothing fires it`); failed++; }
console.log(`signals: ${listened.size} listened, ${fired.size} fired`);

// 3. Run
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const run = (src, name, nargs) => {
  if (lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring("@" + name)) !== lua.LUA_OK) {
    throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  }
  if (nargs) lua.lua_insert(L, -(nargs + 1));
  if (lua.lua_pcall(L, nargs || 0, 1, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
};
try {
  run(fs.readFileSync(path.join(__dirname, "stubs.lua"), "utf8"), "stubs.lua");
  lua.lua_pop(L, 1);
  lua.lua_newtable(L);
  lua.lua_setglobal(L, to_luastring("__ns"));
  for (const f of files) {
    lua.lua_pushliteral(L, "FiftyDKPMinus");
    lua.lua_getglobal(L, to_luastring("__ns"));
    run(sources[f], f, 2);
    lua.lua_pop(L, 1);
  }
  lua.lua_getglobal(L, to_luastring("__ns"));
  run(fs.readFileSync(path.join(__dirname, "smoke.lua"), "utf8"), "smoke.lua", 1);
  failed += lua.lua_tointeger(L, -1);
} catch (e) {
  console.log("ERROR " + e.message);
  failed++;
}
console.log(failed ? `\n${failed} FAILED` : "\nall passed");
process.exit(failed ? 1 : 0);
