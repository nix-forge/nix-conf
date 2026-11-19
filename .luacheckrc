-- Match mpv's LuaJIT runtime; application globals are read-only and local.
std = "luajit"
max_line_length = 100

files["modules/home/mpv/*.lua"] = { read_globals = { "mp" } }
