// SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: GPL-2.0-only
/*
 * Fake battery power_supply driver (out-of-tree)
 *
 * Creates: /sys/class/power_supply/fake-battery
 *
 * Writable attributes (via echo <value> > file):
 *   capacity (0..100)
 *   status (enum int)
 *   voltage_now (microvolts)
 *   current_now (microamps)
 *   charge_now (microamp-hours)
 *   charge_full (microamp-hours)
 *   temp (decidegree Celsius, e.g. 300 = 30.0C)
 *   health (enum int)
 *
 * Read-only examples:
 *   manufacturer
 *   model_name
 *   serial_number
 *   technology
 *   present
 *   type
 *
 * NOTE: Only integer-based standard properties are made writable. The generic
 * power_supply sysfs store helpers expect integer conversions.
 *
 * Status enumeration (see include/linux/power_supply.h):
 *   0 = UNKNOWN
 *   1 = CHARGING
 *   2 = DISCHARGING
 *   3 = NOT_CHARGING
 *   4 = FULL
 *
 * Health enumeration:
 *   0 = UNKNOWN
 *   1 = GOOD
 *   2 = OVERHEAT
 *   3 = DEAD
 *   4 = OVERVOLTAGE
 *   5 = UNSPEC_FAILURE
 *   6 = COLD
 *   7 = WATCHDOG_TIMER_EXPIRE
 *   8 = SAFETY_TIMER_EXPIRE
 *   9 = OVERCURRENT
 *  10 = CALIBRATION_REQUIRED
 *
 * Technology enumeration:
 *   0 = UNKNOWN
 *   1 = NIMH
 *   2 = LION
 *   3 = LIPO
 *   4 = LIFE
 *   5 = NICD
 *   6 = LIMN
 */

#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/power_supply.h>
#include <linux/slab.h>
#include <linux/types.h>

#define DRV_NAME "fake_battery"

struct fake_battery_data {
  struct power_supply *psy;
  struct power_supply_desc desc;
  struct mutex lock;

  /* Stored (mutable) properties */
  int status;
  int health;
  bool present;
  int technology;
  int capacity;           /* percentage 0..100 */
  int charge_full_design; /* uAh */
  int charge_full;        /* uAh */
  int charge_now;         /* uAh */
  int voltage_now;        /* uV */
  int current_now;        /* uA */
  int temp;               /* decidegrees C (e.g. 300 = 30.0C) */

  /* Strings (read-only via this driver) */
  char manufacturer[32];
  char model_name[32];
  char serial[32];
};

static struct fake_battery_data *g_data;

/* Enumerate the supported properties */
static enum power_supply_property fake_battery_props[] = {
    POWER_SUPPLY_PROP_STATUS,      POWER_SUPPLY_PROP_HEALTH,
    POWER_SUPPLY_PROP_PRESENT,     POWER_SUPPLY_PROP_TECHNOLOGY,
    POWER_SUPPLY_PROP_CAPACITY,    POWER_SUPPLY_PROP_CHARGE_FULL_DESIGN,
    POWER_SUPPLY_PROP_CHARGE_FULL, POWER_SUPPLY_PROP_CHARGE_NOW,
    POWER_SUPPLY_PROP_VOLTAGE_NOW, POWER_SUPPLY_PROP_CURRENT_NOW,
    POWER_SUPPLY_PROP_TEMP,        POWER_SUPPLY_PROP_MANUFACTURER,
    POWER_SUPPLY_PROP_MODEL_NAME,  POWER_SUPPLY_PROP_SERIAL_NUMBER,
    POWER_SUPPLY_PROP_TYPE,
};

