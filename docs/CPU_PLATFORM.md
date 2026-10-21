# CPU and memory platform

[TD8_RISCV_V31_Core](../sources_1/new/TD8_RISCV_V31_Core.v) is a five-stage RV32I core with synchronous instruction and data memories. Its stages are IF, ID, EX, MEM, and WB. It includes EX/MEM and MEM/WB forwarding, a WB-to-ID bypass, load-use bubbles, and control-transfer resolution in EX.

The core derives from [TD8_To_RISCV_v3-pipeline](https://github.com/y0sh120040803-cpu/TD8_To_RISCV_v3-pipeline), revision `e8b9219f745e60d78dfa04ccef3416b58ad2efd9`. The `V31` module name identifies the synchronous-memory interface.

## Address spaces

| Space | Address | Storage or interface |
|---|---|---|
| Instruction | `0x00000000`–`0x00003fff` | 4096 x 32-bit synchronous ROM |
| Data | `0x00000000`–`0x000000ff` | Alias of the first 256 bytes of data RAM |
| Data | `0x00000100` | Legacy input, aligned `LW` only |
| Data | `0x00000104` | Legacy eight-bit output/readback, aligned `LW` / `SW` |
| Data | `0x00001000`–`0x00001fff` | 1024 x 32-bit synchronous RAM |
| Data | `0x00002000`–`0x000020ff` | External MMIO, aligned `LW` / `SW` |

Instruction and data memories are separate. Data addresses `0x00` and `0x1000` refer to the same physical RAM word, as do bytes `0xff` and `0x10ff`. RAM supports little-endian byte, halfword, and word accesses. Misaligned and unassigned data accesses trap before a memory request is issued.

[PipelineMemoryV31.v](../sources_1/new/PipelineMemoryV31.v) supplies the synchronous-memory templates. Data RAM has four byte write enables. Arrays are initialized at configuration time but have no runtime reset. Unused instruction locations contain NOPs. The optional asynchronous memory-debug port is disabled in the board top because it changes the inference requirements.

## Memory transactions

Instruction fetch and MEM-stage access each use a response token. The entire pipeline advances only when both required responses are available.

1. With `fetch_done=0`, one enabled rising edge reads instruction ROM and marks the response available.
2. A valid MEM-stage load or store issues once while `mem_done=0`. RAM accesses complete on that rising edge. External MMIO completes on an edge with `mmio_valid && mmio_ready`.
3. The response is held until the pipeline advances. Instructions that do not need a memory access require no MEM response.
4. An enabled edge with `fetch_done && mem_complete && !fault` advances the pipeline and clears the response tokens.

The memory-read edge and the pipeline-advance edge are separate. Even an independent instruction stream therefore has a basic pipeline advance interval of two physical clocks. A load-use bubble adds a logical pipeline step to this schedule.

`mem_done` prevents a completed store or MMIO read from being issued again while other stages wait. Peripheral side effects must occur only on a rising edge with both `valid` and `ready` asserted.

`cpu_enable=0` stops new requests and retirement while retaining completed responses. MMIO valid is withdrawn during a pause, so this interface requires acceptance on the shared valid/ready edge; it is not a bus with separate request and response phases. The game top holds `cpu_enable` high.

## Branches and traps

A branch, jump, or EX-stage exception waits for older MEM work to complete before the pipeline advances. The redirect flushes younger work and discards the previous fetch response. The next request uses the updated PC.

Exceptions travel to WB as ordered tokens. Older instructions finish before the core latches the fault and stops. `ECALL`, `EBREAK`, illegal instructions, and invalid fetch/data addresses have distinct diagnostic causes. The design has no privileged CSRs, interrupts, exception vector, or trap return. `FENCE` is a no-op in the ordered memory system.

## Reset

CPU control state, the PC, pipeline registers, and register-file validity bits use synchronous reset. The register arrays retain their physical contents; invalid registers read as zero and `x0` is always zero. Data RAM also retains its contents.

At board level, SW15 or MMCM unlock asserts reset asynchronously through `ResetSync`. Release takes three system-clock edges, followed by an additional register before reset reaches the CPU. This keeps the CPU's BRAM control signals in the system-clock domain. A reused core requires synchronous reset, enable, and MMIO response signals.

A game restart is a command to `PuyoEngine`, not a CPU or RAM reset.

## Performance counters

All counters are 32 bits, clear on CPU reset, and wrap on overflow.

| Signal | Meaning |
|---|---|
| `counter_cycle` | Physical clocks after reset, including pause and fault cycles |
| `counter_instret` | Normally retired instructions; excludes faulting instructions |
| `counter_mem_stall` | Enabled, non-faulted cycles waiting for a required IF or MEM response |
| `counter_load_stall` | Load-use bubbles inserted when the pipeline advances |
| `counter_flush` | Redirect or EX-exception flush events |

Memory stalls include instruction-fetch wait time. Flushes count events, not discarded instructions. For a selected program interval, `CPI = delta(cycle) / delta(instret)` and execution time is `delta(cycle) / clock_frequency`.

The [integration reference](INTEGRATION.md) gives the MMIO counter addresses and supervisor program. [VALIDATION.md](VALIDATION.md) describes the test available in this checkout.
