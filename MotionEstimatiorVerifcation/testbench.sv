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

endinterface


module top_testbench;

  top_if intf();

  integer i;
  integer signed x, y;
  integer test_mode;

  integer rand_top_row;
  integer rand_left_col;

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

  ROM_R memR_u (
    .clock    (intf.clock),
    .AddressR (intf.AddressR),
    .R        (intf.R)
  );

  ROM_S memS_u (
    .clock    (intf.clock),
    .AddressS1(intf.AddressS1),
    .AddressS2(intf.AddressS2),
    .S1       (intf.S1),
    .S2       (intf.S2)
  );

  always #10 intf.clock = ~intf.clock;

  task make_ref_from_search;
    input integer top_row;   // valid range: 0..16
    input integer left_col;  // valid range: 0..16
    integer r, c;
    integer s_idx, r_idx;
    begin
      if (top_row < 0 || top_row > 16 || left_col < 0 || left_col > 16) begin
        $display("ERROR: make_ref_from_search out of range. top_row=%0d left_col=%0d",
                 top_row, left_col);
        $finish;
      end

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

  task apply_test_mode;
    begin
      rand_top_row  = $urandom % 17;
      rand_left_col = $urandom % 17;

      case (test_mode)
        0: begin
          $display("Running PERFECT MATCH test from random search memory block.");
          make_ref_from_search(rand_top_row, rand_left_col);
        end

        1: begin
          $display("Running PARTIAL / PERTURBED MATCH test from random search memory block.");
          make_ref_from_search(rand_top_row, rand_left_col);

          memR_u.Rmem[1]   = memR_u.Rmem[1]   + 8'd3;
          memR_u.Rmem[20]  = memR_u.Rmem[20]  + 8'd4;
          memR_u.Rmem[55]  = memR_u.Rmem[55]  + 8'd5;
          memR_u.Rmem[100] = memR_u.Rmem[100] + 8'd6;
        end

        2: begin
          $display("Running NO-INTENDED-MATCH test.");
          for (i = 0; i < 256; i = i + 1) begin
            memR_u.Rmem[i] = 8'hFF;
          end
        end

        default: begin
          $display("Unknown test_mode. Using random perfect match.");
          make_ref_from_search(rand_top_row, rand_left_col);
        end
      endcase
    end
  endtask

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

    //test_mode = 0;
    //test_mode = 1;
    test_mode = 2;

    $readmemh("search.txt", memS_u.Smem);
    $readmemh("ref.txt", memR_u.Rmem);

    apply_test_mode();

    print_memories();

    $writememh("search_dump.txt", memS_u.Smem);
    $writememh("ref_randomized.txt", memR_u.Rmem);

    $display("Starting simulation...");

    @(posedge intf.clock);
    #1 intf.start = 1'b1;

    for (i = 0; i < 5000; i = i + 1) begin
      @(posedge intf.clock);
      #1;

      if ((i % 100) == 0) begin
        $display("cycle=%0d BestDist=%h motionX=%h motionY=%h count=%0d completed=%b",
                 i, intf.BestDist, intf.motionX, intf.motionY, dut.ctl_u.count, intf.completed);
      end

      if (intf.completed) begin
        $display("Completed at cycle %0d", i);
        intf.start = 1'b0;

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

    $display("Timeout: completed never asserted.");
    $finish;
  end

endmodule
