#include <zephyr/bluetooth/conn.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>

#include "lib/core/button.h"
#include "lib/core/settings.h"
#include "lib/core/transport.h"

static void emit_connected_button_event(struct k_work *work)
{
    struct bt_conn *conn = get_current_connection();
    if (conn == NULL) {
        k_work_reschedule(k_work_delayable_from_work(work), K_MSEC(1));
        return;
    }

    bt_conn_unref(conn);
    button_notify(1);
    printk("OMI_BSIM_BUTTON_NOTIFIED\n");
}

K_WORK_DELAYABLE_DEFINE(button_event_work, emit_connected_button_event);

int main(void)
{
    int err = app_settings_init();
    if (err) {
        printk("OMI_BSIM_FAIL settings %d\n", err);
        return err;
    }

    err = transport_start();
    if (err) {
        printk("OMI_BSIM_FAIL transport %d\n", err);
        return err;
    }

    k_work_schedule(&button_event_work, K_NO_WAIT);
    printk("OMI_BSIM_READY\n");
    return 0;
}
