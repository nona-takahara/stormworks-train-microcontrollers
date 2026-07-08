# CHUSO1800 Lua Core (prototype)

A standalone, pure-function Lua port of most of `CHUSO1800_Traction_Controller`'s
control logic (main.sw-net's phase1/phase2/regen state machine, cam
advance/homing, notch processing, EB condition, BC/regen-BC smoothing,
pantograph latches) plus its existing physics (`scripts/n409.lua`), unified
into one module under a strict pure-function contract.

**Nothing in `CHUSO1800_Traction_Controller/` is modified by this directory.**
This is a design/verification prototype, not (yet) wired into `main.sw-net`.
See "Future integration" below for what that would take.

Full derivation of every signal, and how it maps onto slots/bits, is in
[`SIGNAL_MAP.md`](./SIGNAL_MAP.md).

## The contract

```lua
local core = require("chuso1800_core")
local stateless_out, state_out = core.calculateTick(stateless_in, state_in)
```

- `stateless_in`, `stateless_out`: arrays `[1..8]` of Lua numbers -- current
  tick's sensor-like values / current tick's outputs.
- `state_in`, `state_out`: arrays `[1..8]` of Lua numbers -- `state_out` from
  tick N is fed back verbatim as `state_in` on tick N+1 (a self-loop).
- No persistent Lua globals are used for control state. Everything that
  crosses a tick boundary lives in `state_in`/`state_out`, which makes the
  whole module callable and testable from a plain `lua` interpreter with no
  Stormworks `input`/`output` mocking needed (see "Testing").
- Each slot is either a raw double, or an integer produced by
  `bitpack.pack`/consumed by `bitpack.unpack` (`src/bitpack.lua`), letting
  several booleans/small integers share one 32-bit slot.

## Tick model

The literal gate-net model (SPEC.md §0.2) treats every single gate output as
delayed by exactly one tick, so a chain of D combinational gates takes D
ticks to settle. Replicating that literally would require a dedicated state
slot for every intermediate signal in a ~150-node graph -- incompatible with
an 8-slot budget.

Instead, this module treats only genuine cross-tick state as delayed
(SR latches, debounce/timer capacitors, blinkers, the physics quasi-state,
BC smoothing): reading the OLD value from `state_in` when deciding this
tick's outcome, and writing a NEW value to `state_out` for next tick.
Everything else (notch processing, EB condition, direction, BC target
formulas, etc.) is pure combinational logic re-evaluated fully within a
single `calculateTick` call.

