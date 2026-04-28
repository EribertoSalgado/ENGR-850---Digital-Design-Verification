`timescale 1ns/1ps

/* Module For Top Level Hierarchy */
module top (
  input  wire        clock,
  input  wire        start,
  output wire [7:0]  BestDist,
  output wire [3:0]  motionX,
  output wire [3:0]  motionY,
  output wire [7:0]  AddressR,
  output wire [9:0]  AddressS1,
  output wire [9:0]  AddressS2,
  input  wire [7:0]  R,
  input  wire [7:0]  S1,
  input  wire [7:0]  S2,
  output wire        completed
);

  wire [15:0]  S1S2mux, newDist, PEready;
  wire         CompStart;
  wire [3:0]   VectorX, VectorY;
  wire [127:0] Accumulate;

  control ctl_u (
    .clock(clock),
    .start(start),
    .S1S2mux(S1S2mux),
    .newDist(newDist),
    .CompStart(CompStart),
    .PEready(PEready),
    .VectorX(VectorX),
    .VectorY(VectorY),
    .AddressR(AddressR),
    .AddressS1(AddressS1),
    .AddressS2(AddressS2),
    .completed(completed)
  );

  PEtotal pe_u (
    .clock(clock),
    .R(R),
    .S1(S1),
    .S2(S2),
    .S1S2mux(S1S2mux),
    .newDist(newDist),
    .Accumulate(Accumulate)
  );

  Comparator comp_u (
    .clock(clock),
    .CompStart(CompStart),
    .PEout(Accumulate),
    .PEready(PEready),
    .vectorX(VectorX),
    .vectorY(VectorY),
    .BestDist(BestDist),
    .motionX(motionX),
    .motionY(motionY)
  );

endmodule

/* Module For Processing Element (PE) */
module PE (
  input  wire       clock,
  input  wire [7:0] R,
  input  wire [7:0] S1,
  input  wire [7:0] S2,
  input  wire       S1S2mux,
  input  wire       newDist,
  output reg  [7:0] Accumulate,
  output reg  [7:0] Rpipe
);

  reg  [7:0] AccumulateIn;
  reg  [7:0] pixel_sel;
  reg  [7:0] difference;
  reg        Carry;

  always @(posedge clock) begin
    Rpipe      <= R;
    Accumulate <= AccumulateIn;
  end

  always @(*) begin
    pixel_sel = (S1S2mux ? S1 : S2);

    if (R >= pixel_sel)
      difference = R - pixel_sel;
    else
      difference = pixel_sel - R;

    {Carry, AccumulateIn} = Accumulate + difference;

    if (Carry)
      AccumulateIn = 8'hFF; // saturated

    if (newDist)
      AccumulateIn = difference;
  end

endmodule


/* Module For The Last Processing Element (PEend) */
module PEend (
  input  wire       clock,
  input  wire [7:0] R,
  input  wire [7:0] S1,
  input  wire [7:0] S2,
  input  wire       S1S2mux,
  input  wire       newDist,
  output reg  [7:0] Accumulate
);

  reg  [7:0] AccumulateIn;
  reg  [7:0] pixel_sel;
  reg  [7:0] difference;
  reg        Carry;

  always @(posedge clock) begin
    Accumulate <= AccumulateIn;
  end

  always @(*) begin
    pixel_sel = (S1S2mux ? S1 : S2);

    if (R >= pixel_sel)
      difference = R - pixel_sel;
    else
      difference = pixel_sel - R;

    {Carry, AccumulateIn} = Accumulate + difference;

    if (Carry)
      AccumulateIn = 8'hFF; // saturated

    if (newDist)
      AccumulateIn = difference;
  end

endmodule


/* Module For Control Unit */
module control (
  input  wire        clock,
  input  wire        start,
  output reg  [15:0] S1S2mux,
  output reg  [15:0] newDist,
  output reg         CompStart,
  output reg  [15:0] PEready,
  output reg  [3:0]  VectorX,
  output reg  [3:0]  VectorY,
  output reg  [7:0]  AddressR,
  output reg  [9:0]  AddressS1,
  output reg  [9:0]  AddressS2,
  output reg         completed
);

  parameter count_complete = 16*(16*16) + 15; // 4111

  reg [12:0] count, count_temp;
  reg [11:0] temp;
  integer i;

  always @(posedge clock) begin
    if (start == 1'b0)
      count <= 13'b0;
    else if (completed == 1'b0)
      count <= count_temp;
  end

  always @(*) begin
    count_temp = count + 13'b1;

    for (i = 0; i < 16; i = i + 1) begin
      newDist[i] = (count[7:0] == i[7:0]);
      PEready[i] = (newDist[i] && !(count < 13'd256));
      S1S2mux[i] = (count[3:0] >= i[3:0]);
    end

    CompStart = !(count < 13'd256);

    AddressR  = count[7:0];
    AddressS1 = (count[11:8] + count[7:4]) * 32 + count[3:0];

    temp      = count[11:0] - 12'd16;
    AddressS2 = (temp[11:8] + temp[7:4]) * 32 + temp[3:0] + 10'd16;

    VectorX   = count[3:0] - 4'd8;
    VectorY   = count[11:8] - 4'd9;

    completed = (count == count_complete[12:0]);
  end

endmodule


/* Module For Comparator Unit */
module Comparator (
  input  wire           clock,
  input  wire           CompStart,
  input  wire [127:0]   PEout,
  input  wire [15:0]    PEready,
  input  wire [3:0]     vectorX,
  input  wire [3:0]     vectorY,
  output reg  [7:0]     BestDist,
  output reg  [3:0]     motionX,
  output reg  [3:0]     motionY
);

  reg [7:0] selectedDist;
  reg       validDist;

  always @(*) begin
    validDist = 1'b1;

    case (PEready)
      16'b0000_0000_0000_0001: selectedDist = PEout[7:0];
      16'b0000_0000_0000_0010: selectedDist = PEout[15:8];
      16'b0000_0000_0000_0100: selectedDist = PEout[23:16];
      16'b0000_0000_0000_1000: selectedDist = PEout[31:24];
      16'b0000_0000_0001_0000: selectedDist = PEout[39:32];
      16'b0000_0000_0010_0000: selectedDist = PEout[47:40];
      16'b0000_0000_0100_0000: selectedDist = PEout[55:48];
      16'b0000_0000_1000_0000: selectedDist = PEout[63:56];
      16'b0000_0001_0000_0000: selectedDist = PEout[71:64];
      16'b0000_0010_0000_0000: selectedDist = PEout[79:72];
      16'b0000_0100_0000_0000: selectedDist = PEout[87:80];
      16'b0000_1000_0000_0000: selectedDist = PEout[95:88];
      16'b0001_0000_0000_0000: selectedDist = PEout[103:96];
      16'b0010_0000_0000_0000: selectedDist = PEout[111:104];
      16'b0100_0000_0000_0000: selectedDist = PEout[119:112];
      16'b1000_0000_0000_0000: selectedDist = PEout[127:120];
      default: begin
        selectedDist = 8'hFF;
        validDist    = 1'b0;
      end
    endcase
  end

  always @(posedge clock) begin
    if (!CompStart) begin
      BestDist <= 8'hFF;
      motionX  <= 4'd0;
      motionY  <= 4'd0;
    end
    else if (validDist && (selectedDist < BestDist)) begin
      BestDist <= selectedDist;
      motionX  <= vectorX;
      motionY  <= vectorY;
    end
  end

endmodule

/* Module For Total 16 Processing Elements (PEtotal) */
module PEtotal (
  input  wire         clock,
  input  wire [7:0]   R,
  input  wire [7:0]   S1,
  input  wire [7:0]   S2,
  input  wire [15:0]  S1S2mux,
  input  wire [15:0]  newDist,
  output wire [127:0] Accumulate
);

  wire [7:0] Rpipe0, Rpipe1, Rpipe2, Rpipe3, Rpipe4, Rpipe5, Rpipe6, Rpipe7;
  wire [7:0] Rpipe8, Rpipe9, Rpipe10, Rpipe11, Rpipe12, Rpipe13, Rpipe14;

  PE pe0   (clock, R,       S1, S2, S1S2mux[0],  newDist[0],  Accumulate[7:0],    Rpipe0);
  PE pe1   (clock, Rpipe0,  S1, S2, S1S2mux[1],  newDist[1],  Accumulate[15:8],   Rpipe1);
  PE pe2   (clock, Rpipe1,  S1, S2, S1S2mux[2],  newDist[2],  Accumulate[23:16],  Rpipe2);
  PE pe3   (clock, Rpipe2,  S1, S2, S1S2mux[3],  newDist[3],  Accumulate[31:24],  Rpipe3);
  PE pe4   (clock, Rpipe3,  S1, S2, S1S2mux[4],  newDist[4],  Accumulate[39:32],  Rpipe4);
  PE pe5   (clock, Rpipe4,  S1, S2, S1S2mux[5],  newDist[5],  Accumulate[47:40],  Rpipe5);
  PE pe6   (clock, Rpipe5,  S1, S2, S1S2mux[6],  newDist[6],  Accumulate[55:48],  Rpipe6);
  PE pe7   (clock, Rpipe6,  S1, S2, S1S2mux[7],  newDist[7],  Accumulate[63:56],  Rpipe7);
  PE pe8   (clock, Rpipe7,  S1, S2, S1S2mux[8],  newDist[8],  Accumulate[71:64],  Rpipe8);
  PE pe9   (clock, Rpipe8,  S1, S2, S1S2mux[9],  newDist[9],  Accumulate[79:72],  Rpipe9);
  PE pe10  (clock, Rpipe9,  S1, S2, S1S2mux[10], newDist[10], Accumulate[87:80],  Rpipe10);
  PE pe11  (clock, Rpipe10, S1, S2, S1S2mux[11], newDist[11], Accumulate[95:88],  Rpipe11);
  PE pe12  (clock, Rpipe11, S1, S2, S1S2mux[12], newDist[12], Accumulate[103:96], Rpipe12);
  PE pe13  (clock, Rpipe12, S1, S2, S1S2mux[13], newDist[13], Accumulate[111:104], Rpipe13);
  PE pe14  (clock, Rpipe13, S1, S2, S1S2mux[14], newDist[14], Accumulate[119:112], Rpipe14);

  PEend pe15 (
    .clock(clock),
    .R(Rpipe14),
    .S1(S1),
    .S2(S2),
    .S1S2mux(S1S2mux[15]),
    .newDist(newDist[15]),
    .Accumulate(Accumulate[127:120])
  );

endmodule


/* Module For Reference Block (Memory) */
module ROM_R (
  input  wire       clock,
  input  wire [7:0] AddressR,
  output reg  [7:0] R
);

  reg [7:0] Rmem[0:255];

  always @(*) begin
    R = Rmem[AddressR];
  end

endmodule


/* Module For Search Block (Memory) */
module ROM_S (
  input  wire        clock,
  input  wire [9:0]  AddressS1,
  input  wire [9:0]  AddressS2,
  output reg  [7:0]  S1,
  output reg  [7:0]  S2
);

  reg [7:0] Smem[0:1023];

  always @(*) begin
    S1 = Smem[AddressS1];
    S2 = Smem[AddressS2];
  end

endmodule
