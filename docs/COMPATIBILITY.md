# Capability report

Target machine: Apple Silicon M4 Pro, macOS 27.0.1 (26A434). Other models and OS releases are not yet validated. Source supports macOS 15+ compilation, which is not a compatibility claim.

| Feature | Implementation / verification |
|---|---|
| Battery percentage, charge state, AC status, cycles | Implemented using AppleSmartBattery IORegistry reads; live target readings verified |
| Battery health | Capacity-based estimate, explicitly labelled; not remaining years or an exact match to Apple's displayed health |
| Battery temperature | AppleSmartBatteryPack BatteryData Temperature fallback verified on target; no CPU-temperature substitution |
| Battery power | Signed current × voltage; does not represent total adapter input power |
| Process activity | Same-user processes ranked by sampled CPU activity; not per-process watts |
| Selected application termination | Start time, UID and protected process guards; instance-bound NSRunningApplication normal/force requests require explicit selection. Bare workers are handed off to Activity Monitor |
| Seven-day battery history | Local, optional, deletable; missing data stays unknown |
| Session metadata | Inactive records pruned after 30 days on app refresh/session start; user-deletable; live supervisors preserved |
| Terminal sessions | Direct argv execution, inherited terminal IO, real exit status, scoped bounded idle-sleep assertion |
| Display sleep | Uses macOS display-sleep request; manual screen-off/physical-display test is separate from command success |
| Safe resource cleanup | Opt-in; only supervisor-created explicitly registered resource; success-only SIGTERM; no automatic SIGKILL |
| Charge limit 80–100% (5% steps) | macOS charge limit through the private PowerUI client; each write is verified by reading it back. Verified on target (85%); persists across app quit, sleep and reboot. With the adapter connected and charge above the limit, macOS discharges to the limit, then runs from the adapter |
| Charge limit 50–79% | Optional root helper writing `com.apple.smartcharging.topoffprotection`; accepts only `setLimit(50…100)` and `readState`; the helper checks that the caller is the console user, runs from `/Applications/VibeBattery.app` and carries the app's signing identifier. With ad-hoc signing this is not a security boundary: any process of the logged-in user can sign itself with that identifier and request a limit between 50 and 100%. Developer ID signing will pin the team. Verified on target (75%, 70%, and 70% from the off state, where the helper sets `MCLFeatureState` 0 → 1); macOS applies helper writes after a short delay, so read-back polls up to 4 s |
| One-time full charge | PowerUI temporary disable, reported by macOS as enabled at 100%. Verified on target: charging resumed, the full-charge notification arrived, and ending it restored the user's 70% (macOS re-enables at its own stored value, so the app re-applies its last limit). Automatic return by macOS is covered by tests only |
| Heat charging hold | Opt-in. At or above the hold temperature while charging and at ≥ 50%, lowers the limit to the current charge; restores only its own value after 5 minutes at or below the resume temperature, or when the app quits. Stops automating if anyone else changes the limit. Works only while the app runs. Policy tested with injected temperatures; real high-temperature behavior not validated |
| Other charge managers | AlDente, batt, battery (actuallymentor) and Battery Toolkit are detected by running app or installed daemon; all writes and heat hold are blocked while present |
| Sailing lower bound / forced discharge / calibration | Not available: firmware 20457.1.29 blocks the SMC charge keys; the only remaining control is adapter cutoff, which conflicts with battery preservation |
| Power modes | Opens macOS Battery settings |
| MagSafe LED | Planned (`ACLC` readable, write unverified) |
| Schedules / Shortcuts | Weekly schedules (set limit, one-time full charge, turn off) run by the app with a 12-hour catch-up of the latest missed occurrence; `vbctl charge set/off/topup/end` routed to the running app over a same-user socket, usable from Shortcuts' "Run Shell Script". Verified on target (schedule run, CLI write, exit codes). Five Shortcuts actions (set limit, start and end a one-time full charge, turn off, battery status) through App Intents in the Xcode-built app; they go through the same controller and are logged as Shortcuts writes. Shortcuts lists them only for team-signed builds (Apple Development locally; ad-hoc CI builds do not show them). Verified on target: all five listed, status returned, set limit, top-up start/end logged as Shortcuts |
| Health history | Daily time-weighted records (observed time, AC time, time at ≥90/95% and ≥35/40°C, average charge, maximum temperature) kept locally for the latest 400 recorded days (counted, so a wrong clock cannot prune real history); missing keys load with defaults across versions; corrupt files are kept aside with a timestamp; gaps over five minutes stay unknown; collected only while the app runs and history is enabled; deletable |
| Lifetime trend | Theil–Sen fit of measured health over days and cycles; shown as a range for reaching 80% only after ≥30 days, ≥5 measured days and ≥1 point of change; restarts after a battery replacement (hashed serial, design capacity or cycle count drop). Needs a month of use before it can be checked on the target |
| Stress comparison | Relative storage-aging index interpolated from Battery University BU-808 Table 3 (general Li-ion data, not validated for this cell); compares the recorded pattern with the same record capped at 80%; never converted to years |
| Sleep drain | Charge before sleep and after wake while the app runs; per-hour drain only on battery for sleeps of at least one hour; highlighted only when the rate minus one point of integer rounding still exceeds 1%/h |
| Notifications | Local UNUserNotificationCenter alerts decided by a pure, tested policy; per-event toggles, one alert per condition with persisted re-arm state, clicks open an allow-listed screen. Only while the app runs (up to ~2 min late under App Nap); Time Sensitive delivery is unavailable with ad-hoc signing. Verified on target: permission prompt, test alert with the app in front and behind, click opens the window, permission kept after a rebuild, full-charge alert. Other events await real conditions |
| Automatic AI turn hooks | Planned, not implemented |

## Firmware findings (2026-10-20)

Read-only SMC probing on the target found no `CHTE`, `CH0B`, `CH0C` or `CH0I`; the firmware-limit keys `bfD0`/`bfE0`/`bfF0` refuse reads. `CHIE` (adapter cutoff) and `ACLC` (MagSafe LED) are readable. The macOS charge limit (`PowerUISmartChargeClient`) reports support and offers 80/85/90/95/100. Limits below 80 were observed (79%, set by AlDente) and appear to come from the root-owned `com.apple.smartcharging.topoffprotection` domain. Details: [charge control design](superpowers/specs/2026-10-20-charge-control-design.md).

## Scope and safeguards

A registered command ending is the completion signal. An interactive AI tool awaiting another prompt is still running. Existing jobs are not retroactively adopted for automatic cleanup. Use `resource --keep` for a persistent server; if ownership or lifecycle is unknown it is left alone.

Protection expires after the selected duration or, by default, when AC is disconnected. This releases only VibeBattery's sleep assertion; the command is not killed, and macOS may subsequently sleep. `--allow-battery` is an explicit override of AC-only protection. OS low-battery, lid-close and explicit sleep are not overridden. Other apps or system settings can still prevent sleep after VibeBattery releases its own assertion.

The app UI quitting does not kill terminal-managed sessions; each CLI supervisor owns its assertion. A killed supervisor's assertion is released by macOS; any uncertain resource is left running. Closing the lid or locking the screen may interrupt screen-based automation. App Nap, authentication waits and network failures are not solved by holding the system awake.

The current app is ad-hoc signed for local testing and is not Developer ID notarized. No SMC write, security setting change, or cloud service is installed. The optional charge helper is installed only when the user runs its install script with sudo, and is removed with the matching uninstall script.
