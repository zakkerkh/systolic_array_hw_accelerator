module two_d
    #(parameter MAT_A_HEIGHT = 3, SYS_NODES_WIDTH = MAT_A_HEIGHT,
    MAT_A_WIDTH = 3, SYS_NODES_HEIGHT = MAT_A_WIDTH,
    MAT_B_HEIGHT = 3, SYS_FEED_HEIGHT = MAT_B_HEIGHT,
    MAT_B_WIDTH = 3, SYS_FEED_WIDTH = MAT_B_WIDTH,
    OUTPUT_HEIGHT = MAT_B_WIDTH,
    OUTPUT_WIDTH = MAT_A_HEIGHT,
    DATA_W = 16, ACC_W = 40)( 
    input logic clk,
    input logic reset,
    input logic enable_feed_shift,
    input logic load_feed_enable,
    input logic [DATA_W-1:0] feed_in [SYS_FEED_HEIGHT - 1:0][SYS_FEED_WIDTH - 1:0],
    input logic weight_load_enable,
    input logic [DATA_W-1:0] weight_in [SYS_NODES_HEIGHT - 1:0][SYS_NODES_WIDTH - 1:0],
    output logic [ACC_W-1:0] outputs [OUTPUT_HEIGHT - 1:0][OUTPUT_WIDTH - 1:0],
    output logic complete
);
logic [DATA_W-1:0] feed [SYS_FEED_HEIGHT - 1:0][SYS_FEED_WIDTH - 1:0];
logic [DATA_W-1:0] activation_net [SYS_NODES_HEIGHT:0][SYS_NODES_WIDTH:0];
logic [ACC_W-1:0] sum_net [SYS_NODES_HEIGHT:0][SYS_NODES_WIDTH - 1:0];
// row 0 has no row above it, so its sum_in boundary must be tied to 0.
// Leaving it undriven floats in synthesis and reads X in a 4-state
// simulator, corrupting every column's accumulation.
genvar zc;
generate
    for (zc = 0; zc < SYS_NODES_WIDTH; zc++) begin : gen_zero_boundary
        assign sum_net[0][zc] = '0;
    end
endgenerate

logic load_skew_stage   [SYS_NODES_HEIGHT-1:0];
logic enable_skew_stage [SYS_NODES_HEIGHT-1:0];
genvar k;
generate
    for (k = 0; k < SYS_NODES_HEIGHT - 1; k++) begin : gen_skew
        always_ff @(posedge clk) begin
            if (reset) begin
                load_skew_stage[k]   <= 1'b0;
                enable_skew_stage[k] <= 1'b0;
            end else if (k == 0) begin
                load_skew_stage[k]   <= load_feed_enable;
                enable_skew_stage[k] <= enable_feed_shift;
            end else begin
                load_skew_stage[k]   <= load_skew_stage[k-1];
                enable_skew_stage[k] <= enable_skew_stage[k-1];
            end
        end
    end
endgenerate

//one_d instatiations
genvar i;
generate
for(i = 0; i < SYS_NODES_HEIGHT; i++) begin : gen_label
    one_d #(.MAT_A_HEIGHT(MAT_A_HEIGHT), .MAT_A_WIDTH(MAT_A_WIDTH),
            .MAT_B_HEIGHT(MAT_B_HEIGHT), .MAT_B_WIDTH(MAT_B_WIDTH),
            .DATA_W(DATA_W), .ACC_W(ACC_W)) row(
            .clk(clk),
            .reset(reset),
            .weight_load_enable(weight_load_enable),
            .feed_in(feed_in[i]), //each feed represents one row in of the feed the sys diagram from the website
            .enable_feed_shift(i == 0 ? enable_feed_shift : enable_skew_stage[(i == 0) ? 0 : i-1]), //index clamped: never -1, same behaviour
            .load_feed_enable(i == 0 ? load_feed_enable : load_skew_stage[(i == 0) ? 0 : i-1]), //index clamped: never -1, same behaviour
            .feed(feed[i]),
            .activation_net(activation_net[i]),
            .sum_in(sum_net[i]),
            .sum_out(sum_net[i + 1]),
            .weight_in(weight_in[i])
            );
end
endgenerate

logic [ACC_W-1:0] col_deskew  [SYS_NODES_WIDTH - 1:0][SYS_NODES_WIDTH - 1:0]; // [col][stage]
logic [ACC_W-1:0] aligned_sum [SYS_NODES_WIDTH - 1:0];
genvar dc, ds;
generate
for (dc = 0; dc < SYS_NODES_WIDTH; dc = dc + 1) begin : gen_deskew_col
    localparam int DELAY = SYS_NODES_WIDTH - 1 - dc;
    if (DELAY == 0) begin : gen_no_delay
        assign aligned_sum[dc] = sum_net[SYS_NODES_HEIGHT][dc];
    end else begin : gen_delay_chain
        for (ds = 0; ds < DELAY; ds = ds + 1) begin : gen_stage
            always_ff @(posedge clk) begin
                if (reset)
                    col_deskew[dc][ds] <= '0;
                else if (ds == 0)
                    col_deskew[dc][ds] <= sum_net[SYS_NODES_HEIGHT][dc];
                else
                    col_deskew[dc][ds] <= col_deskew[dc][ds-1];
            end
        end
        assign aligned_sum[dc] = col_deskew[dc][DELAY-1];
    end
end
endgenerate

//output (the final matrix result)
parameter CYCLES_NEEDED = SYS_NODES_WIDTH + SYS_FEED_WIDTH - 1 + SYS_NODES_HEIGHT;
logic [$clog2(CYCLES_NEEDED + 1)-1:0]cycle_count;
assign complete = (CYCLES_NEEDED == cycle_count);
logic capture_active;
always_ff @ (posedge clk) begin
    if(reset) begin
        cycle_count <=0;
        capture_active <= 1'b0;
         for(int i = 0; i < OUTPUT_HEIGHT; i++) begin
            for(int j = 0; j < OUTPUT_WIDTH; j++) begin
                outputs[i][j] <= 0;
            end
         end
    end
    else if(load_feed_enable) begin
        cycle_count <= 0;
        capture_active <= 1'b1;
    end
    else if(capture_active && !complete) begin 
        cycle_count <= cycle_count + 1;
        outputs[0] <= aligned_sum;
        for(int i = 0; i < OUTPUT_HEIGHT - 1; i++) outputs[i + 1] <= outputs[i];
    end
end
endmodule
