-- compose.lua: drive the grid keyboard end to end, against emu/echosrv.py.
--
-- Launch, dial, open the composer with the trigger, pick A B C off the grid,
-- send with keypad =, and snapshot at each step. Proves the overlay draws, the
-- character shadow puts the covered terminal rows back, and NET_WRITE reaches
-- the far end (the server logs the line it received, and echoes it).
--
--   ENDPOINT=N:TCP://127.0.0.1:4242/ ./build.sh && make echotest
--
-- Frame-scheduled: machine.time.seconds is an attotime's INTEGER seconds
-- field, so a fractional threshold does not fire until the next whole second,
-- which would turn every tap into a one-second hold and auto-repeat it.
local function P(s) for tag,p in pairs(manager.machine.ioport.ports) do
  if tag:sub(-#s)==s then return p end end return nil end
local function tap(n,f) local p=P(n); if p then p:field(f):set_value(1) end end
local function untap(n,f) local p=P(n); if p then p:field(f):clear_value() end end
local JOY,TRIG,RIGHT="ctrl1:joy:HANDLE",0x10,0x08
local FPS=60
local acts={}
local function at(sec,fn) acts[#acts+1]={math.floor(sec*FPS),fn} end
local function press(sec,port,bit)
  at(sec,      function() tap(port,bit) end)
  at(sec+0.13, function() untap(port,bit) end)   -- ~8 frames: a single tap
end
press(3.0,"KEYPAD3",0x10)                  -- keypad 1: launch
press(8.0,"KEYPAD0",0x20)                  -- '=': dial
press(18.0,JOY,TRIG)                       -- open the composer
at(19.5,function() emu.print_info("kb: OVERLAY"); manager.machine.video:snapshot() end)
press(21.0,JOY,TRIG)                       -- 'A' (cursor starts there)
press(22.0,JOY,RIGHT)
press(23.0,JOY,TRIG)                       -- 'B'
press(24.0,JOY,RIGHT)
press(25.0,JOY,TRIG)                       -- 'C'
at(26.0,function() emu.print_info("kb: TYPED"); manager.machine.video:snapshot() end)
press(27.0,"KEYPAD0",0x20)                 -- '=': send the line
at(30.0,function() emu.print_info("kb: RESTORED"); manager.machine.video:snapshot() end)
table.sort(acts,function(a,b) return a[1]<b[1] end)
local i,f=1,0
emu.register_frame(function()
  f=f+1
  while i<=#acts and f>=acts[i][1] do acts[i][2](); i=i+1 end
end)
