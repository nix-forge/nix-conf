-- Match mpv's LuaJIT runtime; application globals are read-only and local.
std = "luajit"
max_line_length = 100

files["modules/home/mpv/*.lua"] = { read_globals = { "mp" } }
files["tests/hyprland/**/*.lua"] = { read_globals = { "hl" } }
-- The adapter deliberately supplies mpv's API to the real plugin.
files["tests/lua/check-mpv-anime-toggle.lua"] = { globals = { "mp" } }
