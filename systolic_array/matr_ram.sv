module matr_ram #(
    parameter SYS_NODES_HEIGHT = 10, parameter SYS_NODES_WIDTH = 10,
    parameter SYS_FEED_HEIGHT  = 10, parameter SYS_FEED_WIDTH  = 50,
    parameter OUTPUT_HEIGHT    = 50, parameter OUTPUT_WIDTH    = 10,
    parameter RAM_SIZE = SYS_NODES_HEIGHT*SYS_NODES_WIDTH + SYS_FEED_HEIGHT*SYS_FEED_WIDTH,  // 600
    parameter RESULT_SIZE = OUTPUT_HEIGHT*OUTPUT_WIDTH,
    parameter CYCLES_NEEDED = SYS_NODES_WIDTH + SYS_FEED_WIDTH - 1 + SYS_NODES_HEIGHT,
    parameter DATA_W = 16, parameter ACC_W = 40
)(
    input logic clk,
    input logic reset,
    input logic [31:0]base_addr, //byte address of A in main memory (rs1 of MATR)
    output logic [31:0]main_mem_address_in,
    output logic [31:0]main_mem_data_in,
    input logic [31:0]main_mem_data_out,
    output logic main_mem_read_enable,
    output logic main_mem_write_enable,
    //connection to systolic array
    output logic [DATA_W-1:0] feed_in [SYS_FEED_HEIGHT - 1:0][SYS_FEED_WIDTH - 1:0],
    output logic [DATA_W-1:0] weight_in [SYS_NODES_HEIGHT - 1:0][SYS_NODES_WIDTH - 1:0],
    input logic [ACC_W-1:0] sys_arr_outputs [OUTPUT_HEIGHT - 1:0][OUTPUT_WIDTH - 1:0],
    output logic enable_feed_shift,
    output logic load_feed_enable,
    output logic weight_load_enable,
    //Connection to internal RAM
    input logic ram_reset,
    output logic ram_loaded,
    output logic sys_arr_loaded,
    output logic unload_sys_arr_complete,
    output logic main_mem_write_complete,
    input logic begin_load_ram,
    input logic begin_load_sys_arr,
    input logic start_sys_arr,
    input logic unload_sys_arr,
    input logic write_to_main_mem,
    input logic wait_sys_arr
);
//Memory for the RAM
// The buffer holds the operand block while loading and the result block while
// writing back, so it has to fit whichever of the two is larger. Sizing it from
// RAM_SIZE alone silently dropped the top result words whenever M*N > K*M + K*N.
localparam int MEM_DEPTH  = (RAM_SIZE > RESULT_SIZE) ? RAM_SIZE : RESULT_SIZE;
// addrFFs has to reach RAM_SIZE+2 (the burst-load terminator) and RESULT_SIZE
// (the write-back terminator). Sizing it $clog2(RAM_SIZE) wide made those
// comparisons unreachable whenever RAM_SIZE was a power of two, so ram_loaded
// never asserted and the accelerator held the bus forever.
localparam int ADDR_LIMIT = ((RAM_SIZE + 2) > RESULT_SIZE) ? (RAM_SIZE + 2) : RESULT_SIZE;
localparam int ADDR_W     = $clog2(ADDR_LIMIT + 1);
logic [31:0]memory[0:MEM_DEPTH-1];
logic [ADDR_W-1:0] addrFFs;
logic [ADDR_W-1:0] prev_addrFFs;
logic [ADDR_W-1:0] prev_prev_addrFFs;
logic [$clog2(CYCLES_NEEDED + 1)-1:0]sys_arr_wait_counter;
always_ff @ (posedge clk) begin
    if(reset | ram_reset) begin
        addrFFs <= 0;
        prev_addrFFs <= 0;
        prev_prev_addrFFs <= 0;
        sys_arr_wait_counter <= 0;
        main_mem_address_in <= 0;
        main_mem_data_in <= 0;
        main_mem_read_enable <= 0;
        main_mem_write_enable <= 0;
        enable_feed_shift <= 0;
        load_feed_enable <= 0;
        weight_load_enable <= 0;
        ram_loaded <= 0;
        sys_arr_loaded <= 0;
        unload_sys_arr_complete <= 0;
        main_mem_write_complete <= 0;
    end
    else begin
        //Load RAM and prime weight/feed-in
        if (begin_load_ram & (addrFFs != RAM_SIZE + 1 + 1) & !ram_loaded) begin
            main_mem_read_enable <= 1;
            addrFFs <= addrFFs + 1;
            prev_addrFFs <= addrFFs;
            prev_prev_addrFFs <= prev_addrFFs;
            memory[prev_prev_addrFFs] <= main_mem_data_out;
            main_mem_address_in <= base_addr + {addrFFs, 2'b00}; //address is multiplied by 4 to account for the 32 bit words
        end
        else if(addrFFs == RAM_SIZE + 1 + 1) begin
            addrFFs <= 0;
            ram_loaded <= 1;
            main_mem_read_enable <= 0;
        end
        if (begin_load_sys_arr & (addrFFs != RAM_SIZE)) begin
            sys_arr_loaded <= 1;
        end
        //Load feed/weights
        load_feed_enable   <= 0;
        weight_load_enable <= 0;
        if(start_sys_arr) begin
            load_feed_enable <= 1;
            weight_load_enable <= 1;
            sys_arr_loaded <= 1;
            sys_arr_wait_counter <= 0;
            unload_sys_arr_complete <= 0;
        end
        //wait for sys arr to calcualate
        if(wait_sys_arr) begin
            sys_arr_wait_counter <= sys_arr_wait_counter + 1;
            if(sys_arr_wait_counter < SYS_FEED_WIDTH) enable_feed_shift <= 1;
            else enable_feed_shift <= 0; //ie sys_wait_counter is between FEED_WIDTH - 1 and CYCLES NEEDED
        end
        //unload the systolic array results back into the buffer
        if(unload_sys_arr & !unload_sys_arr_complete) begin
            for (int t = 0; t < OUTPUT_HEIGHT; t++)
                for (int m = 0; m < OUTPUT_WIDTH; m++)
                    memory[m*OUTPUT_HEIGHT + (OUTPUT_HEIGHT-1-t)] <= sys_arr_outputs[t][m][31:0];
            unload_sys_arr_complete <= 1;
        end
        if(write_to_main_mem & (addrFFs != RESULT_SIZE)) begin
            main_mem_write_enable <= 1;
            addrFFs <= addrFFs + 1;
            main_mem_data_in <= memory[addrFFs];
            main_mem_address_in <= base_addr + {addrFFs, 2'b00};
        end
        else if(write_to_main_mem & (addrFFs == RESULT_SIZE)) begin
            main_mem_write_complete <= 1;
            main_mem_write_enable <= 0;
        end
    end
end
// memory -> array ports, wired combinationally (no extra flip-flops)
always_comb begin
    // weights: array row k, column m holds W[m][k]
    for (int k = 0; k < SYS_NODES_HEIGHT; k++)
        for (int m = 0; m < SYS_NODES_WIDTH; m++)
            weight_in[k][m] = memory[m*SYS_NODES_HEIGHT + k][DATA_W-1:0];
    // feed: array row k gets row k of the activations, reversed
    for (int k = 0; k < SYS_FEED_HEIGHT; k++)
        for (int j = 0; j < SYS_FEED_WIDTH; j++)
            feed_in[k][SYS_FEED_WIDTH-1-j] = memory[SYS_NODES_HEIGHT*SYS_NODES_WIDTH + k*SYS_FEED_WIDTH + j][DATA_W-1:0];
end
endmodule
