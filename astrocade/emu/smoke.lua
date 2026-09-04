-- smoke.lua: headless end-to-end test of the whole flow.
--
-- Press keypad 1 at the OS menu to launch netcat, then keypad = to accept the
-- compiled-in default devicespec and dial it. After that the client is just
-- receiving: the banner arrives, fills the pane and scrolls it. Two snapshots,
-- one early and one late, so a diff between them shows the pane moving rather
-- than merely filling.
--
-- Everything is scheduled in FRAMES. manager.machine.time.seconds is an
-- attotime's integer seconds field, so a fractional threshold compared against
-- it does not fire until the next whole second -- which silently turns a
-- 150 ms tap into a one-second hold, long enough to auto-repeat.
--
--   mame ... -autoboot_script emu/smoke.lua -video none -sound none \
--        -seconds_to_run 60 -snapshot_directory build
local FPS = 60

local function port_by_suffix(suffix)
    for tag, port in pairs(manager.machine.ioport.ports) do
        if tag:sub(-#suffix) == suffix then return port end
    end
    return nil
end

local function tap(name, field)
    local p = port_by_suffix(name)
    if p then p:field(field):set_value(1) end
end
local function untap(name, field)
    local p = port_by_suffix(name)
    if p then p:field(field):clear_value() end
end

local acts = {}
local function at(sec, fn) acts[#acts + 1] = {math.floor(sec * FPS), fn} end
local function press(sec, name, field)         -- ~8 frames: a single tap
    at(sec, function() tap(name, field) end)
    at(sec + 0.13, function() untap(name, field) end)
end

press(3.0, "KEYPAD3", 0x10)                    -- keypad 1: launch from the menu
press(8.0, "KEYPAD0", 0x20)                    -- keypad =: dial the default
at(25.0, function()
    emu.print_info("smoke.lua: snapshot (early)")
    manager.machine.video:snapshot()
end)
at(50.0, function()
    emu.print_info("smoke.lua: snapshot (late)")
    manager.machine.video:snapshot()
end)

table.sort(acts, function(a, b) return a[1] < b[1] end)

local i, frame = 1, 0
emu.register_frame(function()
    frame = frame + 1
    while i <= #acts and frame >= acts[i][1] do
        acts[i][2]()
        i = i + 1
    end
end)
