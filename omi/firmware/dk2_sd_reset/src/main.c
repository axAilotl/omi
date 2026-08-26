/* SPDX-License-Identifier: Apache-2.0 */

#include <errno.h>
#include <string.h>

#include <ff.h>
#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/fs/fs.h>
#include <zephyr/kernel.h>
#include <zephyr/storage/disk_access.h>
#include <zephyr/sys/printk.h>

#define DISK_NAME CONFIG_SDMMC_VOLUME_NAME
#define MOUNT_POINT "/" DISK_NAME ":"
#define CISSA_DIR MOUNT_POINT "/CISSA"
#define MARKER_PATH CISSA_DIR "/RESERVED.V1"

static const char marker[] = "CISSA-SD-RESERVATION-V1\n";
#define MARKER_SIZE (sizeof(marker) - 1U)
#define MKFS_WORK_SIZE 4096U

static uint8_t mkfs_work[MKFS_WORK_SIZE] __aligned(4);
static uint32_t card_sector_count;
static FRESULT mkfs_result = FR_OK;
static unsigned int mkfs_attempts;
static bool recovered_mkfs_error;

static const struct gpio_dt_spec red_led = GPIO_DT_SPEC_GET(DT_ALIAS(led0), gpios);
static const struct gpio_dt_spec green_led = GPIO_DT_SPEC_GET(DT_ALIAS(led1), gpios);
static const struct gpio_dt_spec blue_led = GPIO_DT_SPEC_GET(DT_ALIAS(led2), gpios);
static const struct device *const console = DEVICE_DT_GET(DT_CHOSEN(zephyr_console));

static FATFS fat_fs;
static struct fs_mount_t mount = {
	.type = FS_FATFS,
	.fs_data = &fat_fs,
	.mnt_point = MOUNT_POINT,
};

static void set_leds(bool red, bool green, bool blue)
{
	gpio_pin_set_dt(&red_led, red);
	gpio_pin_set_dt(&green_led, green);
	gpio_pin_set_dt(&blue_led, blue);
}

static int init_leds(void)
{
	int rc;

	if (!gpio_is_ready_dt(&red_led) || !gpio_is_ready_dt(&green_led) ||
	    !gpio_is_ready_dt(&blue_led)) {
		return -ENODEV;
	}

	rc = gpio_pin_configure_dt(&red_led, GPIO_OUTPUT_INACTIVE);
	if (rc != 0) {
		return rc;
	}
	rc = gpio_pin_configure_dt(&green_led, GPIO_OUTPUT_INACTIVE);
	if (rc != 0) {
		return rc;
	}
	return gpio_pin_configure_dt(&blue_led, GPIO_OUTPUT_INACTIVE);
}

static void wait_for_console(void)
{
	uint32_t dtr = 0;

	while (!device_is_ready(console)) {
		k_sleep(K_MSEC(50));
	}
	while (uart_line_ctrl_get(console, UART_LINE_CTRL_DTR, &dtr) != 0 || dtr == 0) {
		k_sleep(K_MSEC(50));
	}
}

static int mkfs_errno(FRESULT result)
{
	switch (result) {
	case FR_OK:
		return 0;
	case FR_WRITE_PROTECTED:
		return -EROFS;
	case FR_NOT_ENOUGH_CORE:
		return -ENOMEM;
	case FR_INVALID_PARAMETER:
		return -EINVAL;
	default:
		return -EIO;
	}
}

