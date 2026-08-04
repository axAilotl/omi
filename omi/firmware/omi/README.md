# OMI Firmware

The firmware for the OMI consumer version.

## Install

Use https://docs.omi.me/doc/developer/firmware/Compile_firmware as the reference with these specifications.

Note: Open "firmware" folder in your code editor. Don't open the root omi folder (otherwise West wouldn't recognize the project and won't find your board)

- NCS: 2.9.0
- Application: omi
- Board: omi/nrf5340/cpuapp — you can also use the [CMakePresets.json](CMakePresets.json).

 <img width="463" alt="Screenshot 2025-04-20 at 12 48 04" src="https://github.com/user-attachments/assets/5fc17e99-9cdd-4b2a-a438-fc4c6ffed498" />

 <img width="986" alt="Screenshot 2025-04-20 at 12 48 49" src="https://github.com/user-attachments/assets/ccce238d-fa4b-4cbc-af7c-fc7688569b95" />

## CV1 power and reset behavior

- Historical CV1 firmware armed the active-low center button as a level-low
  system-off wake source while the long shutdown press could still be held.
  The same press could therefore wake the application core immediately after
  `sys_poweroff()`. The release fence below closes that inherited race. No
  matching public issue or regression test existed when it was reproduced.
- Hold the center button for 3 seconds to request a graceful power-off. The
  firmware preserves audio first and may cancel power-off if an SD/audio
  durability gate cannot complete safely.
- Release the button after the normal shutdown feedback. Firmware waits for
  release before arming that same active-low button as the wake source, which
  prevents an immediate wake from looking like the device turned itself on.
- If graceful shutdown returns to a red state, start a new continuous
  30-second hold to request a one-shot cold reboot. If the original hold is
  still in progress, keep holding through 30 seconds. The emergency timer uses
  system uptime, so time spent waiting for storage teardown does not restart it.
- If firmware is not servicing the button, remove the pendant from the powered
  magnetic charger, hold the center button, and place it back on the charger
  while continuing to hold. Release after about 2 seconds. The mainboard force
  reset circuit detects charger insertion while the button is already held.
- The two RGB packages beside the center switch share the same three LED nets.
  Seeing both emit the same color is expected and is not a two-code fault
  indication.

The charger-button action resets the MCU; it is not a factory reset. Do not
short test pads, battery contacts, or the FPC connector as a substitute.

## WIP

- Status: running on production, missing some enhancement.

- TODOs:
  - [x] Testing new modules in the omi device (7/9)
    - [x] Mic
    - [x] BLE
    - [x] Buttons
    - [x] LEDs
    - [ ] Wi-Fi, partially
    - [x] Motors
    - [x] Qspi flash
    - [ ] IMU
    - [x] Sd Card
  - [x] Add support for MCUBoot
    - [x] Add basic MCUBoot
    - [x] Test with the OMI app (iOS/Android)
    - [x] Test with an on-battery device (without charger)
  - [x] Initialize project, basic main loop with tests and devkit firmware as libs
  - [x] Streaming and transcribing
    - [x] Mic
      - [x] Capturing audio bytes
      - [x] Activating the 2nd mic
    - [x] BLE
    - [x] Encoding (OPUS) and transmitting
    - [x] Fix the audio byte loss issue - currently about 30% https://github.com/BasedHardware/omi/pull/2217#issuecomment-2815077148
      - [x] android, fixed by increasing the BLE connection interval (7ms) - but tbh i don't think this is a good solution since our devkit work fine without tuning the connection interval. 100 rps, 50 bytes each is not a big deal! https://github.com/BasedHardware/omi/pull/2248#issuecomment-2820156590
      - [x] iOS, they doesn't allow increasing the connection interval(CI). the feasible CI on iOS is about 15ms.
  - [x] LEDs
    - [x] Charging
    - [x] BLE connected
    - [x] BLE disconnected
    - [x] Fix the issue: The led during charging + device off ~ green only, does not provide correct feedback. charging still works.
  - [x] Buttons
    - [x] Turn the device on/off(entering the deepsleep mode)
    - [x] Long press to chat with omi
    - [x] Test the deepsleep mode's battery draining.
  - [x] SD Card (2/3)
    - [x] Store files
    - [x] Transfer via BLE
    - [ ] Transfer via Wi-Fi
  - [x] Haptic
    - [x] Haptic on turning on/off
    - [x] Long press to chat with omi
    - [x] Recheck the mass production version, since the current motor is not good https://github.com/BasedHardware/omi/pull/2281#issuecomment-2841105447
  - [x] Battery (1/2)
    - [x] Percentage feedbacks via BLE
    - [ ] Fix in-accurated battery level, especially on charging
  - [x] Charger
