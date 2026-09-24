module mac #(parameter DATA_W = 16, ACC_W = 40)(
    input logic signed [ACC_W-1:0] sum_in,
    output logic signed [ACC_W-1:0] sum_out,
    input logic signed [DATA_W-1:0] a_in,
    output logic signed [DATA_W-1:0] a_out,
    input logic signed [DATA_W-1:0] weight_in,
    input logic weight_load_enable,
    input logic clk,
    input logic reset
);
logic signed [DATA_W-1:0] weight;
logic signed [2*DATA_W-1:0] product;
assign product = a_in * weight; //computing this here so it doesnt not get inflated into a 72 x 72 multiplier in the FF
always_ff @(posedge clk) begin
    if(reset) begin
        weight <= 0;
        sum_out <= 0;
        a_out <= 0;
    end
    else begin
        if(weight_load_enable) weight <= weight_in;
        else begin
            sum_out <= sum_in + product;
            a_out <= a_in;
        end
    end
end
endmodule
