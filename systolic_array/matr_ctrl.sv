module matr_ctrl(
    input logic clk,
    input logic reset,
    input logic matr_grant,
    output logic unrequest_grant,
    output logic sys_arr_reset,
    input logic calc_complete,
    output logic ram_reset,
    input logic ram_loaded,
    input logic sys_arr_loaded,
    input logic unload_sys_arr_complete,
    input logic main_mem_write_complete,
    output logic begin_load_ram,
    output logic begin_load_sys_arr,
    output logic start_sys_arr,
    output logic unload_sys_arr,
    output logic write_to_main_mem,
    output logic wait_sys_arr
);
//FSM state encodings
localparam logic [3:0] RESET             = 4'd0;
localparam logic [3:0] IDLE              = 4'd1;
localparam logic [3:0] LOAD_RAM          = 4'd2;
localparam logic [3:0] LOAD_SYS_ARR      = 4'd3;
localparam logic [3:0] START_SYS_ARR     = 4'd4;
localparam logic [3:0] WAIT_SYS_ARR      = 4'd5;
localparam logic [3:0] UNLOAD_SYS_ARR    = 4'd6;
localparam logic [3:0] WRITE_TO_MAIN_MEM = 4'd7;
localparam logic [3:0] UNREQUEST_GRANT   = 4'd8;
logic [3:0] state, next_state;

//Main ctrl FSM of sys. arr.
always_ff @ (posedge clk) begin
    if(reset) state <= RESET;
    else state <= next_state;
end
always_comb begin
    next_state = state; //default: stay in the current state
    case (state)
        RESET: next_state = IDLE;
        IDLE: if(matr_grant) next_state = LOAD_RAM;
        LOAD_RAM: if(ram_loaded) next_state = LOAD_SYS_ARR;
        LOAD_SYS_ARR: if(sys_arr_loaded) next_state = START_SYS_ARR;
        START_SYS_ARR: next_state = WAIT_SYS_ARR;
        WAIT_SYS_ARR: if(calc_complete) next_state = UNLOAD_SYS_ARR;
        UNLOAD_SYS_ARR: if(unload_sys_arr_complete) next_state = WRITE_TO_MAIN_MEM;
        WRITE_TO_MAIN_MEM: if(main_mem_write_complete) next_state = UNREQUEST_GRANT;
        UNREQUEST_GRANT: next_state = RESET;
        default: next_state = RESET;
    endcase
end
always_comb begin
    //defaults: every output is 0 unless the current state sets it
    ram_reset = 0;
    sys_arr_reset = 0;
    begin_load_ram = 0;
    begin_load_sys_arr = 0;
    start_sys_arr = 0;
    unload_sys_arr = 0;
    write_to_main_mem = 0;
    unrequest_grant = 0;
    wait_sys_arr = 0;
    case(state)
        RESET: begin
            ram_reset = 1;
            sys_arr_reset = 1;
        end
        IDLE: ;
        LOAD_RAM: begin_load_ram = 1;
        LOAD_SYS_ARR: begin_load_sys_arr = 1;
        START_SYS_ARR: start_sys_arr = 1;
        WAIT_SYS_ARR: wait_sys_arr = 1;
        UNLOAD_SYS_ARR: unload_sys_arr = 1;
        WRITE_TO_MAIN_MEM: write_to_main_mem = 1;
        UNREQUEST_GRANT: unrequest_grant = 1;
        default: begin
            ram_reset = 0;
            sys_arr_reset = 0;
            begin_load_ram = 0;
            begin_load_sys_arr = 0;
            start_sys_arr = 0;
            unload_sys_arr = 0;
            write_to_main_mem = 0;
            unrequest_grant = 0;
            wait_sys_arr = 0;
        end
    endcase
end
endmodule
