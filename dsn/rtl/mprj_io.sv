// This code snippet was auto generated by xls2vlog.py from source file: /home/patrick/Downloads/Interface-Definition.xlsx
// User: patrick
// Date: Jul-19-23



module MPRJ_IO #( parameter pADDR_WIDTH   = 12,
                  parameter pDATA_WIDTH   = 32
                )
(
  output wire  [11: 0] serial_rxd,
  output wire          serial_rclk,
  input  wire   [4: 0] user_prj_sel,
  input  wire  [11: 0] serial_txd,
  input  wire          serial_tclk,
  input  wire  [37: 0] io_in,
  input  wire          vccd1,
  input  wire          vccd2,
  input  wire          vssd1,
  input  wire          vssd2,
  output wire  [37: 0] io_out,
  output wire  [37: 0] io_oeb,
  output wire          io_clk,
  input  wire          user_clock2,
  input  wire          axi_clk,
  input  wire          axi_reset_n,
  input  wire          axis_clk,
  input  wire          uck2_rst_n,
  input  wire          axis_rst_n
);

// MPRJ_IO PIN PLANNING
// --------------------------------
// [19: 8]  I   RXD
// [   20]  I   RXCLK

// --------------------------------
// [32:21]  O   TXD
// [   33]  O   TXCLK

// --------------------------------
// [   37]  I   IO_CLK

/*
assign serial_rxd    = 12'b0;
assign serial_rclk   = 1'b0;
assign io_out        = 38'b0;
assign io_oeb        = 38'b0;
*/

assign io_clk = io_in[37];

assign io_oeb[ 7: 0]   =  8'h00;

assign io_oeb[19: 8]   = 12'h000;  // RXD
assign io_oeb[   20]   =  1'b0;    // RX_CLK

assign io_oeb[32:21]   = 12'hFFF;  // TXD
assign io_oeb[   33]   =  1'b1;    // TX_CLK

assign io_oeb[   37]   =  1'b0;    // IO_CLK (from FPGA)


assign serial_rxd  = io_in[19:8];
assign serial_rclk = io_in[  20];

assign io_out[32:21] = serial_txd;
assign io_out[   33] = serial_tclk;


endmodule // MPRJ_IO


