`timescale 1ns/1ps

// ================================================================
// Author: Eriberto Salgado
// Description:
// This is a testbench for the `top` module. It drives the design,
// loads reference/search memory from files, and runs different
// test scenarios (perfect match, partial match, random).
// It monitors outputs like BestDist and motion vectors and
// checks if the DUT behaves as expected.
// This version also uses a SystemVerilog interface to group the
// DUT/testbench connection signals in one place.
// ================================================================


// ---------------------------------------------------------------
// Interface: bundles signals shared by testbench, DUT, and memories
// ---------------------------------------------------------------
interface motion_if;
  logic clock;
  logic start;

  logic [7:0] BestDist;
  logic [3:0] motionX, motionY;
  logic [7:0] AddressR;
  logic [9:0] AddressS1, AddressS2;
  logic [7:0] R, S1, S2;
  logic completed;
endinterface


module top_testbench;

  // Instantiate interface
  motion_if mif();

  // General purpose variables
  integer i;
  integer signed x, y;   // used to convert motion vectors to signed values
  integer test_mode;     // selects which test to run

  // Instantiate DUT using interface signals
  top dut (
    .clock(mif.clock),
    .start(mif.start),
    .BestDist(mif.BestDist),
    .motionX(mif.motionX),
    .motionY(mif.motionY),
    .AddressR(mif.AddressR),
    .AddressS1(mif.AddressS1),
    .AddressS2(mif.AddressS2),
    .R(mif.R),
    .S1(mif.S1),
    .S2(mif.S2),
    .completed(mif.completed)
  );

  // Reference memory (16x16 block)
  ROM_R memR_u (
    .clock(mif.clock),
    .AddressR(mif.AddressR),
    .R(mif.R)
  );

  // Search memory (32x32 block)
  ROM_S memS_u (
    .clock(mif.clock),
    .AddressS1(mif.AddressS1),
    .AddressS2(mif.AddressS2),
    .S1(mif.S1),
    .S2(mif.S2)
  );

  // Simple clock generator (20ns period)
  always #10 mif.clock = ~mif.clock;

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
          r_idx = r * 16 + c;                          // index in reference memory
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
          make_ref_from_search(8, 7);   // pick a valid block (row,column)
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
          $display("Running MAX-DISTORTION test (Ref = FF, Search = 00).");

          // Force reference block to all 0xFF
          foreach (memR_u.Rmem[i]) begin
            memR_u.Rmem[i] = 8'hFF;
          end

          // Optional but safer: force search to all 0x00
          foreach (memS_u.Smem[i]) begin
            memS_u.Smem[i] = 8'h00;
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
    $dumpvars(0, mif.clock);
    $dumpvars(0, mif.start);
    $dumpvars(0, mif.BestDist);
    $dumpvars(0, mif.motionX);
    $dumpvars(0, mif.motionY);
    $dumpvars(0, mif.completed);
    $dumpvars(0, mif.AddressR);
    $dumpvars(0, mif.AddressS1);
    $dumpvars(0, mif.AddressS2);
    $dumpvars(0, mif.R);
    $dumpvars(0, mif.S1);
    $dumpvars(0, mif.S2);
    $dumpvars(0, dut.ctl_u.count); // internal counter (useful for debug)

    // initialize signals
    mif.clock = 0;
    mif.start = 0;

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
    @(posedge mif.clock);
    #1 mif.start = 1'b1;

    // run simulation loop
    for (i = 0; i < 5000; i = i + 1) begin
      @(posedge mif.clock);
      #1;

      // print status every 100 cycles
      if ((i % 100) == 0) begin
        $display("cycle=%0d BestDist=%h motionX=%h motionY=%h count=%0d completed=%b",
                 i, mif.BestDist, mif.motionX, mif.motionY, dut.ctl_u.count, mif.completed);
      end

      // stop when DUT finishes
      if (mif.completed) begin
        $display("Completed at cycle %0d", i);
        mif.start = 1'b0;

        // convert 4-bit values to signed (-8 to +7)
        if (mif.motionX >= 8) x = mif.motionX - 16;
        else                  x = mif.motionX;

        if (mif.motionY >= 8) y = mif.motionY - 16;
        else                  y = mif.motionY;

        // print final results
        $display("");
        $display("===== FINAL RESULT =====");
        $display("BestDist = %0d (0x%0h)", mif.BestDist, mif.BestDist);
        $display("motionX  = %0d", x);
        $display("motionY  = %0d", y);
        $display("completed = %b", mif.completed);
        $display("========================");

        // simple pass/fail checks
        case (test_mode)
          0: begin
            if (mif.BestDist == 8'h00)
              $display("PASS: perfect-match style test produced zero distortion.");
            else
              $display("FAIL: expected zero distortion for perfect-match file test.");
          end

          1: begin
            if (mif.BestDist != 8'h00 && mif.BestDist != 8'hFF)
              $display("PASS: partial-match style test produced non-zero distortion.");
            else
              $display("FAIL: partial-match test did not produce a useful non-zero BestDist.");
          end

          2: begin
            if (mif.BestDist != 8'h00)
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
