# Signal Map — CHUSO1800 Lua Core

This is the binding source of truth for how every signal from
`CHUSO1800_Traction_Controller/main.sw-net` / `scripts/n409.lua` maps onto the
`calculateTick(stateless_in, state_in) -> stateless_out, state_out` contract
implemented in `src/chuso1800_core.lua`. Section numbers below (`SPEC §x.y`)
refer to `../CHUSO1800_Traction_Controller/SPEC.md`.

Nothing in this directory modifies `CHUSO1800_Traction_Controller/`. This is a
standalone prototype; wiring it into `main.sw-net` is future, out-of-scope
work (see README.md's "Future integration" section).

## Contract shape

```
calculateTick(stateless_in, state_in) -> stateless_out, state_out
```

- `stateless_in`, `stateless_out`: arrays `[1..8]`, one Lua number each.
- `state_in`, `state_out`: arrays `[1..8]`, one Lua number each.
  `state_out` from tick N is fed back verbatim as `state_in` on tick N+1.
- Each slot is either a raw double, or an integer produced by
  `bitpack.pack(layout, fields)` / consumed by `bitpack.unpack(layout, value)`
  (see `src/bitpack.lua`).

## Bucket (a) — true latching state → packed state bitfields

| Signal | sw-net origin | SPEC ref |
|---|---|---|
| `position_counter` (0-20) | `FUNC_NUM_3 position_counter`, self-loop `(x+y)%21` | §3.2 |
| `phase1_latch` | `SR_LATCH traction_phase1_latch` | §3.6 |
| `phase2_latch` | `SR_LATCH traction_phase2_latch` | §3.6 |
| `regen_latch` | `SR_LATCH regen_latch` | §3.6 |
| `panta1_latch` / `panta2_latch` | `SR_LATCH panta1_latch` / `panta2_latch` | §3.9 |
| `panta1_en_latch` / `panta2_en_latch` | `SR_LATCH panta1_en_latch` / `panta2_en_latch` | §3.9 |
| `traction_phase1_cap` / `traction_phase2_cap` / `current_below_limit_cap` | `CAPACITOR(0.1, 0)` ×3 | §3.6/§3.7 |
| `regen_delay_cap` | `CAPACITOR(0.5, 10)` | §3.8 |
| `traction_blinker` (0.1/0.1) | `BLINKER` | §3.2 |
| `regen_warning_blinker` (0.1/0.4) | `BLINKER` | §3.6 |
| `position_tick_pulse` / `regen_warning_pulse` | `PULSE(rise)` ×2 | §3.2/§3.6 |

Deliberately **not** state (see README "Simplifications" section):

- `power_cut_latch_q` / `startup_delay` / `motor_current_oor` chain — provably
  dead (SPEC §4.4). Exposed only as a hardcoded-`false` status bit.

## Bucket (b) — quasi-state (raw double, self-referencing, decaying)

| Signal | Source | Formula |
|---|---|---|
| `OLD_I` | `n409.lua` global | last tick's Newton-solve armature current |
| `OLD_IF_A` | `n409.lua` global | last tick's field current |
| `OLD_PHI` | `n409.lua` global | last tick's flux |
| `regen_bc_smooth` | `FUNC_NUM_3` self-loop | `min(clamp(x, y-0.1, y+0.02), 0)` |
| `bc_target_smooth` | `FUNC_NUM_3` self-loop | `x*0.2 + y*0.8` (EMA) |

**Implementation note**: the Newton solve's iteration seed is *not* `OLD_I`.
`n409.lua` seeds from `input.getNumber(6)`, which `main.sw-net`'s `sim_input`
wires to a hardcoded `CONST(200)` every tick. `physics_tick` must seed from
the constant `200`, not from `state.OLD_I`.

## Bucket (c) — stateless, recomputed every tick

`notch_eff`, `notch_ge1..4`, `direction`, `eb_condition` (uses the *real*
machine semantics `direction == 0` only — SPEC §4.2 — not the sw-net literal
`(0,1)` threshold, which SPEC identifies as a storm-mcl serialization bug),
`power_with_regen`, `coasting_cond`/`neutral_cond`/`phase_reset_cond`,
`current_below_limit` (pre-debounce), `regen_available`, `brake_below_min`,
`overspeed`, `regen_bc_target`, `ecb_sap_pressure`, `current_limit_sw`,
`traction_any_active` (pre-blinker).

## State slot layout

### `state_in[1]` / `state_out[1]` — `STATE_LATCHES_LAYOUT` (22 of 32 bits)

| order | field | bits | range |
|---|---|---|---|
| 1 | `position_counter` | 5 | 0-20 (0-31 representable) |
| 2 | `phase1_latch` | 1 | bool |
| 3 | `phase2_latch` | 1 | bool |
| 4 | `regen_latch` | 1 | bool |
| 5 | `panta1_latch` | 1 | bool |
| 6 | `panta2_latch` | 1 | bool |
| 7 | `panta1_en_latch` | 1 | bool |
| 8 | `panta2_en_latch` | 1 | bool |
| 9 | `traction_blinker_phase` | 1 | bool |
| 10 | `traction_blinker_counter` | 3 | 0-6 |
| 11 | `regen_warning_blinker_phase` | 1 | bool |
| 12 | `regen_warning_blinker_counter` | 5 | 0-23 |

10 bits spare (22-31).

**Implementation refinement vs. the original plan draft**: the `PULSE(rise)`
edge detectors (`position_tick_pulse`, `regen_warning_pulse`) do not need
their own "previous output" state bit. Since each blinker's phase bit is
itself state (`state_in` = old phase, freshly computed `new phase` = this
tick's decision), the rising edge is simply
`(not old_phase) and new_phase` — computable within the same tick with no
extra storage. This freed 2 bits versus the original plan draft.

### `state_in[2]` / `state_out[2]` — `STATE_TIMERS_LAYOUT` (19 of 32 bits)

| order | field | bits | range |
|---|---|---|---|
| 1 | `regen_delay_cap_level` | 10 | 0-600 |
| 2 | `phase1_cap_counter` | 3 | 0-6 |
| 3 | `phase2_cap_counter` | 3 | 0-6 |
| 4 | `current_below_limit_cap_counter` | 3 | 0-6 |

13 bits spare (19-31).

### `state_in[3..7]` / `state_out[3..7]` — raw doubles

| slot | field |
|---|---|
| 3 | `OLD_I` |
| 4 | `OLD_IF_A` |
| 5 | `OLD_PHI` |
| 6 | `regen_bc_smooth` |
| 7 | `bc_target_smooth` |

### `state_in[8]` / `state_out[8]` — spare (always 0 for now)

## Stateless input slot layout

Assumes `sap_ecb_toggle` hardcoded to **ECB** (matches the sw-net property's
own default: `PROPERTY_TOGGLE` with no `v=` override defaults off = "ECB"
label — see `main.sw-net` line ~102, and SPEC §3.8 "既定 OFF=ECB"). Under
ECB, `brake_pressure_sw`/`sap_pressure_sw` never read `"BP [atm]"`/`"SAP
[atm]"` — but slots 5-6 are still wired to those ports (see README risk #2)
so a future SAP-mode switch needs only a constant flip, not a slot-layout
redesign.

| slot | content | source |
|---|---|---|
| 1 | `speed` (m/s) | Physics Sensor ch9 |
| 2 | `catenary_voltage_sw` (V) | stays a gate computation upstream, fed in as-is |
| 3 | `sap_raw` | Simple IF ch1 (number) — brake handle position, 0-8ish |
| 4 | `INPUT_BITS_LAYOUT` packed bitfield (14 of 32 bits, see below) | Simple IF / Extended IF / Controller Stop |
| 5 | `"BP [atm]"` (pre-wired, unused while ECB is hardcoded) | BP sensor port |
| 6 | `"SAP [atm]"` (pre-wired, unused while ECB is hardcoded) | SAP sensor port |
| 7-8 | spare (0) | |

### `INPUT_BITS_LAYOUT` (14 bits)

| order | field | bits | source |
|---|---|---|---|
| 1 | `notch_pos` | 3 | Simple IF ch2 (number, clamped 0-7 at pack time) |
| 2 | `controller_stop` | 1 | top-level `Controller Stop` port |
| 3 | `regen_flag` | 1 | Simple IF ch18 bool |
| 4 | `forward_signal` | 1 | Simple IF ch16 bool |
| 5 | `backward_signal` | 1 | Simple IF ch17 bool |
| 6 | `eb_signal` | 1 | Simple IF ch1 bool |
| 7 | `panta_enable_signal` | 1 | Extended IF ch6 bool |
| 8 | `panta_all_down_signal` | 1 | Extended IF ch7 bool |
| 9 | `panta1_up_signal` | 1 | Extended IF ch4 bool |
| 10 | `panta1_down_signal` | 1 | Extended IF ch5 bool |
| 11 | `panta2_up_signal` | 1 | Extended IF ch8 bool |
| 12 | `panta2_down_signal` | 1 | Extended IF ch9 bool |

## Stateless output slot layout

`current_src_mux`'s ch2 (back-EMF), ch5 (cam echo / `notch_fb`), ch6
(`iF_a`) have zero consumers in `main.sw-net` once the state machine that
was their only reader is absorbed into this module (verified by tracing
every `COMPOSITE_READ_NUMBER`/`COMPOSITE_READ_BOOLEAN` of
`current_src_mux_out` and `traction_status_bool_out`) — they are **not**
exported. ch3 (`accel`) fed only `bc_target_raw`'s EMA, which is now
internal (bucket b) — the *smoothed* value is exported instead of the raw
one.

| slot | content | why it must leave the module |
|---|---|---|
| 1 | `motor_current` | DANRYU gate, Momelink-1900 ch24 |
| 2 | `W` | direct output port `W` |
| 3 | `bc_target_smooth` | feeds `BC target [atm]` output chain |
| 4 | `bcT` | feeds the existing (mislabeled, unchanged) `speed_display`/Momelink ch25 path |
| 5 | `STATUS_BITS_LAYOUT` packed bitfield (12 of 32 bits, see below) | RSS / Momelink / catenary-voltage-mux gates |
| 6-8 | spare (0) | |

### `STATUS_BITS_LAYOUT` (12 bits)

| order | field | bits | consumed by a gate today? |
|---|---|---|---|
| 1 | `cam_pulse` | 1 | yes — direct output port `cam` |
| 2 | `panta1_1800_active` | 1 | yes — RSS ch6, catenary `panta_up` mux |
| 3 | `panta2_1800_active` | 1 | yes — RSS ch8, catenary `panta_up` mux |
| 4 | `panta1_1800_latched` | 1 | yes — RSS ch5 |
| 5 | `panta2_1800_latched` | 1 | yes — RSS ch7 |
| 6 | `phase1_latch` | 1 | no — reserved/debug |
| 7 | `phase2_latch` | 1 | no — reserved/debug |
| 8 | `regen_latch` | 1 | no — reserved/debug |
| 9 | `notch_ge1` | 1 | no — reserved/debug |
| 10 | `low_bc_with_regen_flag` | 1 | no — reserved/debug |
| 11 | `regen_warning_cond` | 1 | no — reserved/debug |
| 12 | `power_cut` | 1 | hardcoded 0 — see README "Simplifications" |

## What stays in gates (unconverted this phase)

- Catenary voltage selector chain (`catenary_active_thresh` … `catenary_voltage_sw`) — reads this module's `panta1_1800_active`/`panta2_1800_active` output bits, unchanged.
- Momelink-A formatting (`momelink_1800_out`/`momelink_1900_out`/`momelink_version_sw`/`momelink_src_mux`/`momelink_1900_select`).
- Rolling Stock Status formatting (`rolling_status_bool_write`/`rolling_status_write`/`bc_pressure_kpa`/etc).
- `bc_target_read` (inter-unit Momelink passthrough — unrelated to this migration).

All four are pure stateless data formatting/muxing with no latching state of
their own; moving them into Lua would not simplify anything.
