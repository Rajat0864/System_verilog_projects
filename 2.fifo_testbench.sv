`timescale 1ns/1ps

interface fifo_if #(parameter int DATA_WIDTH = 8, parameter int DEPTH = 16) (input logic clk);
  logic                    rst_n;
  logic                    wr_en;
  logic                    rd_en;
  logic [DATA_WIDTH-1:0]   wr_data;
  logic [DATA_WIDTH-1:0]   rd_data;
  logic                    full;
  logic                    empty;
  logic [$clog2(DEPTH):0]  count;

  clocking drv_cb @(posedge clk);
    default input #1ns output #1ns;
    output rst_n, wr_en, rd_en, wr_data;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1ns;
    input  rst_n, wr_en, rd_en, wr_data, rd_data, full, empty, count;
  endclocking

  modport DUT (
    input  clk, rst_n, wr_en, rd_en, wr_data,
    output rd_data, full, empty, count
  );

  modport DRV (clocking drv_cb);
  modport MON (clocking mon_cb);
endinterface

class fifo_item #(parameter int DATA_WIDTH = 8);
  rand bit                  wr_en;
  rand bit                  rd_en;
  rand bit [DATA_WIDTH-1:0] wr_data;

  constraint c_wr { wr_en dist {1 := 60, 0 := 40}; }
  constraint c_rd { rd_en dist {1 := 40, 0 := 60}; }

  function new(bit w = 0, bit r = 0, bit [DATA_WIDTH-1:0] d = '0);
    this.wr_en   = w;
    this.rd_en   = r;
    this.wr_data = d;
  endfunction
endclass

class fifo_driver #(parameter int DATA_WIDTH = 8, parameter int DEPTH = 16);
  virtual fifo_if #(DATA_WIDTH, DEPTH).DRV vif;

  function new(virtual fifo_if #(DATA_WIDTH, DEPTH).DRV vif);
    this.vif = vif;
  endfunction

  task reset_dut();
    vif.drv_cb.wr_en   <= 0;
    vif.drv_cb.rd_en   <= 0;
    vif.drv_cb.wr_data <= '0;
    vif.drv_cb.rst_n   <= 0;
    repeat (3) @(vif.drv_cb);
    vif.drv_cb.rst_n   <= 1;
    @(vif.drv_cb);
  endtask

  task drive(bit w, bit r, logic [DATA_WIDTH-1:0] d = '0);
    @(vif.drv_cb);
    vif.drv_cb.wr_en   <= w;
    vif.drv_cb.rd_en   <= r;
    vif.drv_cb.wr_data <= d;
  endtask

  task idle(int n = 1);
    repeat (n) drive(0, 0, '0);
  endtask
endclass

class fifo_scoreboard #(parameter int DATA_WIDTH = 8, parameter int DEPTH = 16);
  virtual fifo_if #(DATA_WIDTH, DEPTH).MON vif;
  logic [DATA_WIDTH-1:0] model_q[$];
  logic [DATA_WIDTH-1:0] exp_data;
  bit                    exp_valid;
  int                    errors = 0;
  int                    checks = 0;

  function new(virtual fifo_if #(DATA_WIDTH, DEPTH).MON vif);
    this.vif = vif;
  endfunction

  task reset_model();
    model_q.delete();
    exp_valid = 0;
  endtask

  task check_cycle();
    @(vif.mon_cb);

    if (exp_valid) begin
      checks++;
      if (vif.mon_cb.rd_data !== exp_data) begin
        errors++;
        $error("[%0t] READ MISMATCH: got %h, expected %h", $time, vif.mon_cb.rd_data, exp_data);
      end
      exp_valid = 0;
    end

    checks += 3;
    if (vif.mon_cb.count !== model_q.size()) begin
      errors++;
      $error("[%0t] COUNT MISMATCH: got %0d, expected %0d", $time, vif.mon_cb.count, model_q.size());
    end
    if (vif.mon_cb.full !== (model_q.size() == DEPTH)) begin
      errors++;
      $error("[%0t] FULL FLAG MISMATCH: got %b, expected %b", $time, vif.mon_cb.full, (model_q.size() == DEPTH));
    end
    if (vif.mon_cb.empty !== (model_q.size() == 0)) begin
      errors++;
      $error("[%0t] EMPTY FLAG MISMATCH: got %b, expected %b", $time, vif.mon_cb.empty, (model_q.size() == 0));
    end

    begin
      bit do_wr, do_rd;
      do_wr = vif.mon_cb.wr_en && (model_q.size() < DEPTH);
      do_rd = vif.mon_cb.rd_en && (model_q.size() > 0);

      if (do_rd) begin
        exp_data  = model_q.pop_front();
        exp_valid = 1;
      end
      if (do_wr) begin
        model_q.push_back(vif.mon_cb.wr_data);
      end
    end
  endtask
endclass

module sync_fifo_tb;
  localparam int DATA_WIDTH = 8;
  localparam int DEPTH      = 16;

  logic clk = 0;
  always #5 clk = ~clk;

  fifo_if #(DATA_WIDTH, DEPTH) vif (clk);

  sync_fifo #(DATA_WIDTH, DEPTH) dut (
    .clk     (vif.clk),
    .rst_n   (vif.rst_n),
    .wr_en   (vif.wr_en),
    .rd_en   (vif.rd_en),
    .wr_data (vif.wr_data),
    .rd_data (vif.rd_data),
    .full    (vif.full),
    .empty   (vif.empty),
    .count   (vif.count)
  );

  fifo_driver     #(DATA_WIDTH, DEPTH) drv;
  fifo_scoreboard #(DATA_WIDTH, DEPTH) scb;

  initial begin
    wait (vif.rst_n === 1'b1);
    forever scb.check_cycle();
  end

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end

  initial begin
    $display("=== Starting FIFO Verification ===");

    drv = new(vif.DRV);
    scb = new(vif.MON);

    drv.reset_dut();
    scb.reset_model();

    drv.idle(2);
    assert (vif.empty && !vif.full && vif.count == 0)
      else $error("Reset failed: empty=%b, full=%b, count=%0d", vif.empty, vif.full, vif.count);

    $display("Test 2: Full capacity and overflow protection");
    for (int i = 0; i < DEPTH; i++) drv.drive(1, 0, 8'h10 + i);
    drv.idle(1);
    for (int i = 0; i < 4; i++)     drv.drive(1, 0, 8'hEE);
    drv.idle(1);

    $display("Test 3: Empty drain and underflow protection");
    for (int i = 0; i < DEPTH; i++) drv.drive(0, 1, '0);
    drv.idle(1);
    for (int i = 0; i < 4; i++)     drv.drive(0, 1, '0);
    drv.idle(1);

    $display("Test 4: Simultaneous read/write");
    for (int i = 0; i < DEPTH/2; i++) drv.drive(1, 0, 8'hA0 + i);
    for (int i = 0; i < 30; i++)      drv.drive(1, 1, 8'h50 + i);
    drv.idle(1);
    for (int i = 0; i < DEPTH/2; i++) drv.drive(0, 1, '0);
    drv.idle(2);

    $display("Test 5: Constrained-random traffic (2000 cycles)");
    repeat (2000) begin
      fifo_item #(DATA_WIDTH) tr = new();
      assert(tr.randomize());
      drv.drive(tr.wr_en, tr.rd_en, tr.wr_data);
    end
    drv.idle(5);

    $display("==================================================");
    $display("Checks performed : %0d", scb.checks);
    $display("Errors detected  : %0d", scb.errors);
    if (scb.errors == 0)
      $display("TEST RESULT: PASSED");
    else
      $display("TEST RESULT: FAILED");
    $display("==================================================");

    $finish;
  end

  initial begin
    #2_000_000;
    $display("[TIMEOUT] Simulation reached max runtime limit.");
    $finish;
  end

endmodule
