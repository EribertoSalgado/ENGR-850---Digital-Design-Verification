`timescale 1ns/1ps

interface top_if;

  logic [7:0] BestDist;
  logic [3:0] motionX, motionY;
  logic [7:0] AddressR;
  logic [9:0] AddressS1, AddressS2;
  logic [7:0] R, S1, S2;
  logic completed;

  logic clock;
  logic start;

  logic [7:0] Rmem[0:255];
  logic [7:0] Smem[0:1023];

  always_comb begin
    R  = Rmem[AddressR];
    S1 = Smem[AddressS1];
    S2 = Smem[AddressS2];
  end

endinterface


typedef enum int {
  TEST_PERFECT   = 0,
  TEST_PERTURBED = 1
} test_kind_e;


class motion_transaction;

  rand test_kind_e kind;
  rand int unsigned target_top_row;
  rand int unsigned target_left_col;
  rand int unsigned perturb_count;

  int unsigned id;
  byte unsigned ref_mem[0:255];
  byte unsigned search_mem[0:1023];

  int signed expected_motion_x;
  int signed expected_motion_y;
  bit [7:0] expected_best_dist;
  bit expected_motion_valid;

  logic [7:0] actual_best_dist;
  logic [3:0] actual_motion_x_raw;
  logic [3:0] actual_motion_y_raw;
  int signed actual_motion_x;
  int signed actual_motion_y;

  constraint legal_target_c {
    target_top_row  inside {[0:15]};
    target_left_col inside {[0:15]};
  }

  constraint useful_case_c {
    kind dist {
      TEST_PERTURBED := 4,
      TEST_PERFECT   := 1
    };
    perturb_count inside {[1:12]};
  }

  function new(int unsigned id = 0);
    this.id = id;
  endfunction

  function string kind_name();
    case (kind)
      TEST_PERFECT:   return "perfect";
      TEST_PERTURBED: return "perturbed";
      default:        return "unknown";
    endcase
  endfunction

  function void post_randomize();
    build_memories();
  endfunction

  function void build_memories();
    int tries;
    bit done;

    tries = 0;
    done = 0;

    while (!done && tries < 20) begin
      fill_search_memory();
      copy_target_to_reference();

      if (kind == TEST_PERTURBED) begin
        perturb_reference();
      end

      compute_expected();

      done = (kind == TEST_PERFECT && expected_best_dist == 8'd0) ||
             (kind == TEST_PERTURBED && expected_best_dist != 8'd0 &&
                                      expected_best_dist != 8'hff);
      tries++;
    end
  endfunction

  function void fill_search_memory();
    int i;

    for (i = 0; i < 1024; i++) begin
      search_mem[i] = $urandom_range(0, 255);
    end
  endfunction

  function void copy_target_to_reference();
    int row, col;
    int s_idx, r_idx;

    for (row = 0; row < 16; row++) begin
      for (col = 0; col < 16; col++) begin
        s_idx = (target_top_row + row) * 32 + (target_left_col + col);
        r_idx = row * 16 + col;
        ref_mem[r_idx] = search_mem[s_idx];
      end
    end
  endfunction

  function void perturb_reference();
    int k;
    int idx;
    int attempts;
    int max_delta;
    byte unsigned delta;

    for (k = 0; k < perturb_count; k++) begin
      attempts = 0;

      do begin
        idx = $urandom_range(0, 255);
        attempts++;
      end
      while (ref_mem[idx] > 8'd243 && attempts < 64);

      max_delta = 255 - ref_mem[idx];
      if (max_delta > 12) begin
        max_delta = 12;
      end

      if (max_delta >= 1) begin
        delta = $urandom_range(1, max_delta);
        ref_mem[idx] = ref_mem[idx] + delta;
      end
      else begin
        delta = $urandom_range(1, 12);
        ref_mem[idx] = ref_mem[idx] - delta;
      end
    end
  endfunction

  function int unsigned sad_for_candidate(int unsigned top_row,
                                          int unsigned left_col);
    int row, col;
    int s_idx, r_idx;
    int diff;
    int unsigned acc;

    acc = 0;

    for (row = 0; row < 16; row++) begin
      for (col = 0; col < 16; col++) begin
        s_idx = (top_row + row) * 32 + (left_col + col);
        r_idx = row * 16 + col;

        if (ref_mem[r_idx] > search_mem[s_idx]) begin
          diff = ref_mem[r_idx] - search_mem[s_idx];
        end
        else begin
          diff = search_mem[s_idx] - ref_mem[r_idx];
        end

        if ((acc + diff) >= 255) begin
          acc = 255;
        end
        else begin
          acc = acc + diff;
        end
      end
    end

    return acc;
  endfunction

  function void compute_expected();
    int unsigned row, col;
    int unsigned dist_val;
    int unsigned best;

    best = 255;
    expected_motion_valid = 0;
    expected_motion_x = 0;
    expected_motion_y = 0;

    for (row = 0; row < 16; row++) begin
      for (col = 0; col < 16; col++) begin
        dist_val = sad_for_candidate(row, col);

        if (dist_val < best) begin
          best = dist_val;
          expected_motion_x = int'(col) - 8;
          expected_motion_y = int'(row) - 8;
          expected_motion_valid = (dist_val != 255);
        end
      end
    end

    expected_best_dist = best[7:0];
  endfunction

endclass


class motion_generator;

  mailbox #(motion_transaction) gen_to_drv;
  int unsigned num_random_tests;
  int unsigned sent_count;

  function new(mailbox #(motion_transaction) gen_to_drv,
               int unsigned num_random_tests = 64);
    this.gen_to_drv = gen_to_drv;
    this.num_random_tests = num_random_tests;
    this.sent_count = 0;
  endfunction

  task run();
    send_directed(TEST_PERFECT,   0,  0);
    send_directed(TEST_PERTURBED, 0,  0);
    send_directed(TEST_PERTURBED, 0,  15);
    send_directed(TEST_PERTURBED, 15, 0);
    send_directed(TEST_PERTURBED, 15, 15);
    send_directed(TEST_PERTURBED, 8,  8);
    send_directed(TEST_PERTURBED, 8,  0);
    send_directed(TEST_PERTURBED, 0,  8);
    send_directed(TEST_PERTURBED, 15, 8);
    send_directed(TEST_PERTURBED, 8,  15);
    send_directed(TEST_PERTURBED, 4,  4);
    send_directed(TEST_PERTURBED, 4,  12);
    send_directed(TEST_PERTURBED, 12, 4);
    send_directed(TEST_PERTURBED, 12, 12);
    send_random();
  endtask

  task send_directed(test_kind_e kind,
                     int unsigned top_row,
                     int unsigned left_col);
    motion_transaction tr;

    tr = new(sent_count);
    tr.kind = kind;
    tr.target_top_row = top_row;
    tr.target_left_col = left_col;
    tr.perturb_count = 4;
    tr.build_memories();

    gen_to_drv.put(tr);
    sent_count++;
  endtask

  task send_random();
    motion_transaction tr;
    int unsigned i;

    for (i = 0; i < num_random_tests; i++) begin
      tr = new(sent_count);

      if (!tr.randomize()) begin
        $display("FATAL: transaction randomization failed for id=%0d", sent_count);
        $finish;
      end

      gen_to_drv.put(tr);
      sent_count++;
    end
  endtask

endclass


class motion_driver;

  virtual top_if vif;
  mailbox #(motion_transaction) gen_to_drv;
  mailbox #(motion_transaction) drv_to_mon;
  int unsigned num_tests;

  function new(virtual top_if vif,
               mailbox #(motion_transaction) gen_to_drv,
               mailbox #(motion_transaction) drv_to_mon,
               int unsigned num_tests);
    this.vif = vif;
    this.gen_to_drv = gen_to_drv;
    this.drv_to_mon = drv_to_mon;
    this.num_tests = num_tests;
  endfunction

  task run();
    motion_transaction tr;
    int unsigned i;

    vif.start = 1'b0;
    repeat (2) @(posedge vif.clock);

    for (i = 0; i < num_tests; i++) begin
      gen_to_drv.get(tr);
      load_memories(tr);

      $display("");
      $display("TEST %0d: kind=%s target_top=%0d target_left=%0d expected_dist=%0d expected_motion=(%0d,%0d)",
               tr.id, tr.kind_name(), tr.target_top_row, tr.target_left_col,
               tr.expected_best_dist, tr.expected_motion_x, tr.expected_motion_y);

      drv_to_mon.put(tr);
      start_dut();
      wait_for_done();
      stop_dut();
    end
  endtask

  task load_memories(motion_transaction tr);
    int i;

    for (i = 0; i < 256; i++) begin
      vif.Rmem[i] = tr.ref_mem[i];
    end

    for (i = 0; i < 1024; i++) begin
      vif.Smem[i] = tr.search_mem[i];
    end
  endtask

  task start_dut();
    @(posedge vif.clock);
    #1 vif.start = 1'b1;
  endtask

  task wait_for_done();
    int cycles;

    cycles = 0;
    while (vif.completed !== 1'b1 && cycles < 5000) begin
      @(posedge vif.clock);
      #1;
      cycles++;
    end

    if (cycles >= 5000) begin
      $display("FATAL: timeout waiting for completed");
      $finish;
    end
  endtask

  task stop_dut();
    #1 vif.start = 1'b0;
    repeat (2) @(posedge vif.clock);
  endtask

endclass


class motion_monitor;

  virtual top_if vif;
  mailbox #(motion_transaction) drv_to_mon;
  mailbox #(motion_transaction) mon_to_scb;
  int unsigned num_tests;

  function new(virtual top_if vif,
               mailbox #(motion_transaction) drv_to_mon,
               mailbox #(motion_transaction) mon_to_scb,
               int unsigned num_tests);
    this.vif = vif;
    this.drv_to_mon = drv_to_mon;
    this.mon_to_scb = mon_to_scb;
    this.num_tests = num_tests;
  endfunction

  task run();
    motion_transaction tr;
    int unsigned i;

    for (i = 0; i < num_tests; i++) begin
      drv_to_mon.get(tr);

      while (vif.completed !== 1'b1) begin
        @(posedge vif.clock);
        #1;
      end

      tr.actual_best_dist = vif.BestDist;
      tr.actual_motion_x_raw = vif.motionX;
      tr.actual_motion_y_raw = vif.motionY;
      tr.actual_motion_x = decode_motion(vif.motionX);
      tr.actual_motion_y = decode_motion(vif.motionY);

      mon_to_scb.put(tr);
    end
  endtask

  function int signed decode_motion(logic [3:0] value);
    if (value >= 4'd8) begin
      return int'(value) - 16;
    end

    return int'(value);
  endfunction

endclass


class motion_coverage;

  test_kind_e sampled_kind;
  int signed sampled_target_x;
  int signed sampled_target_y;
  int signed sampled_expected_x;
  int signed sampled_expected_y;
  int unsigned sampled_dist;
  bit sampled_motion_valid;

  covergroup motion_cg;
    option.per_instance = 1;

    kind_cp: coverpoint sampled_kind {
      bins perfect   = {TEST_PERFECT};
      bins perturbed = {TEST_PERTURBED};
    }

    target_x_cp: coverpoint sampled_target_x {
      bins left_edge  = {-8};
      bins left_mid   = {[-7:-1]};
      bins center     = {0};
      bins right_mid  = {[1:6]};
      bins right_edge = {7};
    }

    target_y_cp: coverpoint sampled_target_y {
      bins top_edge    = {-8};
      bins top_mid     = {[-7:-1]};
      bins center      = {0};
      bins bottom_mid  = {[1:6]};
      bins bottom_edge = {7};
    }

    expected_x_cp: coverpoint sampled_expected_x iff (sampled_motion_valid) {
      bins left_edge  = {-8};
      bins left_mid   = {[-7:-1]};
      bins center     = {0};
      bins right_mid  = {[1:6]};
      bins right_edge = {7};
    }

    expected_y_cp: coverpoint sampled_expected_y iff (sampled_motion_valid) {
      bins top_edge    = {-8};
      bins top_mid     = {[-7:-1]};
      bins center      = {0};
      bins bottom_mid  = {[1:6]};
      bins bottom_edge = {7};
    }

    dist_cp: coverpoint sampled_dist {
      bins zero    = {0};
      bins nonzero = {[1:254]};
    }
  endgroup

  function new();
    motion_cg = new();
  endfunction

  function void sample(motion_transaction tr);
    sampled_kind = tr.kind;
    sampled_target_x = int'(tr.target_left_col) - 8;
    sampled_target_y = int'(tr.target_top_row) - 8;
    sampled_expected_x = tr.expected_motion_x;
    sampled_expected_y = tr.expected_motion_y;
    sampled_dist = tr.expected_best_dist;
    sampled_motion_valid = tr.expected_motion_valid;
    motion_cg.sample();
  endfunction

  function real get_coverage();
    return motion_cg.get_coverage();
  endfunction

endclass


class motion_scoreboard;

  mailbox #(motion_transaction) mon_to_scb;
  motion_coverage cov;
  int unsigned num_tests;
  int unsigned pass_count;
  int unsigned fail_count;

  function new(mailbox #(motion_transaction) mon_to_scb,
               int unsigned num_tests);
    this.mon_to_scb = mon_to_scb;
    this.num_tests = num_tests;
    this.cov = new();
    this.pass_count = 0;
    this.fail_count = 0;
  endfunction

  task run();
    motion_transaction tr;
    int unsigned i;

    for (i = 0; i < num_tests; i++) begin
      mon_to_scb.get(tr);
      check(tr);
      cov.sample(tr);
    end

    $display("");
    $display("===== SCOREBOARD SUMMARY =====");
    $display("PASS count           = %0d", pass_count);
    $display("FAIL count           = %0d", fail_count);
    $display("Functional coverage  = %0.2f%%", cov.get_coverage());
    $display("==============================");

    if (fail_count != 0) begin
      $display("TESTBENCH RESULT: FAIL");
      $finish;
    end

    $display("TESTBENCH RESULT: PASS");
  endtask

  task check(motion_transaction tr);
    bit pass;

    pass = 1'b1;

    if (tr.actual_best_dist !== tr.expected_best_dist) begin
      pass = 1'b0;
      $display("FAIL id=%0d: BestDist actual=%0d expected=%0d",
               tr.id, tr.actual_best_dist, tr.expected_best_dist);
    end

    if (tr.expected_motion_valid) begin
      if (tr.actual_motion_x != tr.expected_motion_x ||
          tr.actual_motion_y != tr.expected_motion_y) begin
        pass = 1'b0;
        $display("FAIL id=%0d: motion actual=(%0d,%0d) expected=(%0d,%0d)",
                 tr.id, tr.actual_motion_x, tr.actual_motion_y,
                 tr.expected_motion_x, tr.expected_motion_y);
      end
    end
    else begin
      $display("INFO id=%0d: expected distortion saturated; motion vector is not checked",
               tr.id);
    end

    if (pass) begin
      pass_count++;
      $display("PASS id=%0d: BestDist=%0d motion=(%0d,%0d)",
               tr.id, tr.actual_best_dist, tr.actual_motion_x, tr.actual_motion_y);
    end
    else begin
      fail_count++;
    end
  endtask

endclass


class motion_environment;

  virtual top_if vif;
  mailbox #(motion_transaction) gen_to_drv;
  mailbox #(motion_transaction) drv_to_mon;
  mailbox #(motion_transaction) mon_to_scb;

  motion_generator gen;
  motion_driver drv;
  motion_monitor mon;
  motion_scoreboard scb;

  int unsigned num_random_tests;
  int unsigned num_directed_tests;
  int unsigned num_tests;

  function new(virtual top_if vif);
    this.vif = vif;
  endfunction

  task build();
    num_random_tests = 64;
    num_directed_tests = 14;

    if ($value$plusargs("NUM_RANDOM_TESTS=%d", num_random_tests)) begin
      $display("Using NUM_RANDOM_TESTS=%0d", num_random_tests);
    end

    num_tests = num_random_tests + num_directed_tests;

    gen_to_drv = new();
    drv_to_mon = new();
    mon_to_scb = new();

    gen = new(gen_to_drv, num_random_tests);
    drv = new(vif, gen_to_drv, drv_to_mon, num_tests);
    mon = new(vif, drv_to_mon, mon_to_scb, num_tests);
    scb = new(mon_to_scb, num_tests);
  endtask

  task run();
    fork
      gen.run();
      drv.run();
      mon.run();
      scb.run();
    join
  endtask

endclass


module top_testbench;

  top_if intf();
  motion_environment env;

  top dut (
    .clock     (intf.clock),
    .start     (intf.start),
    .BestDist  (intf.BestDist),
    .motionX   (intf.motionX),
    .motionY   (intf.motionY),
    .AddressR  (intf.AddressR),
    .AddressS1 (intf.AddressS1),
    .AddressS2 (intf.AddressS2),
    .R         (intf.R),
    .S1        (intf.S1),
    .S2        (intf.S2),
    .completed (intf.completed)
  );

  always #10 intf.clock = ~intf.clock;

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, intf.clock);
    $dumpvars(0, intf.start);
    $dumpvars(0, intf.BestDist);
    $dumpvars(0, intf.motionX);
    $dumpvars(0, intf.motionY);
    $dumpvars(0, intf.completed);
    $dumpvars(0, intf.AddressR);
    $dumpvars(0, intf.AddressS1);
    $dumpvars(0, intf.AddressS2);
    $dumpvars(0, intf.R);
    $dumpvars(0, intf.S1);
    $dumpvars(0, intf.S2);
    $dumpvars(0, dut.ctl_u.count);

    intf.clock = 1'b0;
    intf.start = 1'b0;

    env = new(intf);
    env.build();
    env.run();

    #20;
    $finish;
  end

endmodule
