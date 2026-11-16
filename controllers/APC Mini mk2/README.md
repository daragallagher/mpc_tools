# APC mini mk2 clip launcher for MPC

Use an **Akai APC mini mk2** as an 8x8 clip launcher for the clip matrix on a standalone **Akai
MPC**. The pads launch clips and light up to show what each clip is doing, the track buttons
select tracks, and the faders set track volumes.

It's a device script: a small Lua file that the MPC loads by itself when the APC is plugged in.
Nothing on the MPC is patched or modified.

## Requirements

- An MPC standalone running **MPC OS 3.10.1**. Tested on an MPC One+ Pro. Other Gen2 MPCs on
  3.10.1 should work but haven't been tested, and other MPC OS versions may not load the script.
- The **clip workflow** (the clip matrix), which needs the **MPC 3 Pro Pack**.
- An **APC mini mk2** (not the original APC mini), plugged into the MPC's USB host port.
- A computer on the same network as the MPC, with `ssh` and `scp`

## Install

1. **Download** the `mpc_tools` repository (**Code → Download ZIP**) and unzip it, or clone it.
   The script is the two files next to this README, in `controllers/APC Mini mk2/`:
   `apcMiniMk2.ini` and `apcMiniMk2.lua`. Don't edit them: the MPC won't load a script that has
   been changed (see [Changing the script](#changing-the-script)).
2. **Turn on SSH on the MPC:**
   - Menu → Preferences → Enhancements: turn on **Enable Enhancements**, then the **Developer**
     panel.
   - Hold **SHIFT + MENU** and choose **Developer**. This starts an SSH server with the login
     `root` and **no password**: only do this on a network you trust, and turn it off again when
     you're done.
   - Note the MPC's IP address, under Preferences → Wi-Fi (or Ethernet).
3. **Copy the two files** to the MPC. On your computer, in the `controllers/APC Mini mk2`
   folder, run these, replacing `<ip>` with the MPC's IP address:

   ```
   ssh root@<ip> 'mkdir -p "/storage/MPC Documents/Devices/APC mini mk2"'
   scp apcMiniMk2.ini apcMiniMk2.lua "root@<ip>:/storage/MPC Documents/Devices/APC mini mk2/"
   ```

   The files must end up in `MPC Documents/Devices/APC mini mk2/`.
4. **Restart the MPC.** Scripts are loaded when the MPC starts.
5. **Plug in the APC.** All pads light white for a second, then show the clip matrix.

## Controls

The 8x8 pads are a window onto the MPC's clip matrix, which can be larger. Each pad is one clip
slot, each row one scene, and each column one track.

| Control | Press | With Shift held |
|---|---|---|
| Pad | Select and launch that clip. On an empty slot: stop that track | Select the clip without launching it |
| Scene buttons (right) | Launch that row (scene) | Bottom button (*stop all clips*): stop all clips |
| Track buttons (bottom) | Select that track | Buttons 5-8 (▲ ▼ ◀ ▶): move the window by one row or column |
| Faders 1-8 | Volume of the track in that column | |

- **Stopping a track:** press an empty pad in its column, as you would tap an empty slot on the
  touch screen.
- **Moving around:** Shift + the arrow buttons. The APC's window moves on its own; scrolling the
  clip matrix on the MPC's screen doesn't move it.
- The labels printed on the track buttons (volume, pan, send, device) and on scene buttons 1-5
  (clip stop, solo, mute, rec arm, select) are for Ableton Live and aren't used. The master
  fader isn't used.

## Lights

| Pad | Meaning |
|---|---|
| Dark | Empty slot |
| Solid, in the clip's colour | Clip ready (white if it has no colour) |
| Blinking green | Queued to play |
| Pulsing green | Playing |
| Fast-blinking green | Queued to stop |
| Blinking, then pulsing red | Recording (queued, then running) |
| Pulsing orange | Overdubbing |

- **Track buttons:** the selected track's button is lit. None is lit when the selected track is
  outside the window or is a master track.
- **Scene buttons:** lit while that scene plays, blinking while it's queued or stopping.
- Clip colours are shown with the APC's nearest colour, so some look slightly different from the
  MPC's screen.

## Troubleshooting

- **Nothing lights up when the APC is plugged in.** Check that both files are in
  `MPC Documents/Devices/APC mini mk2/`, that they haven't been edited, and that the MPC was
  restarted after copying. Check the MPC OS version (Requirements).
- **All pads are red.** The script is running, but the clip workflow isn't available: it needs
  the MPC 3 Pro Pack.
- **The pads went dark and don't launch clips.** Shift + *drum* or Shift + *note* (scene buttons
  6 and 7) switch the APC into its own drum or note mode. Press the same combination again to
  return; the pads light up again when you let go of Shift.
- **Logs**, for the curious: with SSH on, `ssh root@<ip> journalctl -u acvs | grep apcMiniMk2`.
  A normal start shows `script file loaded` and `ready`.

## Changing the script

The MPC only loads a script if its `.ini` contains the right checksum: a hash of the `.lua`
file combined with a value hidden in the MPC's firmware. Any change to `apcMiniMk2.lua`, even
to a comment, needs a new checksum in `apcMiniMk2.ini`. I haven't included a tool to compute
it, because I'm not sure about the legality of publishing one.

## Uninstall

Delete the folder and restart the MPC:

```
ssh root@<ip> 'rm -r "/storage/MPC Documents/Devices/APC mini mk2"'
```

## Licence and disclaimer

MIT: see [LICENSE](../../LICENSE).

