# DK2 Cissa SD reservation provisioner

This directory preserves the exact one-shot application image used to prepare
an Omi DevKit 2 microSD card for the Cissa storage-first runtime.

**This image is destructive.** It erases the card, formats one FAT32 volume,
creates `/CISSA/RESERVED.V1` containing exactly the 24 bytes
`CISSA-SD-RESERVATION-V1\n`, reads the marker back, unmounts the filesystem,
and stops.

The provisioner gives FatFs an aligned 4096-byte work buffer so formatting uses
bounded multi-block transfers instead of thousands of individual 512-byte SPI
transactions. It retries only a FatFs disk error, with a successful raw sync
required between attempts. A final format error remains provisional: successful
mount, exact marker readback, and clean unmount are still mandatory before the
image shows green.

- Source: `omi/firmware/dk2_sd_reset/`
- UF2 SHA-256: `f0e401aef3bfe0dfdab0c5fe916ef519cdbfa81ad4f956100ee1ea50c619fb06`
- Flash range: `[0x27000, 0x37c00)`; Adafruit bootloader and guard region untouched
- microSD: P0.19 power enable, SPI2 on P1.13/P1.15/P1.14, P0.2 chip select,
  4 MHz maximum clock
- Safety gates: haptic P1.11 and speaker amplifier P0.4 held low by GPIO hogs
- Status: blue while provisioning, green only after verified readback and clean
  unmount, red on failure

It was built from a pristine NCS 2.9 workspace with Zephyr SDK 0.17.0:

```sh
env ZEPHYR_BASE=/home/ada/ncs/zephyr \
    ZEPHYR_TOOLCHAIN_VARIANT=zephyr \
    ZEPHYR_SDK_INSTALL_DIR=/home/ada/ncs/zephyr-sdk-0.17.0 \
  west build --pristine --no-sysbuild \
    -b xiao_ble/nrf52840/sense \
    -d omi/firmware/build/dk2-sd-provision \
    omi/firmware/dk2_sd_reset
```

Flash only through the stock `XIAO-SENSE` UF2 volume. Do not flash below
`0x27000`. After a green result, replace this one-shot image with the product
firmware; the provisioner deliberately does not advertise Bluetooth or record
audio.