SPEC.md's own closing note in §0.2 anticipates and accepts this kind of
collapsing ("if some signals propagate within the same real tick, transient
corner-case tick-counts shrink, but steady-state conclusions are
unchanged") -- see `test/scenarios/h7_cam_overshoot_homing.lua` for a
concrete case (SPEC's H7 overshoot artifact, which depends on an
extra gate-hop of delay, does not reproduce here) where this is worked
through explicitly rather than silently assumed.

## What stays in gates (not converted this phase)

Pure stateless data formatting/muxing, with no latching state of their own --
moving them into Lua wouldn't simplify anything:

- Catenary voltage selector chain (reads this module's `panta1_1800_active`/
  `panta2_1800_active` status bits, unchanged).
- Momelink-A composite formatting (1800/1900 frame selection).
- Rolling Stock Status composite formatting.
- `bc_target_read` (inter-unit Momelink passthrough, unrelated to this
  migration).

See `SIGNAL_MAP.md`'s "What stays in gates" section for the exact node list.

## Simplifications (flagged, not silent)

1. **`power_cut_latch`/`startup_delay`/`motor_current_oor` removed entirely.**
   `startup_delay`'s `enable` input is unconnected in `main.sw-net` with
   `discharge_time=0`, so its output is provably `false` forever;
   `motor_current_oor`'s `+-200000A` threshold is unreachable from the
   Newton-solve's actual current range (a few hundred amps). The reset-
   priority latch downstream is therefore provably `q == false` for the
   life of execution -- this is a proof of dead code, not a behavior
   change. `power_cut` is exposed as a hardcoded-`false` status bit only so
   RSS-bit parity is trivial if the unconverted gates want it. Guarded by
   `test/scenarios/power_cut_dead_logic_constant.lua`.

2. **SAP/ECB toggle hardcoded to ECB.** Matches the sw-net property's own
   default (`PROPERTY_TOGGLE` with no `v=` override -> off -> "ECB" label).
   This is a real behavior change versus the original, which could switch
   modes live in Stormworks' property panel: SAP/ECB is now a source-code
   constant (`SAP_ECB_IS_SAP` in `src/chuso1800_core.lua`). Stateless input
   slots 5/6 are still wired to `"BP [atm]"`/`"SAP [atm]"` (unused while ECB
   is hardcoded) specifically so re-enabling SAP mode later needs only a
   constant flip, not a slot-layout redesign.

3. **M-type (1800/1900) hardcoded to 1800** (`IS_1800_TYPE` constant). The
   unconverted Momelink-select gate still reads its own live
   `mtype_toggle` property, so this unit now has two independent sources of
   truth for "1800 vs 1900" that must be kept in sync by hand if this
   design is ever reused for a 1900-type unit.

4. **CAPACITOR charge/discharge modeled as a linear accumulator** (charge_time
   seconds to reach "charged" while enabled, discharge_time seconds to reach
   0 while disabled; `regen_delay_cap`'s 0.5s/10s pair is represented as a
   0-600 level with +20/tick charge, -1/tick discharge). This is SPEC.md
   §0.1's own description of CAPACITOR, but hasn't been cross-checked
   against Stormworks' actual internal implementation -- see
   `test/scenarios/regen_delay_cap_timing.lua` for the boundary tests this
   assumption would need to survive.

5. **BLINKER always starts a fresh `off_ticks`-long "off" phase when
   (re-)enabled**, rather than an instantly-on response. This costs up to
   `off_ticks` of extra latency after a state transition enables a blinker
   (0.1s for the traction/regen-warning blinkers' shorter phase, 0.4s for
   the regen-warning blinker's off phase), but keeps the stored phase bit an
   honest reflection of "current output" -- required for the rising-edge
   (PULSE) detection to work with zero extra state bits. See the
   `blinker_step` comment in `src/chuso1800_core.lua`.

## Slot budget (see SIGNAL_MAP.md for the full bit tables)

- State: 22 (packed latches/timers) + 10 (packed) + 5 raw doubles = 7 of 8
  slots used, 1 spare.
- Stateless input: 4 of 8 slots used, 4 spare (2 of the spares are
  pre-wired to `"BP [atm]"`/`"SAP [atm]"` for a future SAP-mode flip).
- Stateless output: 5 of 8 slots used, 3 spare.

None of these required consulting on exceeding the 8-slot budget (the
concern the plan flagged up front) -- there was room to spare in every
category once the physics/state-machine consolidation eliminated several
channels (back-EMF, cam echo, field current) that turned out to have no
consumer left outside the module.

## Testing

Pure Lua, no Stormworks runtime needed:

```sh
lua test/run_all.lua
```

13 scenarios (`test/scenarios/*.lua`), including a byte-for-byte numeric
regression against the **untouched** `../CHUSO1800_Traction_Controller/scripts/n409.lua`
(via a small `input`/`output` shim that `loadfile`s it directly, so this
also passively re-verifies that file hasn't been modified), full traversal
of SPEC.md §3.6's state diagram, and SPEC.md's documented corner cases
(H4/H5/H6/H7).

## Future integration (out of scope for this prototype)

Wiring this into `main.sw-net` would require (not attempted here):

1. Repoint (or replace) the `LUA current_sim` node's `script_ref` to this
   module, restructured as a Stormworks `onTick()` that packs/unpacks the
   8+8 slots via two Composite Read/Write pairs (one self-looped for state,
   one from/to real gates for stateless in/out).
2. Delete the now-superseded gate networks: the phase1/phase2/regen SR
   latches and their set/reset logic, `position_counter`/blinkers/pulses/
   debounce capacitors, `notch_eff`/`notch_ge*`, `eb_condition`,
   `current_src_mux`/`regen_current_write`, `regen_bc_smooth`/
   `bc_target_smooth`, and the 4 pantograph latches.
3. Wire `catenary_voltage_sw` as a genuine input to the new Lua node
   (currently it's downstream-only of the gate state machine's inputs).
4. Re-route the surviving gates (catenary selector, Momelink formatting,
   Rolling Stock Status) to read the new module's status-bitfield output
   instead of the old composite channels/booleans they used to read.
5. Decide whether to keep the SAP/ECB and M-type hardcodes as source
   constants going forward, or design a way to feed live properties back
   into the packed input bitfield (slots 5/6 are already reserved for this).
