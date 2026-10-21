# Game engine

[PuyoEngine](../sources_1/new/PuyoEngine.v) implements the game rules as a clocked Verilog state machine. It receives commands forwarded by the CPU through MMIO and produces the board, active pair, next pair, score, and status for the renderer.

## Board and active pair

The board has six columns and fourteen rows. Coordinates run from `(0,0)` at the upper left to `(5,13)` at the lower right. Rows 0 and 1 are hidden but participate in gravity, searches, and clearing.

Cells use `board[y*6+x]`. The output representation is `board_flat[(y*6+x)*3 +: 3]`. Color 0 is empty; colors 1..4 are playable colors. RGB values are defined by the renderer.

The active pair is held separately from the fixed board. Color A is the pivot at `active_x, active_y`; color B is placed according to the orientation:

| Orientation | Position of color B |
|---:|---|
| 0 | Above the pivot: `(x,y-1)` |
| 1 | Right: `(x+1,y)` |
| 2 | Below: `(x,y+1)` |
| 3 | Left: `(x-1,y)` |

A pair spawns with its pivot at `(2,1)` and orientation 0. Both spawn cells must be empty. The preview colors become the active colors, then a new preview is generated.

## Movement and timing

Moves and rotations are accepted only if both resulting cells are inside the board and empty. There are no wall kicks or quick turns. Opposing directions cancel. When commands coincide, the candidate position is updated in this order: horizontal movement, rotation, then falling.

Movement and rotation inputs are one-clock pulses; soft drop is a level. Commands are used only in the active state and are not queued for the next pair. Restart takes priority in every state.

| Parameter | Default | Meaning |
|---|---:|---|
| `AUTO_DROP_MS` | 700 | Normal fall interval |
| `SOFT_DROP_MS` | 40 | Fall interval while soft drop is held |
| `FALL_STEP_MS` | 40 | Delay after a gravity pass that moved cells |
| `CLEAR_DELAY_MS` | 180 | Delay between completing a search and clearing its matches |

`tick_ms` is an enable, not a separate clock. A single fall timer uses either the normal or soft-drop threshold. Switching to soft drop can therefore trigger a fall on the next tick if enough time has already elapsed. Values of zero or one advance on the next tick.

The engine waits for `start_enable` after reset. Once started, clearing that signal does not pause play. Restart clears the board, score, pair state, search state, and timers. If start enable remains high, a new game begins.

## State machine

| `state_debug` | State | Operation |
|---:|---|---|
| 0 | WAIT | Wait for start enable |
| 1 | SPAWN | Check the spawn cells and load the next pair |
| 2 | ACTIVE | Apply movement, rotation, and falling |
| 3 | LOCK | Write the pair into the board |
| 4 | GRAVITY_INIT | Start a gravity pass |
| 5 | GRAVITY | Visit cells and move each eligible cell down one row |
| 6 | FALL_WAIT | Hold the result for the fall-animation interval |
| 7 | SCAN_INIT | Clear search flags and the clear mask |
| 8 | SCAN | Find the next unvisited component |
| 9 | BFS_POP | Remove a cell from the search queue |
| 10 | BFS_NEIGHBOR | Examine one orthogonal neighbor |
| 11 | MARK | Add a qualifying component to the clear mask |
| 12 | CLEAR_WAIT | Display the complete clear mask |
| 13 | CLEAR | Clear marked cells and update score and chain |
| 14 | GAME_OVER | Wait for restart |

All board writes occur in one clocked process. Initialization, locking, gravity, clearing, and debug writes are mutually exclusive branches.

### Locking and gravity

If a fall attempt cannot move both cells, the pair enters LOCK without a lock-delay interval. After locking, the two cells fall independently.

A gravity pass visits rows 12 down to 0 in each column, making 78 cell checks. A nonempty cell moves down one row if the cell below is empty. This preserves vertical order. If any cell moved, the engine waits `FALL_STEP_MS` and repeats. Search begins only after an entire pass produces no movement.

### Connected components

Breadth-first search visits cells of the same color through left, right, up, and down neighbors. Diagonal contact does not connect cells. The queue holds up to 84 cell indices; cells are marked visited when enqueued, preventing duplicate entries.

A component with at least four cells is added to `clear_mask`. The board remains unchanged while all components are examined. After the full scan, all marked cells are cleared together. Separate groups found in the same scan count as one chain stage.

The mask is assembled during MARK. `PuyoSystem` exposes it to video only in CLEAR_WAIT and CLEAR, when the complete set is available.

### Scoring and game over

Each clear adds:

```text
points = total cells cleared in this stage x 10 x new chain count
```

After clearing, the engine returns to gravity and repeats the search. `chain` resets at the next spawn. `last_chain` retains the most recent clearing stage, including through a later pair that clears nothing. The 32-bit score wraps on overflow.

Game over is checked at spawn, after settling and clearing have finished. Occupying either `(2,0)` or `(2,1)` blocks the new pair. This is the game's simplified loss condition.

## Pair sequence

The default generator is a 16-bit LFSR seeded with `0xACE1`. Feedback XORs bits 15, 13, 12, and 10. Four steps are used to generate each new preview, with two-bit values mapped to colors 1..4. Identical-color pairs are allowed, and reset/restart repeats the sequence.

With `FIXED_SEQUENCE=1`, the engine cycles through a 256-entry ROM. Its default pattern enumerates `(A,B)=(1,1),(2,1),...,(4,4)` repeatedly. `SEQUENCE_FILE` can supply a `$readmemh` file with one six-bit hexadecimal value per pair, packed as `{B[2:0],A[2:0]}`. Examples are `09` for `(1,1)`, `0a` for `(2,1)`, and `24` for `(4,4)`. Use 256 entries with each color in 1..4.

## Debug interface

Debug controls require `ENABLE_DEBUG=1`; the board configuration disables them. While `dbg_mode=1`, normal progression is held, but reset and restart still take priority.

| Control | Effect |
|---|---|
| `dbg_we` | Write `dbg_data` to a valid board address 0..83 |
| `dbg_resolve` | Remove the active pair and prepare gravity/search/clear processing |
| `dbg_set_active` | Set the supplied pair if both cells fit |
| `dbg_mode=0` | Resume normal progression |

Resolution setup clears chain/search state but retains score. Use reset between independent scoring cases. Apply the last board write before the resolution request.

The included [integration test](../sim_1/new/tb_system.v) checks CPU-mediated control, locking, NEXT, and restart. A standalone engine testbench is not included. Useful additional cases include three versus four connected cells, diagonal contact, separated simultaneous groups, stepped landings, the 84-cell component, and known multistage chains.
