---
name: ghaf-test
description: Run the Ghaf Robot Framework test suite against a device and turn the results into a short list of real failures with suspected module paths. Use whenever asked to test a Ghaf device, run smoke or pre-merge or boot or GUI tests, check whether a change broke anything on hardware, or interpret a Robot Framework output.xml or a failing test report.
---

# Testing a Ghaf device

The suite lives in the `ci-test-automation` flake input and is driven by `robot-test` from
the `smoke-test` devshell. The two things that go wrong here are naming the device wrongly
(which silently changes what runs) and reading raw Robot output instead of parsing it.

## Run the tests

Through the CLI, which reads the device profile from config:

```bash
.github/skills/ghaf-hw-test/ghaf-hw-test test --device darter-pro --ip <IP>
.github/skills/ghaf-hw-test/ghaf-hw-test test --device darter-pro --ip <IP> --tag boot
```

Or directly, which is what that wraps:

```bash
nix develop .#smoke-test --command robot-test -i <IP> -d darter-pro -p ghaf -t pre-merge
```

`-p` is the ghaf/admin password; `--username` / `--userpasswd` override the normal user
(`testuser` / `testpw`). Results land in `/tmp/test_results/` unless `--outputdir` says
otherwise.

Add `--config <dir>` on a rig you have not tested before — without it three tests fail on
unset variables rather than skipping. See "Build the rig's `test_config.json`" below; doing
it up front is cheaper than reading the failures afterwards.

## Name the device correctly

`-d` takes the **physical machine**, not the image you flashed. Valid values are
`darter-pro`, `darter-sec-boot`, `lenovo-x1`, `x1-sec-boot`, `dell-7330`, `orin-agx`,
`orin-agx-64`, `orin-nx`. There is no `intel-laptop` value even though that is now the image
everyone builds.

This matters more than it looks, and for a sharper reason than a typo check. The value
becomes `DEVICE_TYPE`, which the suite uses **as a Robot tag** in the include expression
`<device>AND<tag>` — so an unrecognised device name selects *no tests at all* and the run
ends green having asserted nothing. `Robot-Framework/config/variables.robot` separately
compares `DEVICE_TYPE` against the laptop names above to set `IS_LAPTOP`, so a
near-miss value can also run a partially wrong subset. Neither case errors.

The list above is the set of device tags that actually appear on tests in
`ci-test-automation`; take it from `config.yaml`'s `test_device_name` rather than typing one
from memory. **With one exception: `NUC` is not a testable device.** No test in the suite
carries a `nuc` tag — the string survives only in `edit_report.py`'s label-removal list — so
`-d NUC` runs zero tests and reports success. If you need to test a NUC, find out which tag
its coverage lives under before believing any result.

## Choose a tag

| Tag | What it covers |
|---|---|
| `pre-merge` | quick validation — the default, and the right first move |
| `boot` | boot and connectivity |
| `bat` | basic acceptance |
| `functional` | VMs, host, networking, apps |
| `gui` | desktop behaviour |
| `performance` | benchmarks and boot time |
| `security` | security validation |
| `suspension` | suspend/resume |
| `update` | OTA update |

After a fix, run the specific tag that failed before the full suite. A `pre-merge` run that
passes tells you nothing about the `gui` regression you were chasing.

## Build the rig's `test_config.json` before the first run

Three tests read per-device facts the suite cannot discover for itself. Without them the
run does not skip — it dies on unset variables:

```
Check device id         Variable '${STATIC_DEVICE_ID}' not found.
Check net-vm hostname   Variable '${STATIC_NETVM_NAME}' not found.
Check serial connection Variable '${SERIAL_PORT}' not found.
```

`Robot-Framework/config/variables.robot` reads them from `<configpath>/test_config.json`,
and when `CONFIG_PATH` is `None` the whole branch that sets them is skipped. Seeing these
three together means no config was passed, not that anything on the device is wrong.

The file is rig-specific — addresses, a hardware id, a serial node — so it is deliberately
not in this repo. Generate it for the machine in front of you:

```bash
DEV=orin-agx                 # the value you pass to -d
IP=192.168.10.149            # net-vm's address

# device_id: stable hardware identity, /persist on the host, /etc inside a VM
ssh ghaf@$IP -- ssh ghaf-host cat /persist/common/device-id
# netvm_hostname: generated at provisioning, must not drift
ssh ghaf@$IP hostname
# serial_port: read it, do not assume -- an AGX enumerates as /dev/ttyACM*,
# not the /dev/ttyUSB* that most Jetson docs claim
ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null
```

```json
{
  "addresses": {
    "relay_serial_port": "NONE",
    "<device>": {
      "serial_port": "/dev/ttyACM0",
      "device_ip_address": "192.168.10.149",
      "threads": 12,
      "device_id": "00-c9-f1-66-f2",
      "netvm_hostname": "ghaf-3388040946"
    }
  }
}
```

