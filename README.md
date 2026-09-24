#Systolic Array Matrix Accelerator

This is a hardware accelerator for matrix multiplication, built as a weight-stationary systolic array of signed MAC units. It's parameterized for array size (10×10 by default, feed length 50), with 16-bit operands and 40-bit accumulators. Input skew and output deskew are handled in hardware.

To run it on a real system, I attached it to a multicycle RISC-V CPU I wrote from scratch. The CPU has a custom MATR instruction (opcode 1111111). When the CPU decodes MATR, it hands the memory bus to the accelerator. The accelerator then:

loads the operand matrices from main memory, starting at the address in rs1
loads the weights into the array
streams the input data through the array
writes the result matrix back to memory
It then hands the bus back to the CPU.

Accelerator (SystemVerilog): matr_top.sv (top level), matr_ctrl.sv (control FSM), matr_ram.sv (local buffer and memory transfers), two_d.sv / one_d.sv (array), mac.sv (processing element)
Host CPU (Verilog): top.v, mod_main_ctrl.v, alu.v, alu_ctrl.v, imm_gen.v, reg_file.v, instr_reg.v, pc.v, mem.v. It supports lw, sw, beq, add, sub, and, or, mul and MATR.
