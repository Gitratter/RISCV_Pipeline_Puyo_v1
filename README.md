# RISCV_Pipeline_Puyo_v1

A single-player falling-pair puzzle game for the Digilent Basys 3, built around a five-stage RV32I processor, a hardware game engine, and VGA output.

The CPU runs an eight-instruction supervisor that starts the game, reads input events, sends commands to the game engine, and copies the score to the LEDs. `PuyoEngine` performs collision detection, gravity, connected-component searches, clearing, and scoring. All player commands pass through CPU loads and stores.

## System

```text
Buttons and SW14 -> PuyoInput -> PuyoMMIO <-> RV32I CPU
                                    |
                               PuyoEngine
                                    |
                         Frame snapshot -> VGA
```

The Basys 3's 100 MHz oscillator feeds an MMCM that produces the 25 MHz system and pixel clock. CPU, game engine, input logic, and video share this clock. A one-millisecond enable controls input sampling and game timers.

The CPU has separate synchronous memories: a 16 KiB instruction ROM and 4 KiB data RAM. It holds the pipeline while waiting for memory responses. VGA uses a 640 x 480 visible area within an 800 x 525 frame, giving approximately 59.52 Hz at 25 MHz.

## Controls

| Board input | Action |
|---|---|
| `btnL` / `btnR` | Move left / right; hold to repeat |
| `btnU` | Rotate clockwise once per press |
| `btnC` | Rotate counterclockwise once per press |
| `btnD` | Soft drop |
| SW14, OFF to ON | Restart the game; return OFF before restarting again |
| SW15 ON | Hold the system in reset; switch OFF to run |

The board has six columns and fourteen rows, with the top two rows hidden. Groups of at least four orthogonally connected pieces of the same color clear together. Each clear adds `pieces cleared x 10 x chain number` points. Rotation has no wall kicks or lock delay.

LED15 indicates a CPU fault, LED14 game over, LED13 resolution in progress, and LED12 game-start enable. LED11:8 show bits 19:16 of the retired-instruction counter; LED7:0 show the low score byte written by the supervisor. SW0:13 and the seven-segment display are unused.

## Repository layout

| Path | Contents |
|---|---|
| [sources_1/new](sources_1/new) | CPU, platform, game, input, and video RTL; supervisor ROM image |
| [constrs_1/new](constrs_1/new) | Basys 3 pin and timing constraints |
| [sim_1/new/tb_system.v](sim_1/new/tb_system.v) | Integration test through the CPU and MMIO path |
| [docs](docs) | Architecture, interfaces, game rules, and verification procedures |
| [scripts](scripts) | Utilities that still refer to an earlier source layout |

The scripts expect directories such as `rtl/`, `sim/`, and `firmware/`, which are absent from this checkout. Use the manual setup below and the simulation command in [VALIDATION.md](docs/VALIDATION.md). Only the integration testbench is included here; the larger test suite referenced by those scripts is absent.

## FPGA setup

1. Create a Vivado project for `xc7a35tcpg236-1`.
2. Add every `.v` file in `sources_1/new` as a design source.
3. Add [puyo_supervisor.mem](sources_1/new/puyo_supervisor.mem) as a memory initialization file so Vivado makes it available to synthesis and simulation runs.
4. Add [Basys3_Puyo.xdc](constrs_1/new/Basys3_Puyo.xdc) as constraints.
5. Set the top module to `TD8_RISCV_PUYO_TOP`. Leave the `SIMULATION` define unset for synthesis.
6. Run synthesis and implementation, inspect timing and DRC reports, then generate the bitstream.

The prebuilt supervisor image is sufficient to build the hardware. Assembly source and a ROM generator are not included. Routed reports and a bitstream are also absent, so this checkout alone does not establish timing closure or successful board operation.

## Documentation

- [CPU, memory, and pipeline control](docs/CPU_PLATFORM.md)
- [System integration and MMIO](docs/INTEGRATION.md)
- [Game rules and state machine](docs/GAME_ENGINE.md)
- [Video and input](docs/VIDEO_INPUT.md)
- [Simulation and hardware checks](docs/VALIDATION.md)

The CPU derives from [TD8_To_RISCV_v3-pipeline](https://github.com/y0sh120040803-cpu/TD8_To_RISCV_v3-pipeline). Source modules retain the `V31` name for the synchronous-memory interface.

## License

[MIT](LICENSE).
