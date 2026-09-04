-- resettest.lua: console-RESET continuity.
--
-- Launch, dial, run a while, soft-reset the console, then relaunch and dial
-- again. The FUJINET_DEBUG transaction log must show the sequence numbers
-- CONTINUING across the reset rather than restarting at 1: the client derives
-- SEQ from the cart's persisted ACKSEQ, never from a local counter, because a
-- console reset restarts this program but not the cartridge.
--
-- The autoboot script re-runs after a soft reset, so timing is relative to
-- this run's start and only the first run pulls the reset.
--
--   FUJINET_DEBUG=1 mame ... -autoboot_script emu/resettest.lua \
--       -video none -sound none -seconds_to_run 40
--
-- Frames, not seconds: machine.time.seconds is an attotime's integer seconds
-- field, so fractional thresholds do not fire until the next whole second.
local FPS = 60

local function pbs(s)
    for tag, port in pairs(manager.machine.ioport.ports) do
        if tag:sub(-#s) == s then return port end
    end
end

local base = manager.machine.time.seconds
local first = base < 1

local acts = {}
local function at(sec, fn) acts[#acts + 1] = {math.floor(sec * FPS), fn} end
local function press(sec, name, field)
    at(sec, function() pbs(name):field(field):set_value(1) end)
    at(sec + 0.13, function() pbs(name):field(field):clear_value() end)
end

press(3.0, "KEYPAD3", 0x10)              -- keypad 1: launch
press(8.0, "KEYPAD0", 0x20)              -- keypad =: dial the default
at(16.0, function()
    if first then
        emu.print_info("resettest: SOFT RESET")
        manager.machine:soft_reset()
    end
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
