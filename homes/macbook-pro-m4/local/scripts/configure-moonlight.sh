# shellcheck shell=sh
# Keep only the streaming defaults declarative. Moonlight's pairing key,
# certificate, and host list remain mutable cryptographic/user state in the
# same preference domain and are never replaced by this activation.

# Preserve the panel's native aspect ratio, but use a resilient Wi-Fi baseline.
# The MacBook's current 5 GHz link is 288 Mbit/s at MCS 3, and 3456x2234/120
# AV1 drove both NVENC and the radio path too hard: Moonlight continuously
# dropped video and audio packets. 2562x1656 is within 0.01% of the 3456:2234
# panel aspect ratio, cuts pixel work by roughly 45%, and divides cleanly at
# the desktop's MacBook-matched 1.5 scale. 55 Mbit/s AV1 leaves practical
# airtime headroom for Wi-Fi retransmits and control traffic.
run /usr/bin/defaults write com.moonlight-stream.Moonlight width -int 2562
run /usr/bin/defaults write com.moonlight-stream.Moonlight height -int 1656
run /usr/bin/defaults write com.moonlight-stream.Moonlight fps -int 120
run /usr/bin/defaults write com.moonlight-stream.Moonlight bitrate -int 55000
run /usr/bin/defaults write com.moonlight-stream.Moonlight autoadjustbitrate -bool true

# AV1 hardware decoding is supported by the M4 Pro media engine. Keep normal
# 4:2:0 chroma: YUV 4:4:4 would nearly double bandwidth for little gaming
# benefit. HDR stays disabled because Sunshine's headless wlroots capture
# cannot send HDR metadata; enabling it would produce a 10-bit SDR stream, not
# genuine HDR.
run /usr/bin/defaults write com.moonlight-stream.Moonlight videocfg -int 4
run /usr/bin/defaults write com.moonlight-stream.Moonlight videodec -int 1
run /usr/bin/defaults write com.moonlight-stream.Moonlight hdr -bool false
run /usr/bin/defaults write com.moonlight-stream.Moonlight yuv444 -bool false

# Borderless fullscreen matches the macOS desktop including the panel's native
# aspect ratio. V-sync and frame pacing give the panel a stable presentation
# cadence; adaptive bitrate handles transient Wi-Fi contention without a manual
# settings change.
run /usr/bin/defaults write com.moonlight-stream.Moonlight windowmode -int 1
run /usr/bin/defaults write com.moonlight-stream.Moonlight vsync -bool true
run /usr/bin/defaults write com.moonlight-stream.Moonlight framepacing -bool true
