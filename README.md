# Systolic Array Matrix Accelerator (on a custom RISC-V CPU)

A hardware accelerator for matrix multiplication, built as a **weight-stationary systolic array** in SystemVerilog. To run it inside a real system, I attached it to a **multicycle RISC-V CPU I wrote from scratch** in Verilog. The CPU gets a custom `MATR` instruction: when it decodes `MATR`, it hands the memory bus to the accelerator. The accelerator pulls the matrices out of main memory, multiplies them in the array, writes the result back, and returns control to the CPU.

The focus of this project is the accelerator. The CPU is the host that feeds it.

---

## Highlights

- **Weight-stationary systolic array** made of signed multiply-accumulate (MAC) processing elements
- **Fully parameterized** array size, operand width and accumulator width (default: 10×10 array, 16-bit operands, 40-bit accumulators)
- **Input skew and output deskew in hardware**, so data goes in and comes out as plain row-major matrices
- **Self-contained control FSM** that moves data from main memory → local buffer → array → buffer → main memory
- **Custom ISA extension** (`MATR`, opcode `1111111`) that shares the CPU's memory bus with the accelerator

---

## Architecture

```
        ┌──────────────────────── RISC-V CPU (top.v) ────────────────────────┐
        │                                                                    │
        │   PC ─► Memory ─► IR ─► Reg File ─► ALU        main_ctrl FSM       │
        │            ▲                                  (MATR_WAIT state)    │
        │            │  address / data / enable muxes          │ matrGrant   │
        │            │  (switched to the accelerator           ▼             │
        │            │   while matrGrant is high)   ┌──────────────────────┐ │
        │            └──────────────────────────────┤  matr_top            │ │
        │                                           │  ├─ matr_ctrl (FSM)  │ │
        │                                           │  ├─ matr_ram (buffer)│ │
        │                                           │  └─ two_d (array)    │ │
        │                                           │      └─ one_d (row)  │ │
        │                                           │          └─ mac (PE) │ │
        │                                           └──────────────────────┘ │
        └────────────────────────────────────────────────────────────────────┘
```

### The systolic array (`two_d.sv`, `one_d.sv`, `mac.sv`)

- **`mac.sv`**: one processing element. It holds a stationary weight. Every cycle it multiplies the incoming activation by that weight, adds the product to the partial sum coming from above, and passes the activation along to its neighbour.
- **`one_d.sv`**: one row of the array. A shift-register "feeder" streams one row of the input matrix into the row of MACs.
- **`two_d.sv`**: the full 2-D array.
  - The partial-sum inputs of the top row are tied to zero.
  - Each row's load/shift control signals are delayed one cycle more than the row above. This makes the diagonal *input skew* a systolic array needs.
  - Each output column goes through a delay chain of a different length (*deskew*), so all columns of a result row come out on the same cycle.
  - A cycle counter raises `complete` once the last result has left the array.

### Accelerator control (`matr_top.sv`, `matr_ctrl.sv`, `matr_ram.sv`)

- **`matr_top.sv`**: the accelerator's top level. It connects the controller, buffer and array, and exposes a simple memory-master interface to the CPU.
- **`matr_ctrl.sv`**: the job FSM:

  ```
  RESET → IDLE → LOAD_RAM → LOAD_SYS_ARR → START_SYS_ARR → WAIT_SYS_ARR
        → UNLOAD_SYS_ARR → WRITE_TO_MAIN_MEM → UNREQUEST_GRANT → RESET
  ```

- **`matr_ram.sv`**: a local buffer. It:
  - burst-reads the operands from main memory
  - wires the weights and feed data into the array
  - drives the feed-shift timing during computation
  - collects the results and writes them back to main memory

### Host CPU (`top.v` and friends)

A multicycle, non-pipelined RV32 subset with a shared instruction/data memory.

| File | Purpose |
|---|---|
| `top.v` | CPU datapath. Also instantiates the accelerator and the memory-bus muxes |
| `mod_main_ctrl.v` | Multicycle control FSM, including the `MATR_WAIT` state that grants the bus to the accelerator |
| `alu.v` / `alu_ctrl.v` | ALU (add, sub, and, or, mul) and its decoder |
| `imm_gen.v` | Immediate generator (I, S and B formats) |
| `reg_file.v` | 32 × 32-bit register file (`x0` hard-wired to 0) |
| `instr_reg.v` | Instruction register and field decode |
| `pc.v` | Program counter |
| `mem.v` | 2048-word (8 KB) synchronous main memory |

**Supported instructions:** `lw`, `sw`, `beq`, `add`, `sub`, `and`, `or`, `mul`, and the custom `MATR`.

---

## Using the `MATR` instruction

`MATR` uses opcode `1111111` (`0x7F`). The only operand it reads is **`rs1`**, which holds the **byte address** of the operand block in main memory.

With the default parameters (`ARR_ROWS = K = 10`, `ARR_COLS = M = 10`, `FEED_LEN = N = 50`), the accelerator computes **C = A × B**, where A is M×K, B is K×N and C is M×N.

### Memory layout

Every element takes one 32-bit word. For inputs, only the low `DATA_W` (16) bits are used.

| Word offset from `rs1` | Contents |
|---|---|
| `0` … `M·K − 1` | **A** (the weights), row-major: `A[m][k]` at word `m·K + k` |
| `M·K` … `M·K + K·N − 1` | **B** (the streamed inputs), row-major: `B[k][n]` at word `M·K + k·N + n` |

When the job is done, **C** is written back **starting at `rs1`**, row-major, `C[m][n]` at word `m·N + n`. It overwrites the input block. Each result is the low 32 bits of the 40-bit accumulator.

### What happens when `MATR` executes

1. The CPU fetches and decodes `MATR`, then enters `MATR_WAIT`. It raises `matrGrant` and switches the memory address, data and enable muxes over to the accelerator.
2. The accelerator reads `M·K + K·N` words from main memory into its local buffer.
3. The weights are loaded into the MACs and the input rows are loaded into the feeders.
4. The input rows are shifted through the array (skewed), and the results are deskewed and captured.
5. The results are unloaded into the buffer and written back to main memory.
6. The accelerator raises `unrequest_grant`. The CPU gives up the bus and goes back to `FETCH`.

---

## Parameters

Set on `matr_top`:

| Parameter | Default | Meaning |
|---|---|---|
| `ARR_ROWS` | 10 | Array rows = inner dimension K (columns of A, rows of B) |
| `ARR_COLS` | 10 | Array columns = M (rows of A and C) |
| `FEED_LEN` | 50 | Feed length = N (columns of B and C) |
| `DATA_W` | 16 | Signed operand width |
| `ACC_W` | 40 | Accumulator width |

---

## Limitations

- Matrix dimensions are fixed when the design is built (by parameters). They are not set at runtime.
- The result overwrites the input block in memory. Results wider than 32 bits are truncated when they are written back.
- The CPU implements only the small subset of RV32I/M listed above. It has no `addi`, jumps or CSRs.
- `mem.v` has no built-in program loading. Preload it from your testbench, for example with `$readmemh`.

---

## Credits

The systolic array design, especially the weight-stationary dataflow and the way inputs are skewed through the array, was inspired by this article:

**[Systolic Architectures (telesens.co)](https://telesens.co/2018/07/30/systolic-architectures/)**

Many thanks to its author for such a clear explanation.
