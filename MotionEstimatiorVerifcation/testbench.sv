`timescale 1ns/1ps

// Simple interface to bundle DUT signals together
interface top_if;

  logic [7:0] BestDist;
  logic [3:0] motionX, motionY;
  logic [7:0] AddressR;
  logic [9:0] AddressS1, AddressS2;
  logic [7:0] R, S1, S2;
  logic completed;

  logic clock;
  logic start;

endinterface


module top_testbench;

  top_if intf();

  integer i;
  integer signed x, y;   // signed versions for motion output
  integer test_mode;

  integer rand_top_row;
  integer rand_left_col;

  // DUT hookup
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

  // Reference memory (16x16 block)
  ROM_R memR_u (
    .clock    (intf.clock),
    .AddressR (intf.AddressR),
    .R        (intf.R)
  );

  // Search memory (32x32 block)
  ROM_S memS_u (
    .clock    (intf.clock),
    .AddressS1(intf.AddressS1),
    .AddressS2(intf.AddressS2),
    .S1       (intf.S1),
    .S2       (intf.S2)
  );

  // 50MHz clock
  always #10 intf.clock = ~intf.clock;

  // Copy a 16x16 window from search memory into reference memory
  task make_ref_from_search;
    input integer top_row;   // must be 0..16
    input integer left_col;  // must be 0..16
    integer r, c;
    integer s_idx, r_idx;
    begin
      // basic bounds check so we don't walk off memory
      if (top_row < 0 || top_row > 16 || left_col < 0 || left_col > 16) begin
        $display("ERROR: make_ref_from_search out of range. top_row=%0d left_col=%0d",
                 top_row, left_col);
        $finish;
      end

      // map 16x16 window from 32x32 search into 16x16 reference
      for (r = 0; r < 16; r = r + 1) begin
        for (c = 0; c < 16; c = c + 1) begin
          s_idx = (top_row + r) * 32 + (left_col + c);
          r_idx = r * 16 + c;
          memR_u.Rmem[r_idx] = memS_u.Smem[s_idx];
        end
      end

      $display("Reference copied from Search block: top_row=%0d left_col=%0d",
               top_row, left_col);
    end
  endtask

  // Decide what kind of test we want to run
  task apply_test_mode;
    begin
      // pick a random valid starting point inside 32x32
      rand_top_row  = $urandom % 17; // random number from 0 to 16
      rand_left_col = $urandom % 17;

      case (test_mode)
        0: begin
          // exact match case: reference is copied directly from search
          $display("Running PERFECT MATCH test from random search memory block.");
          make_ref_from_search(rand_top_row, rand_left_col);
        end

        1: begin
          // mostly match, but tweak a few pixels
          $display("Running PARTIAL / PERTURBED MATCH test from random search memory block.");
          make_ref_from_search(rand_top_row, rand_left_col);

          memR_u.Rmem[1]   = memR_u.Rmem[1]   + 8'd3;
          memR_u.Rmem[20]  = memR_u.Rmem[20]  + 8'd4;
          memR_u.Rmem[55]  = memR_u.Rmem[55]  + 8'd5;
          memR_u.Rmem[100] = memR_u.Rmem[100] + 8'd6;
        end

        2: begin
          // completely different reference (should not match anything)
          $display("Running NO-INTENDED-MATCH test.");
          for (i = 0; i < 256; i = i + 1) begin
            memR_u.Rmem[i] = 8'hFF;
          end
        end

        default: begin
          // fallback if test_mode is garbage
          $display("Unknown test_mode. Using random perfect match.");
          make_ref_from_search(rand_top_row, rand_left_col);
        end
      endcase
    end
  endtask

  // Dump both memories so we can visually inspect them if needed
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

  initial begin
    // waveform dump for debugging
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

    intf.clock = 0;
    intf.start = 0;

    // pick which scenario to run
    //test_mode = 0;
    //test_mode = 1;
    test_mode = 2;

    // load initial memory contents from files
    $readmemh("search.txt", memS_u.Smem);
    $readmemh("ref.txt", memR_u.Rmem);

    apply_test_mode();

    print_memories();

    // dump out what we actually used
    $writememh("search_dump.txt", memS_u.Smem);
    $writememh("ref_randomized.txt", memR_u.Rmem);

    $display("Starting simulation...");

    // kick off DUT
    @(posedge intf.clock);
    #1 intf.start = 1'b1;

    // main simulation loop
    for (i = 0; i < 5000; i = i + 1) begin
      @(posedge intf.clock);
      #1;

      // print progress every 100 cycles
      if ((i % 100) == 0) begin
        $display("cycle=%0d BestDist=%h motionX=%h motionY=%h count=%0d completed=%b",
                 i, intf.BestDist, intf.motionX, intf.motionY, dut.ctl_u.count, intf.completed);
      end

      // stop when DUT says it's done
      if (intf.completed) begin
        $display("Completed at cycle %0d", i);
        intf.start = 1'b0;

        // convert 4-bit unsigned to signed (-8..7)
        if (intf.motionX >= 8) x = intf.motionX - 16;
        else                   x = intf.motionX;

        if (intf.motionY >= 8) y = intf.motionY - 16;
        else                   y = intf.motionY;

        $display("");
        $display("===== FINAL RESULT =====");
        $display("BestDist = %0d (0x%0h)", intf.BestDist, intf.BestDist);
        $display("motionX  = %0d", x);
        $display("motionY  = %0d", y);
        $display("completed = %b", intf.completed);
        $display("========================");

        // basic pass/fail checks per test type
        case (test_mode)
          0: begin
            if (intf.BestDist == 8'h00)
              $display("PASS: perfect-match style test produced zero distortion.");
            else
              $display("FAIL: expected zero distortion for perfect-match file test.");
          end

          1: begin
            if (intf.BestDist != 8'h00 && intf.BestDist != 8'hFF)
              $display("PASS: partial-match style test produced non-zero distortion.");
            else
              $display("FAIL: partial-match test did not produce a useful non-zero BestDist.");
          end

          2: begin
            if (intf.BestDist != 8'h00)
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
