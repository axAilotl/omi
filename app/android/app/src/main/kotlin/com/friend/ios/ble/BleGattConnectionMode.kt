package com.friend.ios.ble

/**
 * Selects how Android opens the next GATT session.
 *
 * A presence/foreground signal means the peripheral is known to be nearby, so
 * a direct connection is required. Passive auto-connect is reserved for
 * background retries where waiting for the next advertisement is intentional.
 */
internal enum class BleGattConnectionMode(val autoConnect: Boolean) {
    DIRECT(autoConnect = false),
    PASSIVE(autoConnect = true),
}
