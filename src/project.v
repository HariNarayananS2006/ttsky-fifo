/*
 * Copyright (c) 2026 S Harinarayanan
 * SPDX-License-Identifier: Apache-2.0
 *
 * Tiny Tapeout wrapper for an 8-bit x 16-deep synchronous FIFO.
 *
 *   ui_in[7:0]  -> din        (write data)
 *   uio_in[0]   -> wr_en      (input)
 *   uio_in[1]   -> rd_en      (input)
 *   uio_out[2]  <- full       (output)
 *   uio_out[3]  <- empty      (output)
 *   uo_out[7:0] <- dout       (read data, registered)
 */

`default_nettype none

module tt_um_harinarayanans2006_fifo (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  wire full;
  wire empty;

  fifo #(
      .WIDTH(8),
      .DEPTH(16)
  ) u_fifo (
      .clk  (clk),
      .rst_n(rst_n),
      .wr_en(uio_in[0]),
      .din  (ui_in),
      .rd_en(uio_in[1]),
      .dout (uo_out),
      .full (full),
      .empty(empty)
  );

  // uio[1:0] are inputs (wr_en, rd_en), uio[3:2] are outputs (full, empty),
  // uio[7:4] are unused and left as inputs.
  assign uio_out = {4'b0000, empty, full, 2'b00};
  assign uio_oe  = 8'b0000_1100;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, uio_in[7:2], 1'b0};

endmodule