static int provision_card(const char **failed_stage)
{
	static MKFS_PARM fat32_cfg = {
		.fmt = FM_FAT32 | FM_SFD,
		.n_fat = 1,
		.align = 1,
		.n_root = 512,
		.au_size = 32768,
	};
	static const uint8_t blank_sector[512];
	static uint8_t verify_sector[512];
	char verify[sizeof(marker)] = {0};
	struct fs_file_t file;
	ssize_t io_rc;
	uint32_t sector_size = 0;
	int rc;

	*failed_stage = "disk_init";
	for (int attempt = 0; attempt < 3; ++attempt) {
		rc = disk_access_init(DISK_NAME);
		if (rc == 0) {
			break;
		}
		k_sleep(K_MSEC(250));
	}
	if (rc != 0) {
		return rc;
	}

	*failed_stage = "disk_status";
	rc = disk_access_status(DISK_NAME);
	if (rc != DISK_STATUS_OK) {
		return rc == 0 ? -EIO : rc;
	}

	*failed_stage = "sector_size";
	rc = disk_access_ioctl(DISK_NAME, DISK_IOCTL_GET_SECTOR_SIZE, &sector_size);
	if (rc != 0) {
		return rc;
	}
	if (sector_size != sizeof(blank_sector)) {
		return -ENOTSUP;
	}
	*failed_stage = "sector_count";
	rc = disk_access_ioctl(DISK_NAME, DISK_IOCTL_GET_SECTOR_COUNT,
			       &card_sector_count);
	if (rc != 0 || card_sector_count < 128U) {
		return rc != 0 ? rc : -ENOSPC;
	}

	/* Destroy and verify sector zero before asking FatFs to format. */
	*failed_stage = "raw_write";
	rc = disk_access_write(DISK_NAME, blank_sector, 0, 1);
	if (rc != 0) {
		return rc;
	}
	*failed_stage = "raw_sync";
	rc = disk_access_ioctl(DISK_NAME, DISK_IOCTL_CTRL_SYNC, NULL);
	if (rc != 0) {
		return rc;
	}
	*failed_stage = "raw_read";
	rc = disk_access_read(DISK_NAME, verify_sector, 0, 1);
	if (rc != 0) {
		return rc;
	}
	if (memcmp(blank_sector, verify_sector, sizeof(blank_sector)) != 0) {
		*failed_stage = "raw_compare";
		return -EIO;
	}

	/* Zephyr's fs_mkfs wrapper gives FatFs one 512-byte work sector, forcing
	 * thousands of individual SPI writes on a large card. Use an aligned
	 * eight-sector buffer so FatFs emits bounded multi-block transfers. */
	*failed_stage = "mkfs";
	for (mkfs_attempts = 1U; mkfs_attempts <= 3U; ++mkfs_attempts) {
		mkfs_result = f_mkfs(DISK_NAME ":", &fat32_cfg, mkfs_work,
				     sizeof(mkfs_work));
		if (mkfs_result == FR_OK) {
			break;
		}
		if (mkfs_result != FR_DISK_ERR) {
			return mkfs_errno(mkfs_result);
		}
		k_sleep(K_SECONDS(1));
		*failed_stage = "mkfs_retry_sync";
		rc = disk_access_ioctl(DISK_NAME, DISK_IOCTL_CTRL_SYNC, NULL);
		if (rc != 0) {
			return rc;
		}
		*failed_stage = "mkfs";
	}
	if (mkfs_attempts > 3U) {
		mkfs_attempts = 3U;
	}
	if (mkfs_result != FR_OK) {
		/* A final sync error is provisional. Mount, marker readback, and
		 * unmount below remain mandatory before success can be reported. */
		recovered_mkfs_error = true;
	}

	*failed_stage = "mount";
	rc = fs_mount(&mount);
	if (rc != 0) {
		return rc;
	}

	*failed_stage = "reservation_dir";
	rc = fs_mkdir(CISSA_DIR);
	if (rc != 0 && rc != -EEXIST) {
		goto out_unmount;
	}

	fs_file_t_init(&file);
	*failed_stage = "marker_open_write";
	rc = fs_open(&file, MARKER_PATH, FS_O_CREATE | FS_O_WRITE);
	if (rc != 0) {
		goto out_unmount;
	}

	*failed_stage = "marker_write";
	io_rc = fs_write(&file, marker, MARKER_SIZE);
	if (io_rc != MARKER_SIZE) {
		rc = io_rc < 0 ? (int)io_rc : -EIO;
		fs_close(&file);
		goto out_unmount;
	}

	*failed_stage = "marker_sync";
	rc = fs_sync(&file);
	if (rc != 0) {
		fs_close(&file);
		goto out_unmount;
	}
	rc = fs_close(&file);
	if (rc != 0) {
		*failed_stage = "marker_close_write";
		goto out_unmount;
	}

	fs_file_t_init(&file);
	*failed_stage = "marker_open_read";
	rc = fs_open(&file, MARKER_PATH, FS_O_READ);
	if (rc != 0) {
		goto out_unmount;
	}

	*failed_stage = "marker_read";
	io_rc = fs_read(&file, verify, sizeof(verify));
	if (io_rc != MARKER_SIZE || memcmp(verify, marker, MARKER_SIZE) != 0) {
		rc = io_rc < 0 ? (int)io_rc : -EIO;
		fs_close(&file);
		goto out_unmount;
	}

	rc = fs_close(&file);
	if (rc != 0) {
		*failed_stage = "marker_close_read";
		goto out_unmount;
	}

	*failed_stage = "unmount";
	rc = fs_unmount(&mount);
	return rc;

out_unmount:
	fs_unmount(&mount);
	return rc;
}

int main(void)
{
	const char *failed_stage = "led_init";
	int rc;

	rc = init_leds();
	if (rc == 0) {
		set_leds(false, false, true);
		k_sleep(K_MSEC(300));
	}

	if (rc == 0) {
		rc = provision_card(&failed_stage);
	}

	if (rc == 0) {
		set_leds(false, true, false);
	} else {
		set_leds(true, false, false);
	}

	wait_for_console();
	if (rc == 0) {
		printk("PROVISION_OK marker=%s bytes=%u verified=1 sectors=%u "
		       "mkfs_result=%d attempts=%u recovered=%u\r\n",
		       MARKER_PATH, (unsigned int)MARKER_SIZE,
		       card_sector_count, (int)mkfs_result, mkfs_attempts,
		       recovered_mkfs_error ? 1U : 0U);
	} else {
		printk("PROVISION_FAIL stage=%s errno=%d sectors=%u "
		       "mkfs_result=%d attempts=%u\r\n",
		       failed_stage, rc, card_sector_count, (int)mkfs_result,
		       mkfs_attempts);
	}

	for (;;) {
		k_sleep(K_FOREVER);
	}
	return 0;
}