static int fake_battery_get_property(struct power_supply *psy,
                                     enum power_supply_property psp,
                                     union power_supply_propval *val) {
  struct fake_battery_data *data = power_supply_get_drvdata(psy);

  mutex_lock(&data->lock);

  switch (psp) {
  case POWER_SUPPLY_PROP_STATUS:
    val->intval = data->status;
    break;
  case POWER_SUPPLY_PROP_HEALTH:
    val->intval = data->health;
    break;
  case POWER_SUPPLY_PROP_PRESENT:
    val->intval = data->present ? 1 : 0;
    break;
  case POWER_SUPPLY_PROP_TECHNOLOGY:
    val->intval = data->technology;
    break;
  case POWER_SUPPLY_PROP_CAPACITY:
    val->intval = data->capacity;
    break;
  case POWER_SUPPLY_PROP_CHARGE_FULL_DESIGN:
    val->intval = data->charge_full_design;
    break;
  case POWER_SUPPLY_PROP_CHARGE_FULL:
    val->intval = data->charge_full;
    break;
  case POWER_SUPPLY_PROP_CHARGE_NOW:
    val->intval = data->charge_now;
    break;
  case POWER_SUPPLY_PROP_VOLTAGE_NOW:
    val->intval = data->voltage_now;
    break;
  case POWER_SUPPLY_PROP_CURRENT_NOW:
    val->intval = data->current_now;
    break;
  case POWER_SUPPLY_PROP_TEMP:
    val->intval = data->temp;
    break;
  case POWER_SUPPLY_PROP_MANUFACTURER:
    val->strval = data->manufacturer;
    break;
  case POWER_SUPPLY_PROP_MODEL_NAME:
    val->strval = data->model_name;
    break;
  case POWER_SUPPLY_PROP_SERIAL_NUMBER:
    val->strval = data->serial;
    break;
  case POWER_SUPPLY_PROP_TYPE:
    val->intval = POWER_SUPPLY_TYPE_BATTERY;
    break;
  default:
    mutex_unlock(&data->lock);
    return -EINVAL;
  }

  mutex_unlock(&data->lock);
  return 0;
}

static int fake_battery_set_property(struct power_supply *psy,
                                     enum power_supply_property psp,
                                     const union power_supply_propval *val) {
  struct fake_battery_data *data = power_supply_get_drvdata(psy);
  bool changed = false;

  mutex_lock(&data->lock);

  switch (psp) {
  case POWER_SUPPLY_PROP_STATUS:
    data->status = val->intval;
    changed = true;
    break;
  case POWER_SUPPLY_PROP_HEALTH:
    data->health = val->intval;
    changed = true;
    break;
  case POWER_SUPPLY_PROP_CAPACITY:
    if (val->intval < 0)
      data->capacity = 0;
    else if (val->intval > 100)
      data->capacity = 100;
    else
      data->capacity = val->intval;
    changed = true;
    break;
  case POWER_SUPPLY_PROP_VOLTAGE_NOW:
    data->voltage_now = val->intval;
    changed = true;
    break;
  case POWER_SUPPLY_PROP_CURRENT_NOW:
    data->current_now = val->intval;
    changed = true;
    break;
  case POWER_SUPPLY_PROP_CHARGE_NOW:
    data->charge_now = val->intval;
    changed = true;
    break;
  case POWER_SUPPLY_PROP_CHARGE_FULL:
    data->charge_full = val->intval;
    changed = true;
    break;
  case POWER_SUPPLY_PROP_TEMP:
    data->temp = val->intval;
    changed = true;
    break;
  default:
    mutex_unlock(&data->lock);
    return -EINVAL;
  }

  mutex_unlock(&data->lock);

  if (changed)
    power_supply_changed(data->psy);

  return 0;
}

static int fake_battery_property_is_writeable(struct power_supply *psy,
                                              enum power_supply_property psp) {
  switch (psp) {
  case POWER_SUPPLY_PROP_STATUS:
  case POWER_SUPPLY_PROP_HEALTH:
  case POWER_SUPPLY_PROP_CAPACITY:
  case POWER_SUPPLY_PROP_VOLTAGE_NOW:
  case POWER_SUPPLY_PROP_CURRENT_NOW:
  case POWER_SUPPLY_PROP_CHARGE_NOW:
  case POWER_SUPPLY_PROP_CHARGE_FULL:
  case POWER_SUPPLY_PROP_TEMP:
    return 1;
  default:
    return 0;
  }
}

