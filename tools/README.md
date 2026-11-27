# tools

## sign_scripts.py

The MPC loads a device script only if its `.ini` carries a `checksum=` that matches the `.lua`.
The checksum is `sha256(<lua bytes> + <seed>)`, where the 36-byte seed is baked, obfuscated,
into the MPC program. So any edit to a `.lua` (even a comment) needs its `.ini` re-signed.

`sign_scripts.py` reads the seed from a **stock MPC OS 3.10.1 Gen2 firmware image you supply**
and writes a signed `.ini` for each device folder. The seed is never written to disk.

### Requirements

- Python 3.10+ (standard library only).
- `7zz` (the 7-Zip CLI), to read the image's root filesystem.  On macOS: use "brew install sevenzip". On
   Debian/Ubuntu:  "apt install 7zip".
- A legally obtained MPC OS 3.10.1 Gen2 firmware image (`MPC-3.10.1-Gen2-update.img`).

### Use

A device folder holds `device.ini` (every field except `checksum=`) and the `<script>.lua` that
its `script=` line names. For example, `controllers/APC Mini mk2/`:

```
python3 tools/sign_scripts.py --img MPC-3.10.1-Gen2-update.img "controllers/APC Mini mk2"
```

This writes `<script>.ini` (the template plus `checksum=`) beside the `.lua`. Copy that
`<script>.ini` and `<script>.lua` into `<MPC Documents>/Devices/<any folder>/` on the MPC.

### Credit

The method for locating the seed in the firmware comes from **Eurikon**'s open-mpc plugin
manager (<https://github.com/Eurikon/plugin-manager-usb-for-open-mpc>, MIT). The seed itself is
decoded from Akai's firmware; this tool holds only its offset, XOR key and sha256, not the seed.

### Note

The seed lives inside Akai's proprietary firmware, and this tool decodes it to get past the
MPC's own check on which scripts it will load. Use it only with firmware you obtained legally,
and only on your own device.
