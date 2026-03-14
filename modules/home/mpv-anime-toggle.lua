local state = {
    anime = nil,
    smooth = false,
}

local reset_modes

local function apply_profile(name)
    mp.commandv("apply-profile", name, "apply")
end

local function restore_profile(name)
    mp.commandv("apply-profile", name, "restore")
end

local function show_state()
    local parts = {}

    if state.anime == "anime-fast" then
        table.insert(parts, "Anime4K Fast")
    elseif state.anime == "anime-hq" then
        table.insert(parts, "Anime4K HQ")
    end

    if state.smooth then
        table.insert(parts, "Smooth Motion")
    end

    if #parts == 0 then
        mp.osd_message("Playback: Normal", 2)
        return
    end

    mp.osd_message(table.concat(parts, " + "), 2)
end

local function set_anime_mode(profile)
    if state.anime == profile then
        restore_profile(profile)
        state.anime = nil
        show_state()
        return
    end

    if state.anime ~= nil then
        restore_profile(state.anime)
    end

    apply_profile(profile)
    state.anime = profile
    show_state()
end

local function toggle_smooth_motion()
    if state.smooth then
        restore_profile("smooth-motion")
        state.smooth = false
    else
        apply_profile("smooth-motion")
        state.smooth = true
    end

    show_state()
end

local function toggle_max_anime_mode()
    local max_mode_active = state.anime == "anime-fast" and state.smooth

    if max_mode_active then
        reset_modes()
        return
    end

    if state.anime == "anime-hq" then
        restore_profile("anime-hq")
        state.anime = nil
    end

    if state.anime ~= "anime-fast" then
        if state.anime ~= nil then
            restore_profile(state.anime)
        end

        apply_profile("anime-fast")
        state.anime = "anime-fast"
    end

    if not state.smooth then
        apply_profile("smooth-motion")
        state.smooth = true
    end

    show_state()
end

reset_modes = function()
    if state.anime ~= nil then
        restore_profile(state.anime)
        state.anime = nil
    end

    if state.smooth then
        restore_profile("smooth-motion")
        state.smooth = false
    end

    show_state()
end

mp.register_script_message("toggle-anime-fast", function()
    set_anime_mode("anime-fast")
end)

mp.register_script_message("toggle-anime-hq", function()
    set_anime_mode("anime-hq")
end)

mp.register_script_message("toggle-max-anime-mode", toggle_max_anime_mode)
mp.register_script_message("toggle-smooth-motion", toggle_smooth_motion)
mp.register_script_message("reset-anime-modes", reset_modes)