/* Module parameters for initial values (optional tuning) */
static int initial_capacity = 75;
module_param(initial_capacity, int, 0644);
MODULE_PARM_DESC(initial_capacity, "Initial battery capacity percent (0-100)");

static int initial_voltage_uv = 3700000;
module_param(initial_voltage_uv, int, 0644);
MODULE_PARM_DESC(initial_voltage_uv, "Initial voltage_now in microvolts");

static int initial_current_ua = 500000;
module_param(initial_current_ua, int, 0644);
MODULE_PARM_DESC(initial_current_ua, "Initial current_now in microamps");

static int initial_temp_deciC = 300;
module_param(initial_temp_deciC, int, 0644);
MODULE_PARM_DESC(initial_temp_deciC, "Initial temperature in decidegrees C");

static int __init fake_battery_init(void) {
  int ret;
  struct power_supply_config psy_cfg = {};

  g_data = kzalloc(sizeof(*g_data), GFP_KERNEL);
  if (!g_data)
    return -ENOMEM;

  mutex_init(&g_data->lock);

  /* Initialize defaults (clamp capacity) */
  if (initial_capacity < 0)
    initial_capacity = 0;
  if (initial_capacity > 100)
    initial_capacity = 100;

  g_data->status = POWER_SUPPLY_STATUS_DISCHARGING;
  g_data->health = POWER_SUPPLY_HEALTH_GOOD;
  g_data->present = true;
  g_data->technology = POWER_SUPPLY_TECHNOLOGY_LION;
  g_data->capacity = initial_capacity;
  g_data->voltage_now = initial_voltage_uv;
  g_data->current_now = initial_current_ua;
  g_data->temp = initial_temp_deciC;

  /* Some arbitrary plausible design/full/now charge values (uAh) */
  g_data->charge_full_design = 4000000;
  g_data->charge_full = 3500000;
  g_data->charge_now = 2500000;

  strscpy(g_data->manufacturer, "TIIGhaf", sizeof(g_data->manufacturer));
  strscpy(g_data->model_name, "FakeBattery1", sizeof(g_data->model_name));
  strscpy(g_data->serial, "FB123456", sizeof(g_data->serial));

  g_data->desc.name = "fake-battery";
  g_data->desc.type = POWER_SUPPLY_TYPE_BATTERY;
  g_data->desc.properties = fake_battery_props;
  g_data->desc.num_properties = ARRAY_SIZE(fake_battery_props);
  g_data->desc.get_property = fake_battery_get_property;
  g_data->desc.set_property = fake_battery_set_property;
  g_data->desc.property_is_writeable = fake_battery_property_is_writeable;

  psy_cfg.drv_data = g_data;

  g_data->psy = power_supply_register(NULL, &g_data->desc, &psy_cfg);
  if (IS_ERR(g_data->psy)) {
    ret = PTR_ERR(g_data->psy);
    pr_err(DRV_NAME ": power_supply_register failed: %d\n", ret);
    kfree(g_data);
    return ret;
  }

  pr_info(DRV_NAME ": registered /sys/class/power_supply/%s\n",
          g_data->desc.name);
  return 0;
}

static void __exit fake_battery_exit(void) {
  if (g_data) {
    if (g_data->psy)
      power_supply_unregister(g_data->psy);
    kfree(g_data);
    pr_info(DRV_NAME ": unloaded\n");
  }
}

module_init(fake_battery_init);
module_exit(fake_battery_exit);

MODULE_AUTHOR("Brian McGillion <bmg.avoin@gmail.com>");
MODULE_DESCRIPTION("Fake battery power_supply driver (out-of-tree)");
MODULE_LICENSE("GPL");
