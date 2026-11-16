-----------------------------------------------------------------------------------------------
-- apcMiniMk2.lua: Akai APC mini mk2 as an 8x8 clip launcher for the MPC clip matrix.
--
-- LEDs are driven by MPC state (property listeners) not by button presses.
-- A press calls the MPC; the MPC changes clip state; the listener repaints the pad.
--
-- The 8x8 pads are a WINDOW onto the MPC clip matrix, which can be larger in both dimensions.
-- Shift + the four arrow buttons (track buttons 5-8) move that window around the whole matrix.
--
-- Surface (MIDI layout from Akai's protocol doc):
--   grid 8x8          notes 0-63, note = col + row*8, row 0 = BOTTOM  -> launch clip in window
--   scene buttons     notes 112-119, top to bottom                    -> launch scene (window row)
--   track buttons 1-8 notes 100-107, under columns 1-8                -> select that track; the
--                     current track's button is lit
--   shift             note 122
--     shift + track 5-8 (the arrows)                                  -> move the window by 1
--     shift + scene 8 (stop all clips)                                -> stop all clips
--     shift + pad                                                     -> select clip, no launch
--   faders 0-7       CC 48-55                                         -> volume of the track in
--                    that column
-----------------------------------------------------------------------------------------------

local deviceName = "apcMiniMk2"; -- must match the file name; the MPC exposes the table apcMiniMk2
local controlPortIndex = 0;      -- order of output= lines in apcMiniMk2.ini

local cols, rows = 8, 8;
local trackButtonBase, sceneButtonBase, shiftNote = 100, 112, 122;
local faderCCBase = 48;          -- faders 0-7 = CC 48-55 (master fader CC 56 not mapped)
local SCENE_STOP_ALL = 7;

-- With Shift, the four arrow buttons move the window. Keys are the track-button index (0-7, i.e.
-- note - trackButtonBase); the value is the direction. Notes 104-107 sit under columns 5-8 and
-- are printed up, down, left, right (checked on the hardware).
local CURSOR = { [4] = "up", [5] = "down", [6] = "left", [7] = "right" };

-- Lighting behaviour = MIDI channel of the pad note on.
local L = { solid = 6, pulse4th = 9, blink16th = 12, blink8th = 13 };
local BTN_OFF, BTN_ON, BTN_BLINK = 0, 1, 2;

-- Clip states (order confirmed by the stock MPK script and mpc-3-ce's Gen1 enum).
local S = { NoSlot = 0, Empty = 1, Ready = 2, WillPlay = 3, Playing = 4, WillStopPlaying = 5,
            WillRecord = 6, Recording = 7, WillStopRecording = 8,
            WillOverdub = 9, Overdubbing = 10, WillStopOverdubbing = 11 };

-- Palette indices (Akai's velocity-to-colour chart) for the fixed state colours.
local P = { black = 0, white = 3, red = 5, orange = 9, green = 21 };

-- The MPC's 27 track/clip colours -> palette index. Taken from Akai's own mpkMiniMkIV.lua
-- (velocityForColour), whose MPK mini IV uses the same 128-colour palette as the APC mini mk2:
-- Akai's hand-picked LED match for each MPC colour. Colours outside this set get the nearest
-- palette colour (nearestPaletteVelocity).
local mpcColourVelocity = {
  [0xFFFFFF] = 2,  [0x00FF00] = 87, [0xFF0000] = 5,  [0xFF6D17] = 96, [0xFF4400] = 60,
  [0xFF8800] = 84, [0xECEC24] = 12, [0xFFD500] = 13, [0xE6FF00] = 109, [0xA2FF00] = 73,
  [0x55FF00] = 75, [0x11FF00] = 88, [0x00FF33] = 29, [0x00FF80] = 33, [0x00FFC4] = 32,
  [0x00F7FF] = 90, [0x00AAFF] = 78, [0x0066FF] = 91, [0xA2A9AD] = 3,  [0x0022FF] = 41,
  [0x5200FF] = 45, [0x6F00FF] = 49, [0xB200FF] = 48, [0xFF00FF] = 53, [0xFF00BB] = 56,
  [0xFF0077] = 57, [0x29B574] = 77 };
local unknownColoursLogged = {};

-- The APC's palette: velocity -> RGB (Akai's protocol doc).
local palette = { [0] =
  0x000000, 0x1E1E1E, 0x7F7F7F, 0xFFFFFF, 0xFF4C4C, 0xFF0000, 0x590000, 0x190000,  -- 0-7
  0xFFBD6C, 0xFF5400, 0x591D00, 0x271B00, 0xFFFF4C, 0xFFFF00, 0x595900, 0x191900,  -- 8-15
  0x88FF4C, 0x54FF00, 0x1D5900, 0x142B00, 0x4CFF4C, 0x00FF00, 0x005900, 0x001900,  -- 16-23
  0x4CFF5E, 0x00FF19, 0x00590D, 0x001902, 0x4CFF88, 0x00FF55, 0x00591D, 0x001F12,  -- 24-31
  0x4CFFB7, 0x00FF99, 0x005935, 0x001912, 0x4CC3FF, 0x00A9FF, 0x004152, 0x001019,  -- 32-39
  0x4C88FF, 0x0055FF, 0x001D59, 0x000819, 0x4C4CFF, 0x0000FF, 0x000059, 0x000019,  -- 40-47
  0x874CFF, 0x5400FF, 0x190064, 0x0F0030, 0xFF4CFF, 0xFF00FF, 0x590059, 0x190019,  -- 48-55
  0xFF4C87, 0xFF0054, 0x59001D, 0x220013, 0xFF1500, 0x993500, 0x795100, 0x436400,  -- 56-63
  0x033900, 0x005735, 0x00547F, 0x0000FF, 0x00454F, 0x2500CC, 0x7F7F7F, 0x202020,  -- 64-71
  0xFF0000, 0xBDFF2D, 0xAFED06, 0x64FF09, 0x108B00, 0x00FF87, 0x00A9FF, 0x002AFF,  -- 72-79
  0x3F00FF, 0x7A00FF, 0xB21A7D, 0x402100, 0xFF4A00, 0x88E106, 0x72FF15, 0x00FF00,  -- 80-87
  0x3BFF26, 0x59FF71, 0x38FFCC, 0x5B8AFF, 0x3151C6, 0x877FE9, 0xD31DFF, 0xFF005D,  -- 88-95
  0xFF7F00, 0xB9B000, 0x90FF00, 0x835D07, 0x392B00, 0x144C10, 0x0D5038, 0x15152A,  -- 96-103
  0x16205A, 0x693C1C, 0xA8000A, 0xDE513D, 0xD86A1C, 0xFFE126, 0x9EE12F, 0x67B50F,  -- 104-111
  0x1E1E30, 0xDCFF6B, 0x80FFBD, 0x9A99FF, 0x8E66FF, 0x404040, 0x757575, 0xE0FFFF,  -- 112-119
  0xA00000, 0x350000, 0x1AD000, 0x074200, 0xB9B000, 0x3F3100, 0xB35F00, 0x4B1502,  -- 120-127
};
local nearestCache = {};

-- The palette colour closest in hue to an RGB colour (not 0). The colour is first scaled up so
-- its brightest component is FF: brightness isn't easily discernable on the pads, so dark palette
-- entries (brightest component below 0x50) are skipped.
-- Distance: squared component differences, weighted 2:4:3 for R:G:B.
local function nearestPaletteVelocity(rgb)
  if nearestCache[rgb] then return nearestCache[rgb]; end
  local r, g, b = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF;
  local top = math.max(r, g, b);
  r, g, b = r * 255 // top, g * 255 // top, b * 255 // top;
  local best, bestDistance = 3, nil;   -- white, if nothing qualifies
  for velocity = 1, 127 do
    local p = palette[velocity];
    local pr, pg, pb = (p >> 16) & 0xFF, (p >> 8) & 0xFF, p & 0xFF;
    if math.max(pr, pg, pb) >= 0x50 then
      local d = 2 * (r - pr) ^ 2 + 4 * (g - pg) ^ 2 + 3 * (b - pb) ^ 2;
      if bestDistance == nil or d < bestDistance then best, bestDistance = velocity, d; end
    end
  end
  nearestCache[rgb] = best;
  return best;
end

local sysexHeader = string.char(0x47, 0x7F, 0x4F);   -- Akai, device 7F, APC mini mk2
local introductionSysex = sysexHeader .. string.char(0x60, 0x00, 0x04, 0x00, 0x00, 0x02, 0x00);

local shiftHeld = false;
local loaded = false;    -- from a completed OnLoad set-up until teardown: listeners, mappings, Show

local ledCache = {};     -- note -> last LED command sent (a string key); only changes are sent

-----------------------------------------------------------------------------------------------
-- Utilities
-----------------------------------------------------------------------------------------------

-- On MPC hardware, print goes to the journal: journalctl -u acvs (timestamped there).
local function log(msg)
  pcall(function() print(deviceName .. ": " .. tostring(msg)); end);
end

-- pcall(fn), with a failure logged the first time only for each label. A call that doesn't work
-- on this MPC (e.g. one marked UNVERIFIED) then shows up once in the journal, and is otherwise
-- ignored. Returns what pcall returns.
local failuresLogged = {};
local function report(label, ok, ...)
  if not ok and not failuresLogged[label] then
    failuresLogged[label] = true;
    log(label .. " failed: " .. tostring((...)));
  end
  return ok, ...;
end
local function try(label, fn) return report(label, pcall(fn)); end

-- Palette LED: behaviour (channel) + palette colour (velocity). Also used for buttons (ch 0).
local function sendLed(note, channel, velocity)
  local key = channel .. ":" .. velocity;
  if ledCache[note] == key then return; end
  ledCache[note] = key;
  apcMiniMk2.midiOut.SendMIDINoteOn(channel, note, velocity, controlPortIndex);
end

-- Pad note <-> window position. APC rows count from the bottom; aperture rows from the top.
local function padNote(col, apertureRow) return col + (rows - 1 - apertureRow) * cols; end
local function padPosition(note) return note % cols, rows - 1 - note // cols; end

local function aperture() return apcMiniMk2.clipMatrixAperture; end

-- Every note and CC the script handles, on channel 0 (MIDI channel 1): OnLoad routes them to the
-- script, teardown routes them back.
local surfaceNotes, surfaceCCs = {}, {};
for note = 0, cols * rows - 1 do surfaceNotes[#surfaceNotes + 1] = note; end
for col = 0, cols - 1 do surfaceNotes[#surfaceNotes + 1] = trackButtonBase + col; end
for row = 0, rows - 1 do surfaceNotes[#surfaceNotes + 1] = sceneButtonBase + row; end
surfaceNotes[#surfaceNotes + 1] = shiftNote;
for fader = 0, cols - 1 do surfaceCCs[#surfaceCCs + 1] = faderCCBase + fader; end

local function routeSurface(toScript)
  local script = apcMiniMk2.mappings.script;
  for _, note in ipairs(surfaceNotes) do
    if toScript then script.AddNoteToScript(0, note); else script.RemoveNoteToScript(0, note); end
  end
  for _, cc in ipairs(surfaceCCs) do
    if toScript then script.AddCCToScript(0, cc); else script.RemoveCCToScript(0, cc); end
  end
end
local function clip(col, row) return aperture().clipProperties[col][row]; end

-----------------------------------------------------------------------------------------------
-- State -> LED
-----------------------------------------------------------------------------------------------

-- Returns channel (behaviour), velocity (palette colour) for one clip slot. Selection is not
-- shown: the MPC screen shows it but I found brightness levels to be too subtle to mark it on
-- the APC.
local function clipLed(state, argb)
  if state == S.NoSlot or state == S.Empty then
    return L.solid, P.black;
  elseif state == S.Ready then
    -- A ready clip must never look empty: with no colour (0) it shows white.
    local rgb = (argb or 0) & 0xFFFFFF;
    if rgb == 0 then return L.solid, P.white; end
    local velocity = mpcColourVelocity[rgb];
    if velocity then return L.solid, velocity; end
    velocity = nearestPaletteVelocity(rgb);
    if not unknownColoursLogged[rgb] then
      unknownColoursLogged[rgb] = true;
      log(string.format("clip colour %08X not in the MPC colour table: palette %d", argb, velocity));
    end
    return L.solid, velocity;
  elseif state == S.WillPlay then            return L.blink8th, P.green;
  elseif state == S.Playing then             return L.pulse4th, P.green;
  elseif state == S.WillStopPlaying then     return L.blink16th, P.green;
  elseif state == S.WillRecord then          return L.blink8th, P.red;
  elseif state == S.Recording then           return L.pulse4th, P.red;
  elseif state == S.WillStopRecording then   return L.blink16th, P.red;
  elseif state == S.WillOverdub then         return L.blink8th, P.orange;
  elseif state == S.Overdubbing then         return L.pulse4th, P.orange;
  elseif state == S.WillStopOverdubbing then return L.blink16th, P.orange;
  end
  return L.solid, P.black; -- unknown state: dark rather than wrong
end

local function updatePad(col, row)
  local c = clip(col, row);
  local channel, velocity = clipLed(c.State.value, c.Colour.value);
  sendLed(padNote(col, row), channel, velocity);
end

-- The window column of the MPC's current track, or nil when the current track is outside the
-- window or isn't a normal track. currentTrack.Index counts normal tracks first, then master
-- tracks (as the stock MPK script reads it); normal track i is clip-matrix column i.
local function currentTrackColumn()
  local ok, col = try("currentTrack.Index", function()
    local index = mpc.tracks.currentTrack.Index.value;
    if index >= mpc.tracks.normalTracks.Count.value then return nil; end
    return aperture().ToLocalColumn(index);
  end);
  if ok and col and col >= 0 then return col; end
  return nil;
end

-- Track button LEDs: the current track's button on, the others off.
local function updateTrackButtons()
  local current = currentTrackColumn();
  for col = 0, cols - 1 do
    sendLed(trackButtonBase + col, 0, col == current and BTN_ON or BTN_OFF);
  end
end

-- Scene button LED. sceneProperties[row].State uses the clip-state enum, and covers the whole
-- scene, including tracks outside the 8-column window.
local function updateSceneButton(row)
  local ok, s = try("sceneProperties.State", function() return aperture().sceneProperties[row].State.value; end);
  local led = BTN_OFF;
  if ok and s then
    if s == S.WillPlay or s == S.WillStopPlaying then led = BTN_BLINK;
    elseif s == S.Playing then led = BTN_ON; end
  end
  sendLed(sceneButtonBase + row, 0, led);
end

local function refreshAll()
  for col = 0, cols - 1 do
    for row = 0, rows - 1 do updatePad(col, row); end
  end
  updateTrackButtons();
  for row = 0, rows - 1 do updateSceneButton(row); end
end

-- Forget what the APC is believed to show and send every LED again.
local function repaintAll()
  ledCache = {};
  refreshAll();
end

-- Every pad one solid colour and every button the same: the start-up flash (white, or red with
-- no clip workflow) and the dark at unload.
local function fillAll(padColour, buttonLed)
  local out = apcMiniMk2.midiOut;
  for note = 0, cols * rows - 1 do out.SendMIDINoteOn(L.solid, note, padColour, controlPortIndex); end
  for col = 0, cols - 1 do out.SendMIDINoteOn(0, trackButtonBase + col, buttonLed, controlPortIndex); end
  for row = 0, rows - 1 do out.SendMIDINoteOn(0, sceneButtonBase + row, buttonLed, controlPortIndex); end
  ledCache = {};
end

-----------------------------------------------------------------------------------------------
-- Listeners: one per clip property and scene state. Re-registered on load only; moving the
-- aperture changes which global clips the same local properties refer to.
-----------------------------------------------------------------------------------------------

local function registerListeners()
  for col = 0, cols - 1 do
    for row = 0, rows - 1 do
      local c = clip(col, row);
      local function changed() updatePad(col, row); end
      c.State:listen(changed, deviceName);
      c.Colour:listen(changed, deviceName);
    end
  end
  for row = 0, rows - 1 do
    try("sceneProperties.State:listen", function()
      aperture().sceneProperties[row].State:listen(function() updateSceneButton(row); end, deviceName);
    end);
  end
  -- UNVERIFIED: currentTrack.Index as a listenable property. The stock MPK script listens to
  -- Name instead, which also changes with the current track (unless two tracks share a name).
  try("currentTrack.Index:listen", function() mpc.tracks.currentTrack.Index:listen(updateTrackButtons, deviceName); end);
  try("currentTrack.Name:listen", function() mpc.tracks.currentTrack.Name:listen(updateTrackButtons, deviceName); end);
  -- UNVERIFIED: OriginX/OriginY as listenable properties. The refresh after each move in page()
  -- covers the case where they are not listenable.
  try("OriginX:listen", function() aperture().OriginX:listen(refreshAll, deviceName); end);
  try("OriginY:listen", function() aperture().OriginY:listen(refreshAll, deviceName); end);
end

local function clearListeners()
  for col = 0, cols - 1 do
    for row = 0, rows - 1 do
      local c = clip(col, row);
      c.State:stopListening(deviceName);
      c.Colour:stopListening(deviceName);
    end
  end
  for row = 0, rows - 1 do
    try("sceneProperties.State:stopListening", function() aperture().sceneProperties[row].State:stopListening(deviceName); end);
  end
  try("currentTrack.Index:stopListening", function() mpc.tracks.currentTrack.Index:stopListening(deviceName); end);
  try("currentTrack.Name:stopListening", function() mpc.tracks.currentTrack.Name:stopListening(deviceName); end);
  try("OriginX:stopListening", function() aperture().OriginX:stopListening(deviceName); end);
  try("OriginY:stopListening", function() aperture().OriginY:stopListening(deviceName); end);
end

-----------------------------------------------------------------------------------------------
-- Faders -> track volume
-----------------------------------------------------------------------------------------------

-- The normal-track list is indexed like clip-matrix columns while ActiveMatrix is "Normal"
-- (the stock MPK script relies on the same correspondence). Returns nil past the last track.
local function trackForFader(fader)
  local global = aperture().ToGlobalColumn(fader);
  if global == nil or global < 0 or global >= mpc.tracks.normalTracks.Count.value then return nil; end
  return mpc.tracks.normalTracks[global];
end

-- The fader's position sets the track's volume.
local function handleFader(fader, value)
  local track = trackForFader(fader);
  if track then track.Volume.value = value / 127; end
end

-----------------------------------------------------------------------------------------------
-- Actions
-----------------------------------------------------------------------------------------------

-- Move the window by one row or column.  At the edge of the matrix they do nothing.
local function page(dir)
  local a = aperture();
  if dir == "left" then a.MoveLeft(1); elseif dir == "right" then a.MoveRight(1);
  elseif dir == "up" then a.MoveUp(1); elseif dir == "down" then a.MoveDown(1); end
  refreshAll();
end

local function handlePad(note)
  local col, row = padPosition(note);
  local a = aperture();
  a.SelectClip(col, row);         -- always, as the stock MPK script does, so edit views follow
  if not shiftHeld then a.TriggerClip(col, row); end   -- shift + pad: select only
end

local function handleTrackButton(idx)      -- idx 0-7 within the 8 track buttons
  if not shiftHeld then
    aperture().SelectTrack(idx);           -- plain: make it the MPC's current track
  elseif CURSOR[idx] then
    page(CURSOR[idx]);                     -- shift + arrow: move the window by 1
  end                                      -- shift + track 1-4: nothing
end

local function handleSceneButton(row)
  if shiftHeld then
    if row == SCENE_STOP_ALL then mpc.clipMatrix.StopAllClips(); end
  else
    aperture().TriggerRow(row);
  end
end

-----------------------------------------------------------------------------------------------
-- MPC entry points
-----------------------------------------------------------------------------------------------

function apcMiniMk2.HandleMIDINoteOn(channel, note, velocity)
  if velocity == 0 then return apcMiniMk2.HandleMIDINoteOff(channel, note, velocity); end
  if note == shiftNote then shiftHeld = true;
  elseif note < cols * rows then handlePad(note);
  elseif note >= trackButtonBase and note < trackButtonBase + cols then handleTrackButton(note - trackButtonBase);
  elseif note >= sceneButtonBase and note < sceneButtonBase + rows then handleSceneButton(note - sceneButtonBase);
  end
end

-- Shift + drum/note on the APC changes its mode, and going back to Session mode leaves the pads
-- dark; this is the only sign of it the script gets.
function apcMiniMk2.HandleMIDINoteOff(channel, note, velocity)
  if note == shiftNote then
    shiftHeld = false;
    repaintAll();
  end
end

function apcMiniMk2.HandleMIDICC(channel, cc, value)
  if cc >= faderCCBase and cc < faderCCBase + cols then handleFader(cc - faderCCBase, value); end
end

-- One-shot, shortly after load: the first messages after a USB MIDI port opens can be lost, so
-- introduce and repaint again once the port has settled.
local settleDelayMs = 1000;  -- also how long the start-up flash stays visible

local function stopTimer() try("timer.Stop", function() apcMiniMk2.timer.Stop(); end); end

-- The introduction goes first. If a listener sent an LED note just before this, the two could be
-- packed together and the APC would ignore this copy; the one sent at OnLoad still stands.
function apcMiniMk2.HandleTimer()
  stopTimer();
  apcMiniMk2.midiOut.SendMIDISysex(introductionSysex, controlPortIndex);
  repaintAll();
end

-- Undo what OnLoad set up after the clip-workflow check. Only runs if that set-up happened:
-- without the clip workflow, the clip properties may not exist at all.
local function teardown()
  if not loaded then return; end
  loaded = false;
  clearListeners();
  routeSurface(false);
  try("clipMatrixAperture.Hide", function() aperture().Hide(); end);
end

function apcMiniMk2.OnLoad()
  -- Loading again without an unload in between starts from scratch.
  stopTimer();
  teardown();

  -- Introduction first.
  apcMiniMk2.midiOut.SendMIDISysex(introductionSysex, controlPortIndex);
  -- Start-up signal: all pads white for settleDelayMs, then the real clip state (HandleTimer).
  fillAll(P.white, BTN_ON);

  local ok, clipWorkflow = try("mpc.features.UseClipWorkflow", function() return mpc.features.UseClipWorkflow.value; end);
  if not ok or not clipWorkflow then
    fillAll(P.red, BTN_ON);   -- red pads = loaded, but no clip matrix to show
    if ok then log("clip workflow not available on this MPC"); end
    return;
  end

  shiftHeld = false;
  loaded = true;

  local a = aperture();
  a.SetColumns(cols);
  a.SetRows(rows);
  a.SetFollowsTUI(false);
  a.SetFollowsTUIActiveMatrix(false);
  a.ActiveMatrix.value = "Normal";
  a.SetLabel("APC mini mk2");
  a.MoveToColumn(0);
  a.MoveToRow(0);
  try("clipMatrixAperture.Show", function() a.Show(); end);

  routeSurface(true);

  registerListeners();
  -- The first real paint happens in HandleTimer, after the white flash. If the timer cannot be
  -- started, paint now instead so the pads still show the clip state.
  if not try("timer.Start", function() apcMiniMk2.timer.Start(settleDelayMs); end) then repaintAll(); end
  log("ready");
end

function apcMiniMk2.OnUnload()
  stopTimer();
  teardown();      -- listeners first, so nothing repaints after the LEDs go dark
  fillAll(P.black, BTN_OFF);
end

-- Runs when the MPC reads this file, before any APC is attached: proves the file was found and
-- accepted (folder location and checksum are right), independently of the port-name match.
log("script file loaded");
