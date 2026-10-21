# Verification

This checkout includes one integration testbench, [tb_system.v](../sim_1/new/tb_system.v). The scripts in `scripts/` refer to an earlier `rtl/`, `sim/`, and `firmware/` layout and to test sources absent from this repository. The commands below use the files that are present.

## Integration simulation

Install PowerShell, Icarus Verilog, and `vvp`. Run from the repository root:

```powershell
$rtl = (Get-ChildItem ./sources_1/new -Filter *.v | Sort-Object Name).FullName
$test = (Resolve-Path ./sim_1/new/tb_system.v).Path
$run = (New-Item -ItemType Directory -Force ./build/readme-sim).FullName
Copy-Item ./sources_1/new/puyo_supervisor.mem $run
$out = Join-Path $run 'tb_system.vvp'
iverilog -g2012 -Wall -DSIMULATION -s tb_system -o $out $rtl $test
if ($LASTEXITCODE -ne 0) { throw 'Compilation failed' }
Push-Location $run
try {
    vvp $out
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
} finally {
    Pop-Location
}
```

The ROM is copied into the run directory because `$readmemh` resolves its filename relative to the simulator's working directory. `SIMULATION` selects the portable clock model; it must remain unset for FPGA synthesis.

The test checks:

- Supervisor boot, instruction retirement, and CPU-issued game start.
- Button-to-MMIO-to-CPU command delivery, including opposing directions.
- A single rotation while the button remains held.
- Pair locking and agreement between the NEXT preview and the next spawned pair.
- Restart without repetition while SW14 remains held, followed by rearming after release.
- Board, score, and chain clearing on restart, plus activity in CPU counters.

Assertions use `$fatal` on failure and print `PASS tb_system` on completion. The test accelerates millisecond-based behavior through parameter overrides; its elapsed simulation time is not a measurement of board responsiveness.

## Coverage limits

The integration test does not exhaustively test the CPU ISA, game-engine search cases, input timing boundaries, or a full VGA frame. Standalone tests for those modules are absent here. Simulation logs, implementation reports, a bitstream, and physical-board measurements are also absent.

The available ROM image supports running the supervisor, but its assembly source and image generator are not included. The [integration reference](INTEGRATION.md#supervisor-rom) lists the eight decoded instructions.

## FPGA checks

Build with the [README setup](../README.md#fpga-setup). Inspect the generated clock report for the 25 MHz system clock, then review setup, hold, pulse-width, unconstrained-path, RAM-utilization, and DRC reports. Confirm that instruction and data arrays map as intended and that the board top has no extra asynchronous memory-debug ports.

The XDC's input clock is 100 MHz; the CPU and VGA run on its divided 25 MHz MMCM output. Do not infer the CPU frequency from the oscillator alone. A timing report applies to the selected device, constraints, source revision, and routed design.

After loading a bitstream, check monitor lock, reset release, every control, repeated game restarts, NEXT behavior, clearing and chains, and sustained play. Power reports are estimates unless supported by an explicit activity model or physical measurements.
