# System integration and MMIO

[PuyoSystem](../sources_1/new/PuyoSystem.v) connects the CPU, input conditioner, game engine, and video renderer in one 25 MHz clock domain. `TD8_RISCV_PUYO_TOP` adds the Basys 3 clock/reset logic and board pins.

## Data flow

`PuyoInput` synchronizes and debounces the controls, then supplies movement/rotation events and the soft-drop level to `PuyoMMIO`. The CPU reads those events and writes commands back through MMIO. `PuyoEngine` owns the board array and executes game rules. `PuyoVideo` takes a copy of the game state during vertical blanking and renders that copy for the next frame.

The CPU can inspect board cells but cannot write them. The game engine is the sole board writer. Clear markers reach the renderer only in states 12 and 13, after the search has finished.

## Peripheral registers

All peripheral accesses are aligned 32-bit `LW` or `SW`. A transaction is accepted on a rising clock edge with `valid && ready`. Narrow accesses fault in the CPU.

| Address | Access | Fields |
|---|---|---|
| `0x2000` | R/W | Bit 0: start enable |
| `0x2004` | R | Start[0], busy[1], game over[2], active[3], state[15:8] |
| `0x2008` | R | 32-bit score |
| `0x200c` | R | Chain[7:0], last chain[15:8] |
| `0x2010` | R, clears events | Left[0], right[1], counterclockwise[2], clockwise[3], soft-drop level[4], restart[5] |
| `0x2014` | W | Same action bits; bits 0..3 and 5 issue pulses, bit 4 sets the soft-drop level |
| `0x2018` | R | Milliseconds since system reset |
| `0x201c` | R | Next color A[2:0], next color B[5:3] |
| `0x2020` | R/W | Board index, low seven bits retained |
| `0x2024` | R | Cell color at the selected index; zero for indices 84..127 |
| `0x2030` | R | CPU cycle counter |
| `0x2034` | R | Retired-instruction counter |
| `0x2038` | R | Memory-wait cycles |
| `0x203c` | R | Load-use bubbles |
| `0x2040` | R | Flush events |
| `0x2044` | R | Platform ID `0x5055594f` |

Unassigned aligned words in `0x2000`–`0x20ff` read as zero and ignore writes. The legacy input at `0x100` is tied to zero in this top; the output register at `0x104` drives LED7:0. See [CPU_PLATFORM.md](CPU_PLATFORM.md) for RAM and instruction addresses.

Start enable releases the initial wait state; clearing it does not pause an active game. Event storage is a bit latch rather than a queue, so repeated events before a read merge into one. A new event arriving on the read-to-clear edge remains pending for the next read.

Movement and rotation events are discarded while the engine is busy. Restart remains available. Writing restart clears pending events and the soft-drop command. Opposing movement or rotation bits cancel each other. The input synchronizers are reset only by system reset, so a held SW14 does not become a new press after each game restart.

## Supervisor ROM

[puyo_supervisor.mem](../sources_1/new/puyo_supervisor.mem) contains the following eight-instruction program, followed by NOPs:

```asm
    lui  x1, 0x2
    addi x2, x0, 1
    sw   x2, 0(x1)
loop:
    lw   x3, 16(x1)
    sw   x3, 20(x1)
    lw   x4, 8(x1)
    sw   x4, 260(x0)
    jal  x0, loop
```

The first store enables the game. The loop forwards input to the action register and copies the score to the legacy LED output. Collision detection, gravity, clearing, and scoring are performed by the game engine. The assembly above describes the included image; a standalone assembly source and image generator are not supplied.

## Clock and constraints

`Clock25` converts 100 MHz to 25 MHz with an MMCM and BUFGs. `MillisecondTick` generates an enable every 25,000 system clocks. Game timing does not change the CPU or video clock.

The [XDC](../constrs_1/new/Basys3_Puyo.xdc) sets the 10 ns input clock and lets Vivado derive the MMCM output clock. False paths cover the first external-input synchronizer stage and asynchronous reset assertion. VGA and LED outputs use a 5 ns maximum output-delay budget. Monitor compatibility still depends on the physical VGA connection.

## Board use

Follow the [README setup](../README.md#fpga-setup) to build the project. After implementation meets the required timing and DRC checks, load the generated bitstream with Vivado Hardware Manager. With SW14 and SW15 off, check that LED15 is off, LED12 is on, and the display is stable.

Exercise individual and held movement buttons, one rotation per press, soft drop, and restart. SW14 must return low before another restart. SW15 resets the complete system. Hardware checks should include repeated restarts, power-up behavior, and sustained play on the intended monitor.