The `<device>` key must equal the `-d` argument: `robot-test` passes it through as
`-v DEVICE:`, so `-d orin-agx` looks up `addresses."orin-agx"`. One file can hold every
machine in the lab. `threads` should match `default_threads` for that device in
`config.yaml`.

`serial_port`, `device_ip_address`, `threads` and `relay_serial_port` are **mandatory** —
they are read with a bare `Set Global Variable`, so a missing key is a KeyError. `device_id`
and `netvm_hostname` are read through `Run Keyword And Ignore Error`, which on failure
leaves the variable *unset* rather than defaulting it — which is why their absence surfaces
later as the confusing "Variable not found" above rather than at load time.

Then pass the **directory**, not the file:

```bash
nix develop .#smoke-test --command robot-test -i <IP> -d <device> -p ghaf \
  -t pre-merge --config /path/to/dir
```

`device_id` and `netvm_hostname` are documented as values that must never change, so they
are regression anchors: if a re-provisioned device reports different ones, update the file
deliberately — the failure is the signal working, not noise.

## Read the results

```bash
nix-shell .github/skills/ghaf-hw-test/shell.nix --run \
  'python3 .github/skills/ghaf-hw-test/lib/result_parser.py \
     /tmp/test_results/output.xml .github/skills/ghaf-hw-test/config.yaml true'
```

The third argument turns on fix proposals. The parser maps failures onto Ghaf module paths
using the `failure_patterns` table in `config.yaml` — if you find a recurring failure whose
mapping is missing or wrong, adding it there improves every future run, which is a better
investment than explaining it again by hand.

`log.html` and `report.html` in the same directory are for humans; `output.xml` is the one
to parse.

## The suite needs `testuser`, and a dev device usually cannot have it

Every suite in `pre-merge` logs into gui-vm as `testuser`. If that account is missing the
whole run fails in suite setup — 61 tests, 0 passed, every message reading
`Parent suite setup failed: User not created`. That is one environmental fault, not 61
regressions, and it says nothing about the change you deployed.

Confirm before reading anything else into it:

```bash
ssh ghaf@<host_ip> -- ssh gui-vm homectl list     # is testuser there at all?
ssh ghaf@<host_ip> -- ssh gui-vm systemctl status user-provision-test.service
```

`Skipped due to 'exec-condition'` is the tell. The suite starts that unit and takes its
exit status as proof, but **systemd reports a condition-skipped unit as a successful
start**, so `systemctl start` returns 0 having created nothing.

Why it gets skipped on a device you actually use: Ghaf is single-user by construction.
`storagevm.nix` sizes /home as `admin.homeSize + homedUser.homeSize`, and `homedUser`
defaults to a 400 GiB home, so the partition holds exactly one home area — check with
`df -h /home` on gui-vm, which reads 100% full on a provisioned device. `homedUser.uid`
(1000) is also baked into GIVC, the memsocket paths in `shared-mem.nix`, and the tmpfiles
rules in `microvm-host.nix`, so a second user at another uid would exist without a working
session anyway. Do not try to make `testuser` coexist with a real account.

Two supported ways to get there instead:

- **Fresh install.** A newly flashed debug image has no user, so the unit's condition
  passes and provisioning succeeds. Test-rig images can set
  `ghaf.services.user-provisioning.autoProvisionTestUser = true` to provision at boot, so
  the device comes up already testable. It is off by default because the test unit stops
  `user-provision-interactive`, and enabling it on a developer image means the first-boot
  prompt never runs and no personal account can ever be created.
- **Replace the existing user**, no reflash needed:

  ```bash
  ssh ghaf@<host_ip> -- ssh gui-vm ghaf-test-user-reset
  ```

  It lists the home areas, then asks before touching anything. **Answering yes destroys
  those home images irrecoverably** — hundreds of GB, no shrink path. Only do it on a
  device whose user account is expendable, and ask the device's owner first; `--force`
  skips the prompt and exists for CI, which has no tty. Under the hood it is
  `user-provision-remove.service` followed by `user-provision-test.service`.

## When a test fails

Test failures name a symptom, not a cause. Before changing code:

1. **Check the device is healthy at all.** A device that half-booted fails many unrelated
   tests. `ghaf-logs` across the VMs separates "one feature broke" from "gui-vm never came
   up", and those need completely different fixes.
2. **Confirm what is running.** Compare the deployed store path against what you built —
   a test can only fail against the code that is actually on the device.
3. **Trust the logs over the test name.** The suite reports the assertion that tripped;
   the journal on the responsible VM says why. Hand the snapshot to `ghaf-log-triage` and
   reconcile its findings with the failing test before proposing anything.

A test that fails identically before and after your change is not your regression — it is
the baseline, and worth stating explicitly so nobody chases it twice.
