
module matr_top #(
    parameter ARR_ROWS = 10,   // array rows    = inner dimension K (columns of A, rows of B)
    parameter ARR_COLS = 10,   // array columns = rows of A and of C
    parameter FEED_LEN = 50,   // feed length   = columns of B and of C
    parameter DATA_W   = 16,   // operand width
    parameter ACC_W    = 40    // sum width
)(
    //connection RISC-V CPU
    input  logic        clk,
    input  logic        reset,
    input  logic        matr_grant,
    output logic        unrequest_grant,
    input  logic [31:0] base_addr,              // byte address of A (register rs1 of the MATR instruction)
    //connection to main memory (selected by the muxes in mod_top while matr_grant is high)
    input  logic [31:0] main_mem_read,          // data coming out of main memory
    output logic [31:0] main_mem_write,         // data going into main memory
    output logic [31:0] main_mem_address,       // byte address
    output logic        main_mem_read_enable,
    output logic        main_mem_write_enable
);
// ctrl <-> ram handshakes
logic ram_reset, sys_arr_reset;
logic ram_loaded, sys_arr_loaded, unload_sys_arr_complete, main_mem_write_complete;
logic begin_load_ram, begin_load_sys_arr, start_sys_arr, unload_sys_arr, write_to_main_mem, wait_sys_arr;
// ram <-> array
logic [DATA_W-1:0] feed_in   [ARR_ROWS-1:0][FEED_LEN-1:0];
logic [DATA_W-1:0] weight_in [ARR_ROWS-1:0][ARR_COLS-1:0];
logic [ACC_W-1:0]  sys_arr_outputs [FEED_LEN-1:0][ARR_COLS-1:0];
logic enable_feed_shift, load_feed_enable, weight_load_enable;
logic sys_arr_complete;
matr_ctrl u_ctrl(
    .clk(clk),
    .reset(reset),
    .matr_grant(matr_grant),
    .unrequest_grant(unrequest_grant),
    .sys_arr_reset(sys_arr_reset),
    .calc_complete(sys_arr_complete),           // the array's own complete drives the FSM
    .ram_reset(ram_reset),
    .ram_loaded(ram_loaded),
    .sys_arr_loaded(sys_arr_loaded),
    .unload_sys_arr_complete(unload_sys_arr_complete),
    .main_mem_write_complete(main_mem_write_complete),
    .begin_load_ram(begin_load_ram),
    .begin_load_sys_arr(begin_load_sys_arr),
    .start_sys_arr(start_sys_arr),
    .unload_sys_arr(unload_sys_arr),
    .write_to_main_mem(write_to_main_mem),
    .wait_sys_arr(wait_sys_arr)
);
matr_ram #(
    .SYS_NODES_HEIGHT(ARR_ROWS), .SYS_NODES_WIDTH(ARR_COLS),
    .SYS_FEED_HEIGHT(ARR_ROWS),  .SYS_FEED_WIDTH(FEED_LEN),
    .OUTPUT_HEIGHT(FEED_LEN),    .OUTPUT_WIDTH(ARR_COLS),
    .DATA_W(DATA_W), .ACC_W(ACC_W)
) u_ram(
    .clk(clk),
    .reset(reset),
    .base_addr(base_addr),
    .main_mem_address_in(main_mem_address),
    .main_mem_data_in(main_mem_write),
    .main_mem_data_out(main_mem_read),
    .main_mem_read_enable(main_mem_read_enable),
    .main_mem_write_enable(main_mem_write_enable),
    .feed_in(feed_in),
    .weight_in(weight_in),
    .sys_arr_outputs(sys_arr_outputs),
    .enable_feed_shift(enable_feed_shift),
    .load_feed_enable(load_feed_enable),
    .weight_load_enable(weight_load_enable),
    .ram_reset(ram_reset),
    .ram_loaded(ram_loaded),
    .sys_arr_loaded(sys_arr_loaded),
    .unload_sys_arr_complete(unload_sys_arr_complete),
    .main_mem_write_complete(main_mem_write_complete),
    .begin_load_ram(begin_load_ram),
    .begin_load_sys_arr(begin_load_sys_arr),
    .start_sys_arr(start_sys_arr),
    .unload_sys_arr(unload_sys_arr),
    .write_to_main_mem(write_to_main_mem),
    .wait_sys_arr(wait_sys_arr)
);
two_d #(
    .MAT_A_HEIGHT(ARR_COLS), .MAT_A_WIDTH(ARR_ROWS),
    .MAT_B_HEIGHT(ARR_ROWS), .MAT_B_WIDTH(FEED_LEN),
    .DATA_W(DATA_W), .ACC_W(ACC_W)
) u_arr(
    .clk(clk),
    .reset(reset | sys_arr_reset),              // FSM's RESET state clears the stale complete between jobs
    .enable_feed_shift(enable_feed_shift),
    .load_feed_enable(load_feed_enable),
    .feed_in(feed_in),
    .weight_load_enable(weight_load_enable),
    .weight_in(weight_in),
    .outputs(sys_arr_outputs),
    .complete(sys_arr_complete)
);
endmodule
