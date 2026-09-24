module one_d
    #(parameter MAT_A_HEIGHT = 3, SYS_NODES_WIDTH = MAT_A_HEIGHT,
    MAT_A_WIDTH = 3, SYS_NODES_HEIGHT = MAT_A_WIDTH,
    MAT_B_HEIGHT = 3, SYS_FEED_HEIGHT = MAT_B_HEIGHT,
    MAT_B_WIDTH = 3, SYS_FEED_WIDTH = MAT_B_WIDTH,
    DATA_W = 16, ACC_W = 40)(
    input logic clk,
    input logic reset,
    input logic weight_load_enable,
    input logic [DATA_W-1:0] feed_in [SYS_FEED_WIDTH - 1:0],
    input logic enable_feed_shift,
    input logic load_feed_enable,
    output logic [DATA_W-1:0] feed [SYS_FEED_WIDTH - 1:0],
    output logic [DATA_W-1:0] activation_net [SYS_NODES_WIDTH :0],
    input logic [ACC_W-1:0] sum_in[SYS_NODES_WIDTH - 1:0],
    output logic [ACC_W-1:0] sum_out[SYS_NODES_WIDTH - 1:0],
    input logic [DATA_W-1:0] weight_in[SYS_NODES_WIDTH - 1:0]
);
//shift reg / feeder
always_ff @ (posedge clk) begin
    if(reset) begin
        for(int i = 0; i < SYS_FEED_WIDTH; i++) feed[i] <= 0;
    end
    else if (load_feed_enable) feed <= feed_in;
    else if(enable_feed_shift) begin
        for(int i = 0; i < SYS_FEED_WIDTH - 1; i++) feed[i + 1] <= feed[i];
    end
end
assign activation_net[0] = feed[SYS_FEED_WIDTH - 1];
genvar i;
generate
for(i = 0; i < SYS_NODES_WIDTH; i++) begin : gen_label
    mac #(.DATA_W(DATA_W), .ACC_W(ACC_W)) propogation(.sum_in(sum_in[i]),
                .sum_out(sum_out[i]),
                .a_in(activation_net[i]),
                .a_out(activation_net[i + 1]),
                .weight_in(weight_in[i]),
                .weight_load_enable(weight_load_enable),
                .clk(clk),
                .reset(reset));
end
endgenerate
endmodule
