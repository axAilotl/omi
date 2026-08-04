package com.friend.ios.ble

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BleGattConnectionModeTest {
    @Test
    fun directPresenceAttemptNeverParksInPassiveAutoConnect() {
        assertFalse(BleGattConnectionMode.DIRECT.autoConnect)
    }

    @Test
    fun backgroundRetryUsesLowPowerPassiveAutoConnect() {
        assertTrue(BleGattConnectionMode.PASSIVE.autoConnect)
    }
}
