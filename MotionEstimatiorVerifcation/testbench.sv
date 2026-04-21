`timescale 1ns/1ps

module top_testbench;

  wire [7:0] BestDist;
  wire [3:0] motionX, motionY;
  wire [7:0] AddressR;
  wire [9:0] AddressS1, AddressS2;
  wire [7:0] R, S1, S2;
  wire completed;

  reg clock;
  reg start;

  integer i;
  integer signed x, y;
  integer test_mode;

  // 0 = perfect using files as-is
  // 1 = partial by perturbing reference after file load
  // 2 = no-intended-match by replacing reference with random data

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

  ROM_R memR_u (
    .clock(clock),
    .AddressR(AddressR),
    .R(R)
  );

  ROM_S memS_u (
    .clock(clock),
    .AddressS1(AddressS1),
    .AddressS2(AddressS2),
    .S1(S1),
    .S2(S2)
  );

  always #10 clock = ~clock;

  task apply_test_mode;
    begin
      case (test_mode)
        0: begin
          $display("Running PERFECT MATCH test from files.");
        end

        1: begin
          $display("Running PARTIAL / PERTURBED MATCH test.");

          // perturbations
          memR_u.Rmem[1]   = memR_u.Rmem[1]   + 8'd1;
          memR_u.Rmem[20]  = memR_u.Rmem[20]  + 8'd2;
          memR_u.Rmem[55]  = memR_u.Rmem[55]  + 8'd1;
          memR_u.Rmem[100] = memR_u.Rmem[100] + 8'd3;
        end

        2: begin
          $display("Running NO-INTENDED-MATCH test.");
          foreach (memR_u.Rmem[i]) begin
            memR_u.Rmem[i] = $urandom_range(0,255);
          end
        end

        default: begin
          $display("Unknown test_mode. Using perfect match.");
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
    $dumpvars(0, dut.ctl_u.count);

    clock = 0;
    start = 0;

    // choose one
    test_mode = 0;
    //test_mode = 1;
    //test_mode = 2;

    $readmemh("ref.txt", memR_u.Rmem);
    $readmemh("search.txt", memS_u.Smem);

    apply_test_mode();

    // print memories after loading/modification
    print_memories();

    // dump after modification
    $writememh("search_dump.txt", memS_u.Smem);
    $writememh("ref_randomized.txt", memR_u.Rmem);

    $display("Starting simulation...");

    @(posedge clock);
    #1 start = 1'b1;

    for (i = 0; i < 5000; i = i + 1) begin
      @(posedge clock);
      #1;

      if ((i % 100) == 0) begin
        $display("cycle=%0d BestDist=%h motionX=%h motionY=%h count=%0d completed=%b",
                 i, BestDist, motionX, motionY, dut.ctl_u.count, completed);
      end

      if (completed) begin
        $display("Completed at cycle %0d", i);
        start = 1'b0;

        if (motionX >= 8) x = motionX - 16;
        else              x = motionX;

        if (motionY >= 8) y = motionY - 16;
        else              y = motionY;

        $display("");
        $display("===== FINAL RESULT =====");
        $display("BestDist = %0d (0x%0h)", BestDist, BestDist);
        $display("motionX  = %0d", x);
        $display("motionY  = %0d", y);
        $display("completed = %b", completed);
        $display("========================");

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

    $display("Timeout: completed never asserted.");
    $finish;
  end

endmodule
