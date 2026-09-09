-- Exercise the real plugin using an mpv adapter that records its public calls.
local messages = {}
local calls = {}
local osd = nil
_G.mp = {
  commandv = function(...)
    calls[#calls + 1] = table.concat({ ... }, ":")
  end,
  osd_message = function(text, duration)
    assert(duration == 2, "unexpected OSD duration")
    osd = text
  end,
  register_script_message = function(name, callback)
    assert(messages[name] == nil, "duplicate message: " .. name)
    messages[name] = callback
  end,
}

assert(loadfile(arg[1]))()
local expected_messages = {
  "toggle-anime-fast",
  "toggle-anime-hq",
  "toggle-smooth-motion",
  "toggle-max-anime-mode",
  "reset-anime-modes",
}
local count = 0
for _ in pairs(messages) do
  count = count + 1
end
assert(count == #expected_messages, "unexpected message registration count")
for _, name in ipairs(expected_messages) do
  assert(type(messages[name]) == "function", "missing message: " .. name)
end

local function step(name, expected_calls, expected_osd)
  calls = {}
  messages[name]()
  assert(table.concat(calls, ",") == expected_calls, name .. ": " .. table.concat(calls, ","))
  assert(osd == expected_osd, name .. ": unexpected OSD: " .. tostring(osd))
end

step("reset-anime-modes", "", "Playback: Normal")
step("toggle-anime-fast", "apply-profile:anime-fast:apply", "Anime4K Fast")
step("toggle-anime-fast", "apply-profile:anime-fast:restore", "Playback: Normal")
step("toggle-anime-fast", "apply-profile:anime-fast:apply", "Anime4K Fast")
step(
  "toggle-anime-hq",
  "apply-profile:anime-fast:restore,apply-profile:anime-hq:apply",
  "Anime4K HQ"
)
step("toggle-smooth-motion", "apply-profile:smooth-motion:apply", "Anime4K HQ + Smooth Motion")
step(
  "toggle-max-anime-mode",
  "apply-profile:anime-hq:restore,apply-profile:anime-fast:apply",
  "Anime4K Fast + Smooth Motion"
)
step(
  "toggle-max-anime-mode",
  "apply-profile:anime-fast:restore,apply-profile:smooth-motion:restore",
  "Playback: Normal"
)
step("toggle-smooth-motion", "apply-profile:smooth-motion:apply", "Smooth Motion")
step("toggle-smooth-motion", "apply-profile:smooth-motion:restore", "Playback: Normal")
step(
  "toggle-max-anime-mode",
  "apply-profile:anime-fast:apply,apply-profile:smooth-motion:apply",
  "Anime4K Fast + Smooth Motion"
)
step(
  "toggle-anime-hq",
  "apply-profile:anime-fast:restore,apply-profile:anime-hq:apply",
  "Anime4K HQ + Smooth Motion"
)
step("toggle-anime-hq", "apply-profile:anime-hq:restore", "Smooth Motion")
step("reset-anime-modes", "apply-profile:smooth-motion:restore", "Playback: Normal")
