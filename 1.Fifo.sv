module top_module #(
  parameter int DATA_WIDTH = 8,
  parameter int DEPTH      = 64
)(
  input  logic                         clk,
  input  logic                         rst,
  input  logic                         w_e,
  input  logic                         r_e,
  input  logic [DATA_WIDTH-1:0]        buf_in,
  output logic [DATA_WIDTH-1:0]        buf_out,
  output logic                         buf_empty,
  output logic                         buf_full,
  output logic [$clog2(DEPTH):0]       fifo_counter,
  output logic [$clog2(DEPTH)-1:0]     wr_ptr,
  output logic [$clog2(DEPTH)-1:0]     rd_ptr
);

  logic [DATA_WIDTH-1:0] buf_mem [DEPTH];

  assign buf_empty = (fifo_counter == 0);
  assign buf_full  = (fifo_counter == DEPTH);

  logic do_wr, do_rd;
  assign do_wr = w_e && !buf_full;
  assign do_rd = r_e && !buf_empty;

  always_ff @(posedge clk or posedge rst) begin
    if (rst)
      fifo_counter <= '0;
    else begin
      unique case ({do_wr, do_rd})
        2'b10:   fifo_counter <= fifo_counter + 1'b1;
        2'b01:   fifo_counter <= fifo_counter - 1'b1;
        default: fifo_counter <= fifo_counter;
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (do_wr)
      buf_mem[wr_ptr] <= buf_in;
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst)
      buf_out <= '0;
    else if (do_rd)
      buf_out <= buf_mem[rd_ptr];
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
    end else begin
      if (do_wr) wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1'b1;
      if (do_rd) rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1'b1;
    end
  end

endmodule
