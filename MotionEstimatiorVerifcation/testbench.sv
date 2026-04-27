`timescale 1ns/1ps

// ================================================================
// Author: Eriberto Salgado
// Description:
// This is a testbench for the `top` module. It drives the design,
// loads reference/search memory from files, and runs different
// test scenarios (perfect match, partial match, random).
// It monitors outputs like BestDist and motion vectors and
// checks if the DUT behaves as expected.
// ================================================================

module top_testbench;

  // Outputs from DUT / connections between modules
  wire [7:0] BestDist;
  wire [3:0] motionX, motionY;
  wire [7:0] AddressR;
  wire [9:0] AddressS1, AddressS2;
  wire [7:0] R, S1, S2;
  wire completed;

  // Inputs driven by testbench
  reg clock;
  reg start;

  // General purpose variables
  integer i;
  integer signed x, y;   // used to convert motion vectors to signed values
  integer test_mode;     // selects which test to run

  // Instantiate DUT
  top dut (
    .clock(clock),
    .start(start),
    .BestDist(BestDist),
    .motionX(motionX),
    .motionY(motionY),
    .AddressR(AddressR),
    .AddressS1(AddressS1),
    .AddressS2(AddressS2),
    .R(R),
    .S1(S1),
    .S2(S2),
    .completed(completed)
  );

  // Reference memory (16x16 block)
  ROM_R memR_u (
    .clock(clock),
    .AddressR(AddressR),
    .R(R)
  );

  // Search memory (32x32 block)
  ROM_S memS_u (
    .clock(clock),
    .AddressS1(AddressS1),
    .AddressS2(AddressS2),
    .S1(S1),
    .S2(S2)
  );

  // Simple clock generator (20ns period)
  always #10 clock = ~clock;

  // ---------------------------------------------------------------
  // Copy a 16x16 block from search memory into reference memory
  // This is used to create a "perfect match" scenario
  // ---------------------------------------------------------------
  task make_ref_from_search;
    input integer top_row;   // valid range: 0..16
    input integer left_col;  // valid range: 0..16
    integer r, c;
    integer s_idx, r_idx;
    begin
      // Make sure requested block is within bounds
      if (top_row < 0 || top_row > 16 || left_col < 0 || left_col > 16) begin
        $display("ERROR: make_ref_from_search out of range. top_row=%0d left_col=%0d",
                 top_row, left_col);
        $finish;
      end

      // Copy 16x16 block from search (32x32) into reference (16x16)
      for (r = 0; r < 16; r = r + 1) begin
        for (c = 0; c < 16; c = c + 1) begin
          s_idx = (top_row + r) * 32 + (left_col + c); // index in search memory
          r_idx = r * 16 + c;                         // index in reference memory
          memR_u.Rmem[r_idx] = memS_u.Smem[s_idx];
        end
      end

      $display("Reference copied from Search block: top_row=%0d left_col=%0d",
               top_row, left_col);
    end
  endtask

  // ---------------------------------------------------------------
  // Select test behavior
  // 0 = perfect match
  // 1 = slightly modified match
  // 2 = completely random reference
  // ---------------------------------------------------------------
  task apply_test_mode;
    begin
      case (test_mode)
        0: begin
          $display("Running PERFECT MATCH test from search memory.");
          make_ref_from_search(8, 7);   // pick a valid block
        end

        1: begin
          $display("Running PARTIAL / PERTURBED MATCH test.");
          make_ref_from_search(8, 7);

          // introduce small changes to a few pixels
          memR_u.Rmem[1]   = memR_u.Rmem[1]   + 8'd1;
          memR_u.Rmem[20]  = memR_u.Rmem[20]  + 8'd2;
          memR_u.Rmem[55]  = memR_u.Rmem[55]  + 8'd1;
          memR_u.Rmem[100] = memR_u.Rmem[100] + 8'd3;
        end

        2: begin
          $display("Running NO-INTENDED-MATCH test.");
          // fill reference memory with random values
          foreach (memR_u.Rmem[i]) begin
            memR_u.Rmem[i] = $urandom_range(0,255);
          end
        end

        default: begin
          $display("Unknown test_mode. Using perfect match.");
          make_ref_from_search(8, 7);
        end
      endcase
    end
  endtask

  // ---------------------------------------------------------------
  // Dump both memories to console (for debugging)
  // ---------------------------------------------------------------
  task print_memories;
    integer row, col;
    begin
      $display("");
      $display("Reference Memory content:");
      for (row = 0; row < 256; row = row + 16) begin
        for (col = 0; col < 16; col = col + 1) begin
          $write("%02h ", memR_u.Rmem[row + col]);
        end
        $write("\n");
      end

      $display("");
      $display("Search Memory content:");
      for (row = 0; row < 1024; row = row + 32) begin
        for (col = 0; col < 32; col = col + 1) begin
          $write("%02h ", memS_u.Smem[row + col]);
        end
        $write("\n");
      end
      $display("");
    end
  endtask

  // ---------------------------------------------------------------
  // Main simulation flow
  // ---------------------------------------------------------------
  initial begin
    // waveform dump for GTKWave
    $dumpfile("dump.vcd");
    $dumpvars(0, clock);
    $dumpvars(0, start);
    $dumpvars(0, BestDist);
    $dumpvars(0, motionX);
    $dumpvars(0, motionY);
    $dumpvars(0, completed);
    $dumpvars(0, AddressR);
    $dumpvars(0, AddressS1);
    $dumpvars(0, AddressS2);
    $dumpvars(0, R);
    $dumpvars(0, S1);
    $dumpvars(0, S2);
    $dumpvars(0, dut.ctl_u.count); // internal counter (useful for debug)

    // initialize signals
    clock = 0;
    start = 0;

    // choose test case here
    //test_mode = 0;
    //test_mode = 1;
    test_mode = 2;

    // load memory contents from files
    $readmemh("search.txt", memS_u.Smem);
    $readmemh("ref.txt", memR_u.Rmem);

    // apply selected test mode (may overwrite ref memory)
    apply_test_mode();

    // print contents to console
    print_memories();

    // dump memories to files for inspection
    $writememh("search_dump.txt", memS_u.Smem);
    $writememh("ref_randomized.txt", memR_u.Rmem);

    $display("Starting simulation...");

    // wait one clock, then assert start
    @(posedge clock);
    #1 start = 1'b1;

    // run simulation loop
    for (i = 0; i < 5000; i = i + 1) begin
      @(posedge clock);
      #1;

      // print status every 100 cycles
      if ((i % 100) == 0) begin
        $display("cycle=%0d BestDist=%h motionX=%h motionY=%h count=%0d completed=%b",
                 i, BestDist, motionX, motionY, dut.ctl_u.count, completed);
      end

      // stop when DUT finishes
      if (completed) begin
        $display("Completed at cycle %0d", i);
        start = 1'b0;

        // convert 4-bit values to signed (-8 to +7)
        if (motionX >= 8) x = motionX - 16;
        else              x = motionX;

        if (motionY >= 8) y = motionY - 16;
        else              y = motionY;

        // print final results
        $display("");
        $display("===== FINAL RESULT =====");
        $display("BestDist = %0d (0x%0h)", BestDist, BestDist);
        $display("motionX  = %0d", x);
        $display("motionY  = %0d", y);
        $display("completed = %b", completed);
        $display("========================");

        // simple pass/fail checks
        case (test_mode)
          0: begin
            if (BestDist == 8'h00)
              $display("PASS: perfect-match style test produced zero distortion.");
            else
              $display("FAIL: expected zero distortion for perfect-match file test.");
          end

          1: begin
            if (BestDist != 8'h00 && BestDist != 8'hFF)
              $display("PASS: partial-match style test produced non-zero distortion.");
            else
              $display("FAIL: partial-match test did not produce a useful non-zero BestDist.");
          end

          2: begin
            if (BestDist != 8'h00)
              $display("PASS: no-intended-match test produced non-zero distortion.");
            else
              $display("FAIL: no-intended-match test unexpectedly produced zero distortion.");
          end
        endcase

        #20;
        $finish;
      end
    end

    // if we get here, DUT never finished
    $display("Timeout: completed never asserted.");
    $finish;
  end

endmodule
