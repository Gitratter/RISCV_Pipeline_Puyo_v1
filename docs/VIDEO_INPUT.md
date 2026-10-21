# Video and input

The input conditioner and VGA renderer share the 25 MHz system clock with the CPU and game engine. Input timing uses a one-millisecond enable; video timing uses every system-clock edge.

## Physical controls

[PuyoInput](../sources_1/new/PuyoInput.v) passes each active-high input through two synchronizer registers marked `ASYNC_REG`. It samples stability on `tick_ms`. A changed level must persist for `DEBOUNCE_MS` samples before the debounced state changes; a return to the old level clears the counter.

| Parameter | Default | Function |
|---|---:|---|
| `DEBOUNCE_MS` | 10 | Consecutive samples required for a new level |
| `DAS_MS` | 180 | Delay before the first repeated horizontal move |
| `ARR_MS` | 60 | Interval between later repeated moves |

Rotation and restart produce one-clock events on a debounced rising edge. Soft drop exposes the held level. Horizontal movement produces an event when the selected direction changes, then repeats after the configured delays.

Holding both horizontal buttons cancels movement. Releasing one starts a new hold in the remaining direction, including an immediate move and a fresh repeat delay. Opposing rotation events are cancelled downstream by the command logic.

SW14 must return low and pass debounce before another rising edge can request restart. Game restart does not reset the input circuit; only system reset does. This prevents a held switch from repeatedly restarting the game.

The module's `CLK_HZ` parameter is retained in its interface but is not used to generate the sampling interval. `MillisecondTick` in the parent supplies `tick_ms`.

## VGA timing

[PuyoVideo](../sources_1/new/PuyoVideo.v) produces four bits each of red, green, and blue, with active-low horizontal and vertical synchronization.

| Interval | Horizontal pixels | Vertical lines |
|---|---|---|
| Visible | 0..639 | 0..479 |
| Front porch | 640..655 | 480..489 |
| Sync pulse | 656..751 | 490..491 |
| Back porch | 752..799 | 492..524 |
| Total | 800 | 525 |

The horizontal rate is `25 MHz / 800 = 31.25 kHz`. The frame rate is `25 MHz / (800 x 525) = 59.5238 Hz`. RGB is zero outside the visible region. RGB, HSYNC, and VSYNC are registered on the same edge, giving one pixel of latency with no relative offset between them.

The pixel clock differs from the conventional 25.175 MHz value for this raster. Monitor acceptance must be checked with the actual display.

## Board and text rendering

The visible board starts at pixel `(64,48)`. Cells are 32 x 32 pixels, and the six-column, twelve-row display ends at `(255,431)`. Game row 2 maps to the top display row; game rows 0 and 1 remain hidden.

The renderer overlays the active pair on the fixed board. Colors 1..4 map to red, green, blue, and yellow. `palette()` defines colors and `puyo_pixel()` draws the rounded shapes and eyes. Marked pieces are highlighted in white. NEXT shows color B above pivot color A, matching the spawn orientation.

Text uses a 5 x 7 bitmap font enlarged by two, with a 12 x 14 pixel character cell including spacing. The panel displays score, current chain, last chain, NEXT, game status, and controls. Score uses ten decimal digits; chain values use three digits. Leading zeros are retained.

## Frame snapshots

At internal coordinate `(0,480)`, the renderer copies the board, active pair, preview, score, chain, status, and clear mask into display registers. It also emits a one-clock `frame_tick`. Rendering uses this copy throughout the visible frame, so game updates cannot change the board halfway down the screen.

The score is converted from 32-bit binary to ten BCD digits over 32 clocks during vertical blanking using shift-and-add-three conversion. The eight-bit chain values use the same conversion principle in fixed combinational loops. Score division is therefore absent from the pixel path.

All source and snapshot registers share a clock. A future design with separate game and video clocks would need an explicit transfer protocol. A synchronous sprite ROM would also require its added latency to be matched in the coordinate and synchronization paths.

## Verification scope

The included [system test](../sim_1/new/tb_system.v) exercises debounced controls through the CPU/MMIO path, but it does not check a full VGA frame. Dedicated input and video testbenches are not included in this repository.

A frame test should check 800 x 525 clocks, a 96-pixel horizontal sync pulse on every line, a two-line vertical sync pulse, black blanking pixels, snapshot stability, and decimal conversion at the numeric limits. Physical testing additionally covers monitor synchronization, cable quality, button response, and restart behavior.
