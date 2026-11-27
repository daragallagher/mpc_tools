# mpc_tools

Tools and extensions for Akai MPC standalone hardware.

## Controllers

Device scripts that let a MIDI controller drive the MPC. The MPC loads them by itself when the
controller is plugged in; nothing on the MPC is patched or modified.

| Controller | What it does | Tested on |
|---|---|---|
| [APC mini mk2](controllers/APC%20Mini%20mk2/) | 8x8 clip launcher for the clip matrix, with LEDs following clip state; track select; faders for track volume | MPC One+ Pro, MPC OS 3.10.1 |

## Tools

`tools/sign_scripts.py` re-signs a device script's `.ini` after you edit its `.lua`, using a
stock firmware image you supply. See [tools/README.md](tools/README.md).

## Credits

The method for locating the firmware checksum seed comes from **Eurikon**'s open-mpc plugin
manager ([plugin-manager-usb-for-open-mpc](https://github.com/Eurikon/plugin-manager-usb-for-open-mpc), MIT).

## Licence and disclaimer

MIT: see [LICENSE](LICENSE).

Not affiliated with or endorsed by Akai Professional or inMusic. Akai, MPC and APC are their
trademarks. Use at your own risk.
