# DK2 known-good recovery baseline

This directory preserves the exact application image physically verified on
2026-08-26 on Omi DevKit 2 serial `670AA14EED7750F3`.

- Source base: official `Omi_DK2_v2.0.10` tag (`b6ed65399e975915544120f1c7d485cebf781971`)
- UF2 SHA-256: `9ea68dd48d82d993a5311abae1089589b7ce87fc77ab2ba3d5c4feb5dac8795c`
- Flash range: `[0x27000, 0x74600)`; Adafruit bootloader and guard region untouched
- Physical result: normal startup rainbow, red waiting state, no actuator activity
- Radio result: active Windows scan found `Omi DevK` advertising service
  `19b10000-e8f2-537e-4f6c-d104768a1214`

The exact release UF2 did not reach BLE on this board after the SD reset. This
image uses the official release source with `prj_dk2_stock_recovery.conf` and
`overlay/dk2_stock_recovery.overlay`. Those files park the haptic and speaker
gates low, protect the bootloader/guard regions, and compile out optional
peripheral initialization that can abort before BLE startup.

The image was reproduced byte-for-byte from a pristine NCS 2.7.0 build with:

```sh
west build --pristine -b xiao_ble/nrf52840/sense omi/firmware/devkit \
  -d omi/firmware/build/dk2-recovery \
  -- \
  -DCONF_FILE="prj_xiao_ble_sense_devkitv2-adafruit.conf;prj_dk2_stock_recovery.conf" \
  -DDTC_OVERLAY_FILE="overlay/xiao_ble_sense_devkitv2-adafruit.overlay;overlay/dk2_stock_recovery.overlay"
```

Flash only through the stock `XIAO-SENSE` UF2 volume. Do not flash below
`0x27000`.
