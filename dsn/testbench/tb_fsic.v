`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/16/2023 11:55:15 AM
// Design Name: 
// Module Name: tb_fsic
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
//20230804 1. use #0 for create event to avoid potencial race condition. I didn't found issue right now, just update the code to improve it.
//	reference https://blog.csdn.net/seabeam/article/details/41078023, the source is come from http://www.deepchip.com/items/0466-07.html
//	 Not using #0 is a good guideline, except for event data types.  In Verilog, there is no way to defer the event triggering to the nonblocking event queue.

module tb_fsic #( parameter BITS=32,
		parameter pSERIALIO_WIDTH   = 12,
		parameter pADDR_WIDTH   = 15,
		parameter pDATA_WIDTH   = 32,
		parameter IOCLK_Period	= 10,
		// parameter DLYCLK_Period	= 1,
		parameter SHIFT_DEPTH = 5,
		parameter pRxFIFO_DEPTH = 5,
		parameter pCLK_RATIO = 4
	)
(
);
		localparam CoreClkPhaseLoop	= 4;
		localparam UP_BASE=32'h3000_0000;
		localparam AA_BASE=32'h3000_2000;
		localparam IS_BASE=32'h3000_3000;

		localparam SOC_to_FPGA_MailBox_Base=28'h000_2000;
		localparam FPGA_to_SOC_UP_BASE=28'h000_0000;
		localparam FPGA_to_SOC_AA_BASE=28'h000_2000;
		localparam FPGA_to_SOC_IS_BASE=28'h000_3000;
		
		localparam AA_MailBox_Reg_Offset=12'h000;
		localparam AA_Internal_Reg_Offset=12'h100;
		
		localparam TUSER_AXIS = 2'b00;
		localparam TUSER_AXILITE_WRITE = 2'b01;
		localparam TUSER_AXILITE_READ_REQ = 2'b10;
		localparam TUSER_AXILITE_READ_CPL = 2'b11;

		localparam TID_DN_UP = 2'b00;
		localparam TID_DN_AA = 2'b01;
		localparam TID_UP_UP = 2'b00;
		localparam TID_UP_AA = 2'b01;
		localparam TID_UP_LA = 2'b10;
		
		
    real ioclk_pd = IOCLK_Period;

  wire           wb_rst;
  wire           wb_clk;
  reg   [31: 0] wbs_adr;
  reg   [31: 0] wbs_wdata;
  reg    [3: 0] wbs_sel;
  reg           wbs_cyc;
  reg           wbs_stb;
  reg           wbs_we;
  reg  [127: 0] la_data_in;
  reg  [127: 0] la_oenb;
  wire   [37: 0] io_in;
  reg           vccd1;
  reg           vccd2;
  reg           vssd1;
  reg           vssd2;
  reg           user_clock2;
  reg           ioclk_source;
	
	wire  [37: 0] io_oeb;	
	wire  [37: 0] io_out;	
	
	wire soc_coreclk;
	wire fpga_coreclk;
	
	wire [37:0] mprj_io;
	wire  [127: 0] la_data_out;
	wire    [2: 0] user_irq;
	
//-------------------------------------------------------------------------------------

	reg[31:0] i;
	
	reg[31:0] cfg_read_data_expect_value;
	reg[31:0] cfg_read_data_captured;
	event soc_cfg_read_event;
	
	reg[27:0] soc_to_fpga_mailbox_write_addr_expect_value;
	reg[3:0] soc_to_fpga_mailbox_write_addr_BE_expect_value;
	reg[31:0] soc_to_fpga_mailbox_write_data_expect_value;
	reg [31:0] soc_to_fpga_mailbox_write_addr_captured;
	reg [31:0] soc_to_fpga_mailbox_write_data_captured;
	event soc_to_fpga_mailbox_write_event;

    reg stream_data_addr_or_data; //0: address, 1: data, use to identify the write transaction from AA.

	reg [31:0] soc_to_fpga_axilite_read_cpl_expect_value;
	reg [31:0] soc_to_fpga_axilite_read_cpl_captured;
	event soc_to_fpga_axilite_read_cpl_event;

	reg [31:0] error_cnt;
	reg [31:0] check_cnt;
//-------------------------------------------------------------------------------------	
	//reg soc_rst;
	reg fpga_rst;
	reg soc_resetb;		//POR reset
	reg fpga_resetb;	//POR reset	
	
	//reg ioclk;
	//reg dlyclk;


	//write addr channel
	reg fpga_axi_awvalid;
	reg [pADDR_WIDTH-1:0] fpga_axi_awaddr;
	wire fpga_axi_awready;
	
	//write data channel
	reg 	fpga_axi_wvalid;
	reg 	[pDATA_WIDTH-1:0] fpga_axi_wdata;
	reg 	[3:0] fpga_axi_wstrb;
	wire	fpga_axi_wready;
	
	//read addr channel
	reg 	fpga_axi_arvalid;
	reg 	[pADDR_WIDTH-1:0] fpga_axi_araddr;
	wire 	fpga_axi_arready;
	
	//read data channel
	wire 	fpga_axi_rvalid;
	wire 	[pDATA_WIDTH-1:0] fpga_axi_rdata;
	reg 	fpga_axi_rready;
	
	reg 	fpga_cc_is_enable;		//axi_lite enable

	wire [pSERIALIO_WIDTH-1:0] soc_serial_txd;
	wire soc_txclk;
	wire fpga_txclk;
	
	reg [pDATA_WIDTH-1:0] fpga_as_is_tdata;
	reg [3:0] fpga_as_is_tstrb;
	reg [3:0] fpga_as_is_tkeep;
	reg fpga_as_is_tlast;
	reg [1:0] fpga_as_is_tid;
	reg fpga_as_is_tvalid;
	reg [1:0] fpga_as_is_tuser;
	reg fpga_as_is_tready;		//when local side axis switch Rxfifo size <= threshold then as_is_tready=0; this flow control mechanism is for notify remote side do not provide data with is_as_tvalid=1

	wire [pSERIALIO_WIDTH-1:0] fpga_serial_txd;
//	wire [7:0] fpga_Serial_Data_Out_tdata;
//	wire fpga_Serial_Data_Out_tstrb;
//	wire fpga_Serial_Data_Out_tkeep;
//	wire fpga_Serial_Data_Out_tid_tuser;	// tid and tuser	
//	wire fpga_Serial_Data_Out_tlast_tvalid_tready;		//flowcontrol

	wire [pDATA_WIDTH-1:0] fpga_is_as_tdata;
	wire [3:0] fpga_is_as_tstrb;
	wire [3:0] fpga_is_as_tkeep;
	wire fpga_is_as_tlast;
	wire [1:0] fpga_is_as_tid;
	wire fpga_is_as_tvalid;
	wire [1:0] fpga_is_as_tuser;
	wire fpga_is_as_tready;		//when remote side axis switch Rxfifo size <= threshold then is_as_tready=0, this flow control mechanism is for notify local side do not provide data with as_is_tvalid=1

	wire	wbs_ack;
	wire	[pDATA_WIDTH-1: 0] wbs_rdata;

	//wire [7:0] Serial_Data_Out_ad_delay1;
	//wire txclk_delay1;

	//wire [7:0] Serial_Data_Out_ad_delay;
	//wire txclk_delay;

	//assign #4 Serial_Data_Out_ad_delay1 = Serial_Data_Out_ad;
	//assign #4 txclk_delay1 = txclk;
	//assign #4 Serial_Data_Out_ad_delay = Serial_Data_Out_ad_delay1;
	//assign #4 txclk_delay = txclk_delay1;

//-------------------------------------------------------------------------------------	
	fsic_clock_div soc_clock_div (
	.resetb(soc_resetb),
	.in(ioclk_source),
	.out(soc_coreclk)
	);

	fsic_clock_div fpga_clock_div (
	.resetb(fpga_resetb),
	.in(ioclk_source),
	.out(fpga_coreclk)
	);

FSIC #(
		.pSERIALIO_WIDTH(pSERIALIO_WIDTH),
		.pADDR_WIDTH(pADDR_WIDTH),
		.pDATA_WIDTH(pDATA_WIDTH),
		.pRxFIFO_DEPTH(pRxFIFO_DEPTH),
		.pCLK_RATIO(pCLK_RATIO)
	)
	dut (
		//.serial_tclk(soc_txclk),
		//.serial_rclk(fpga_txclk),
		//.serial_txd(soc_serial_txd),
		//.serial_rxd(fpga_serial_txd),
		.wb_rst(wb_rst),
		.wb_clk(wb_clk),
		.wbs_adr(wbs_adr),
		.wbs_wdata(wbs_wdata),
		.wbs_sel(wbs_sel),
		.wbs_cyc(wbs_cyc),
		.wbs_stb(wbs_stb),
		.wbs_we(wbs_we),
		.la_data_in(la_data_in),
		.la_oenb(la_oenb),
		.io_in(io_in),
		.vccd1(vccd1),
		.vccd2(vccd2),
		.vssd1(vssd1),
		.vssd2(vssd2),
		.wbs_ack(wbs_ack),
		.wbs_rdata(wbs_rdata),		
		.la_data_out(la_data_out),
		.user_irq(user_irq),
		.io_out(io_out),
		.io_oeb(io_oeb),
		.user_clock2(user_clock2)
	);

	fpga  #(
		.pSERIALIO_WIDTH(pSERIALIO_WIDTH),
		.pADDR_WIDTH(pADDR_WIDTH),
		.pDATA_WIDTH(pDATA_WIDTH),
		.pRxFIFO_DEPTH(pRxFIFO_DEPTH),
		.pCLK_RATIO(pCLK_RATIO)
	)
	fpga_fsic(
		.axis_rst_n(~fpga_rst),
		.axi_reset_n(~fpga_rst),
		.serial_tclk(fpga_txclk),
		.serial_rclk(soc_txclk),
		.ioclk(ioclk_source),
		.axis_clk(fpga_coreclk),
		.axi_clk(fpga_coreclk),
		
		//write addr channel
		.axi_awvalid_s_awvalid(fpga_axi_awvalid),
		.axi_awaddr_s_awaddr(fpga_axi_awaddr),
		.axi_awready_axi_awready3(fpga_axi_awready),

		//write data channel
		.axi_wvalid_s_wvalid(fpga_axi_wvalid),
		.axi_wdata_s_wdata(fpga_axi_wdata),
		.axi_wstrb_s_wstrb(fpga_axi_wstrb),
		.axi_wready_axi_wready3(fpga_axi_wready),

		//read addr channel
		.axi_arvalid_s_arvalid(fpga_axi_arvalid),
		.axi_araddr_s_araddr(fpga_axi_araddr),
		.axi_arready_axi_arready3(fpga_axi_arready),
		
		//read data channel
		.axi_rvalid_axi_rvalid3(fpga_axi_rvalid),
		.axi_rdata_axi_rdata3(fpga_axi_rdata),
		.axi_rready_s_rready(fpga_axi_rready),
		
		.cc_is_enable(fpga_cc_is_enable),


		.as_is_tdata(fpga_as_is_tdata),
		.as_is_tstrb(fpga_as_is_tstrb),
		.as_is_tkeep(fpga_as_is_tkeep),
		.as_is_tlast(fpga_as_is_tlast),
		.as_is_tid(fpga_as_is_tid),
		.as_is_tvalid(fpga_as_is_tvalid),
		.as_is_tuser(fpga_as_is_tuser),
		.as_is_tready(fpga_as_is_tready),
		.serial_txd(fpga_serial_txd),
		.serial_rxd(soc_serial_txd),
		.is_as_tdata(fpga_is_as_tdata),
		.is_as_tstrb(fpga_is_as_tstrb),
		.is_as_tkeep(fpga_is_as_tkeep),
		.is_as_tlast(fpga_is_as_tlast),
		.is_as_tid(fpga_is_as_tid),
		.is_as_tvalid(fpga_is_as_tvalid),
		.is_as_tuser(fpga_is_as_tuser),
		.is_as_tready(fpga_is_as_tready)
	);

	assign wb_clk = soc_coreclk;
	assign wb_rst = ~soc_resetb;		//wb_rst is high active
	//assign ioclk = ioclk_source;
	
    assign mprj_io[37] = ioclk_source;
    assign mprj_io[20] = fpga_txclk;
    assign mprj_io[19:8] = fpga_serial_txd;

    assign soc_txclk = mprj_io[33];
    assign soc_serial_txd = mprj_io[32:21];

	//connect input part : mprj_io to io_in
	assign io_in[37] = mprj_io[37];
	assign io_in[20] = mprj_io[20];
	assign io_in[19:8] = mprj_io[19:8];

	//connect output part : io_out to mprj_io
	assign mprj_io[33] = io_out[33];
	assign mprj_io[32:21] = io_out[32:21];
	
    initial begin
		ioclk_source=0;
        soc_resetb = 0;
		wbs_adr = 0;
		wbs_wdata = 0;
		wbs_sel = 0;
		wbs_cyc = 0;
		wbs_stb = 0;
		wbs_we = 0;
		la_data_in = 0;
		la_oenb = 0;
		vccd1 = 1;
		vccd2 = 1;
		vssd1 = 1;
		vssd2 = 1;
		user_clock2 = 0;
		error_cnt = 0;
		check_cnt = 0;

        
		test001();	//soc cfg write/read test
		test002();	//test002_fpga_axis_req
		test003();	//test003_fpga_to_soc_cfg_read
		test004();	//test004_fpga_to_soc_mail_box_write
		test005();	//test005_aa_mailbox_soc_cfg
		test006();	//test006_fpga_to_soc_cfg_write
		test007();	//test007_mailbox_interrupt test
		


		#400;
		$display("=============================================================================================");
		$display("=============================================================================================");
		$display("=============================================================================================");
		if (error_cnt != 0 )  begin 
			$display($time, "=> Final result [FAILED], check_cnt = %04d, error_cnt = %04d, please search [ERROR] in the log", check_cnt, error_cnt);
		end
		else
			$display($time, "=> Final result [PASS], check_cnt = %04d, error_cnt = %04d", check_cnt, error_cnt);
		$display("=============================================================================================");
		$display("=============================================================================================");
		$display("=============================================================================================");
		
		$finish;
        
    end
    
	//WB Master wb_ack_o handling
	always @( posedge wb_clk or posedge wb_rst) begin
		if ( wb_rst ) begin
			wbs_adr <= 32'h0;
			wbs_wdata <= 32'h0;
			wbs_sel <= 4'b0;
			wbs_cyc <= 1'b0;
			wbs_stb <= 1'b0;
			wbs_we <= 1'b0;			
		end else begin 
			if ( wbs_ack ) begin
				wbs_adr <= 32'h0;
				wbs_wdata <= 32'h0;
				wbs_sel <= 4'b0;
				wbs_cyc <= 1'b0;
				wbs_stb <= 1'b0;
				wbs_we <= 1'b0;
			end
		end
	end    
	
	always #(ioclk_pd/2) ioclk_source = ~ioclk_source;
//Willy debug - s

	task test007;
		begin
			$display("test007: mailbox interrupt test");

			#100;
			test007_initial();
			
			test007_aa_internal_soc_mb_interrupt_en();
            test007_fpga_mail_box_write();
            test007_soc_mb_read();
            test007_aa_internal_soc_mb_interrupt_status();
		end
	endtask
	
	
	task test007_initial;
	   begin
           $display("test007: TX/RX test");
            fork 
                soc_apply_reset(40, 40);			//change coreclk phase in soc
                fpga_apply_reset(40, 40);		//fix coreclk phase in fpga
            join
            #40;
            fpga_as_to_is_init();
            //soc_cc_is_enable=1;
            fpga_cc_is_enable=1;
            fork 
                soc_is_cfg_write(0, 4'b0001, 1);				//ioserdes rxen
                fpga_cfg_write(0,1,1,0);
            join
            $display($time, "=> soc rxen_ctl=1");
            $display($time, "=> fpga rxen_ctl=1");

            #400;
            fork 
                soc_is_cfg_write(0, 4'b0001, 3);				//ioserdes txen
                fpga_cfg_write(0,3,1,0);
            join
            $display($time, "=> soc txen_ctl=1");
            $display($time, "=> fpga txen_ctl=1");

            #200;
            fpga_as_is_tdata = 32'h5a5a5a5a;
            #40;
            #200;	   
	   end
    endtask

	task test007_aa_internal_soc_mb_interrupt_en;
		begin
			$display("Enable interrupt, set aa_regs offset 0, bit 0 = 1"); 
			cfg_read_data_expect_value = 32'h1;	
			soc_aa_cfg_write(AA_Internal_Reg_Offset + 0, 4'b1111, cfg_read_data_expect_value);				
			soc_aa_cfg_read(AA_Internal_Reg_Offset + 0, 4'b1111);

			check_cnt = check_cnt + 1;
			if (cfg_read_data_captured !== cfg_read_data_expect_value)  begin
				$display($time, "=> test007_aa_internal_soc_mb_interrupt_en [ERROR] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
				error_cnt = error_cnt+1;
			end
			else
				$display($time, "=> test007_aa_internal_soc_mb_interrupt_en [PASS] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);

            $display("Read interrupt status, aa_regs offset 4, bit 0 should be 0 by default"); 
			cfg_read_data_expect_value = 32'h0;	
            soc_aa_cfg_read(AA_Internal_Reg_Offset + 4, 4'b1111); 
			
			check_cnt = check_cnt + 1;
			if (cfg_read_data_captured[0] !== cfg_read_data_expect_value[0])  begin
				$display($time, "=> test007_aa_internal_soc_mb_interrupt_en [ERROR] cfg_read_data_expect_value[0]=%x, cfg_read_data_captured[0]=%x", cfg_read_data_expect_value[0], cfg_read_data_captured[0]);
				error_cnt = error_cnt+1;
			end
			else
				$display($time, "=> test007_aa_internal_soc_mb_interrupt_en [PASS] cfg_read_data_expect_value[0]=%x, cfg_read_data_captured[0]=%x", cfg_read_data_expect_value[0], cfg_read_data_captured[0]);
            
			#100;
		end
	endtask



	task test007_aa_internal_soc_mb_interrupt_status;
		begin
			$display("Check interrupt status, read aa_regs offset 4, bit 0"); 
			cfg_read_data_expect_value = 32'h1;	
				
			soc_aa_cfg_read(AA_Internal_Reg_Offset + 4, 4'b1111);

			check_cnt = check_cnt + 1;
			if (cfg_read_data_captured[0] !== cfg_read_data_expect_value[0]) begin
				$display($time, "=> Read soc_mb_interrupt_status [ERROR] cfg_read_data_expect_value[0]=%x, cfg_read_data_captured[0]=%x", cfg_read_data_expect_value[0], cfg_read_data_captured[0]);
				error_cnt = error_cnt+1;
			end
			else
				$display($time, "=> Read soc_mb_interrupt_status [PASS] cfg_read_data_expect_value[0]=%x, cfg_read_data_captured[0]=%x", cfg_read_data_expect_value[0], cfg_read_data_captured[0]);

            $display("Clear interrupt status, write aa_regs offset 4, bit 0 = 1");	
			soc_aa_cfg_write(AA_Internal_Reg_Offset + 4, 4'b1111, 1);

			cfg_read_data_expect_value = 32'h0;	
				
			soc_aa_cfg_read(AA_Internal_Reg_Offset + 4, 4'b1111);

			check_cnt = check_cnt + 1;
			if (cfg_read_data_captured[0] !== cfg_read_data_expect_value[0]) begin
				$display($time, "=> Read soc_mb_interrupt_status [ERROR] cfg_read_data_expect_value[0]=%x, cfg_read_data_captured[0]=%x", cfg_read_data_expect_value[0], cfg_read_data_captured[0]);
				error_cnt = error_cnt+1;
			end 
			else
				$display($time, "=>Read soc_mb_interrupt_status [PASS] cfg_read_data_expect_value[0]=%x, cfg_read_data_captured[0]=%x", cfg_read_data_expect_value[0], cfg_read_data_captured[0]);
            
			#100;
		end
	endtask

	task test007_fpga_mail_box_write;
		//input [7:0] compare_data;

		//FPGA to SOC Axilite test
		begin
			@ (posedge fpga_coreclk);
			fpga_as_is_tready <= 1;
			
            fpga_axilite_write(FPGA_to_SOC_AA_BASE + AA_MailBox_Reg_Offset, 4'b1111, 32'h11111111);

			$display($time, "=> test007_fpga_mail_box_write done");
		end
	endtask


	task test007_soc_mb_read;
		begin
			$display("Read mb_regs offset 0"); 
			cfg_read_data_expect_value = 32'h11111111;					
			soc_aa_cfg_read(AA_MailBox_Reg_Offset, 4'b1111);

			check_cnt = check_cnt + 1;
			if (cfg_read_data_captured !== cfg_read_data_expect_value) begin
				$display($time, "=> Result: mb_regs offset 0 [ERROR] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
				error_cnt = error_cnt+1;
			end
			else
				$display($time, "=> Result: mb_regs offset 0 [PASS] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);            
			#100;
		end
	endtask

//Wi lly debug - e


	task test001;
		begin
			$display("test001: soc cfg write/read test");

			#100;
			soc_apply_reset(40,40);
			fpga_apply_reset(40,40);


			test001_is_soc_cfg();
			test001_aa_internal_soc_cfg();
			//test001_aa_internal_soc_cfg_full_range();
			test001_up_soc_cfg();
		end
	endtask

	task test005;
		begin
			$display("test005: soc mail box cfg write/read test");

			#100;
			soc_apply_reset(40,40);
			fpga_apply_reset(40,40);

			#100;
			
			//soc_cc_is_enable=1;
			fpga_cc_is_enable=1;

			fpga_as_to_is_init();

			fork 
				soc_is_cfg_write(0, 4'b0001, 1);				//ioserdes rxen
				fpga_cfg_write(0,1,1,0);
			join
			$display($time, "=> soc rxen_ctl=1");
			$display($time, "=> fpga rxen_ctl=1");

			#400;
			fork 
				soc_is_cfg_write(0, 4'b0001, 3);				//ioserdes txen
				fpga_cfg_write(0,3,1,0);
			join
			$display($time, "=> soc txen_ctl=1");
			$display($time, "=> fpga txen_ctl=1");

			#200;
			fpga_as_is_tdata = 32'h5a5a5a5a;
		
			#200;

			test005_aa_mailbox_soc_cfg();
			
			#100;
		end
	endtask

	task test001_is_soc_cfg;
		begin
			//Test offset 0x00 only for io serdes
			$display("test001_is_soc_cfg: soc cfg read/write test");

			cfg_read_data_expect_value = 32'h01;	
			soc_is_cfg_write(0, 4'b0001, cfg_read_data_expect_value);				//ioserdes rxen
			soc_is_cfg_read(0, 4'b1111);

			check_cnt = check_cnt + 1;
			if (cfg_read_data_captured !== cfg_read_data_expect_value) begin
				$display($time, "=> test001_is_soc_cfg [ERROR] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
				error_cnt = error_cnt + 1;
			end	
			else
				$display($time, "=> test001_is_soc_cfg [PASS] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
			$display("-----------------");

			cfg_read_data_expect_value = 32'h03;	
			soc_is_cfg_write(0, 4'b0001, cfg_read_data_expect_value);				//ioserdes rxen
			soc_is_cfg_read(0, 4'b1111);

			check_cnt = check_cnt + 1;
			if (cfg_read_data_captured !== cfg_read_data_expect_value) begin
				$display($time, "=> test001_is_soc_cfg [ERROR] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
				error_cnt = error_cnt + 1;
			end	
			else
				$display($time, "=> test001_is_soc_cfg [PASS] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
			$display("-----------------");
			$display("test001_is_soc_cfg: soc cfg read/write test - end");
			$display("--------------------------------------------------------------------");

			#100;
		end
	endtask

	task test001_up_soc_cfg;
		begin
			//Test offset 0x00 for user project
			$display("test001_up_soc_cfg: soc cfg read/write test");

			cfg_read_data_expect_value = 32'ha5a5a5a5;	
			soc_up_cfg_write(0, 4'b1111, cfg_read_data_expect_value);
			soc_up_cfg_read(0, 4'b1111);

			check_cnt = check_cnt + 1;
			if (cfg_read_data_captured !== cfg_read_data_expect_value) begin
				$display($time, "=> test001_up_soc_cfg [ERROR] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
				error_cnt = error_cnt + 1;
			end	
			else
				$display($time, "=> test001_up_soc_cfg [PASS] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
			$display("-----------------");

			cfg_read_data_expect_value = $random;	
			soc_up_cfg_write(0, 4'b1111, cfg_read_data_expect_value);
			soc_up_cfg_read(0, 4'b1111);

			check_cnt = check_cnt + 1;
			if (cfg_read_data_captured !== cfg_read_data_expect_value) begin
				$display($time, "=> test001_up_soc_cfg [ERROR] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
				error_cnt = error_cnt + 1;
			end	
			else
				$display($time, "=> test001_up_soc_cfg [PASS] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
			$display("-----------------");
			$display("test001_up_soc_cfg: soc cfg read/write test - end");
			$display("--------------------------------------------------------------------");

			#100;
		end
	endtask


	task test005_aa_mailbox_soc_cfg;
		begin
		 

			//Test offset 0x00~0xff for mail box write to AA
			$display("test005_aa_mailbox_soc_cfg: soc cfg read/write test - check soc cfg read value part");

			$display("test005_aa_mailbox_soc_cfg: AA Mail Box read/write test - start");
			for (i=0;i<32'h20;i=i+4) begin

				cfg_read_data_expect_value = 	32'ha5a5_a5a5;	
				soc_aa_cfg_write(AA_MailBox_Reg_Offset + i, 4'b1111, cfg_read_data_expect_value);				
				soc_aa_cfg_read(AA_MailBox_Reg_Offset + i, 4'b1111);

				check_cnt = check_cnt + 1;
				if (cfg_read_data_captured !== cfg_read_data_expect_value) begin
					$display($time, "=> test005_aa_mailbox_soc_cfg [ERROR] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
					error_cnt = error_cnt + 1;
				end
				else
					$display($time, "=> test005_aa_mailbox_soc_cfg [PASS] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
				$display("-----------------");
			end
			$display("test005_aa_mailbox_soc_cfg: AA Mail Box read/write test - end");
			$display("--------------------------------------------------------------------");

			$display("test005_aa_mailbox_soc_cfg: soc cfg read/write test - check soc to fpga cfg write value part");

			$display("test005_aa_mailbox_soc_cfg: AA Mail Box read/write test - start");
			for (i=0;i<32'h20;i=i+4) begin

				soc_to_fpga_mailbox_write_addr_expect_value =  SOC_to_FPGA_MailBox_Base + i;				
				soc_to_fpga_mailbox_write_addr_BE_expect_value = 4'b1111;
				soc_to_fpga_mailbox_write_data_expect_value = 	32'ha5a5_a5a5;
				soc_aa_cfg_write(AA_MailBox_Reg_Offset + i, soc_to_fpga_mailbox_write_addr_BE_expect_value, soc_to_fpga_mailbox_write_data_expect_value);
				@ (soc_to_fpga_mailbox_write_event) ;		//wait for fpga get the mail box write from soc.
				$display($time, "=> test005_aa_mailbox_soc_cfg : got soc_to_fpga_mailbox_write_event");

				//Address part
				check_cnt = check_cnt + 1;
				if ( soc_to_fpga_mailbox_write_addr_expect_value !== soc_to_fpga_mailbox_write_addr_captured[27:0]) begin
					$display($time, "=> test005_aa_mailbox_soc_cfg [ERROR] soc_to_fpga_mailbox_write_addr_expect_value=%x, soc_to_fpga_mailbox_write_addr_captured[27:0]=%x", soc_to_fpga_mailbox_write_addr_expect_value, soc_to_fpga_mailbox_write_addr_captured[27:0]);
					error_cnt = error_cnt + 1;
				end	
				else
					$display($time, "=> test005_aa_mailbox_soc_cfg [PASS] soc_to_fpga_mailbox_write_addr_expect_value=%x, soc_to_fpga_mailbox_write_addr_captured[27:0]=%x", soc_to_fpga_mailbox_write_addr_expect_value, soc_to_fpga_mailbox_write_addr_captured[27:0]);

				//BE part
				check_cnt = check_cnt + 1;
				if ( soc_to_fpga_mailbox_write_addr_BE_expect_value !== soc_to_fpga_mailbox_write_addr_captured[31:28]) begin
					$display($time, "=> test005_aa_mailbox_soc_cfg [ERROR] soc_to_fpga_mailbox_write_addr_BE_expect_value=%x, soc_to_fpga_mailbox_write_addr_captured[31:28]=%x", soc_to_fpga_mailbox_write_addr_BE_expect_value, soc_to_fpga_mailbox_write_addr_captured[31:28]);
					error_cnt = error_cnt + 1;
				end	
				else
					$display($time, "=> test005_aa_mailbox_soc_cfg [PASS] soc_to_fpga_mailbox_write_addr_BE_expect_value=%x, soc_to_fpga_mailbox_write_addr_captured[31:28]=%x", soc_to_fpga_mailbox_write_addr_BE_expect_value, soc_to_fpga_mailbox_write_addr_captured[31:28]);

				//data part
				check_cnt = check_cnt + 1;
				if (soc_to_fpga_mailbox_write_data_expect_value !== soc_to_fpga_mailbox_write_data_captured) begin
					$display($time, "=> test005_aa_mailbox_soc_cfg [ERROR] soc_to_fpga_mailbox_write_data_expect_value=%x, soc_to_fpga_mailbox_write_data_captured=%x", soc_to_fpga_mailbox_write_data_expect_value, soc_to_fpga_mailbox_write_data_captured);
					error_cnt = error_cnt + 1;
				end	
				else
					$display($time, "=> test005_aa_mailbox_soc_cfg [PASS] soc_to_fpga_mailbox_write_data_expect_value=%x, soc_to_fpga_mailbox_write_data_captured=%x", soc_to_fpga_mailbox_write_data_expect_value, soc_to_fpga_mailbox_write_data_captured);
				$display("-----------------");
			end
			$display("test005_aa_mailbox_soc_cfg: AA Mail Box read/write test - end");
			$display("--------------------------------------------------------------------");

			$display("test005_aa_mailbox_soc_cfg: soc cfg read/write test - check soc cfg read value part with random value");

			$display("test005_aa_mailbox_soc_cfg: AA Mail Box read/write test - start");
			for (i=0;i<32'h20;i=i+4) begin

				cfg_read_data_expect_value = 	$random;	
				soc_aa_cfg_write(AA_MailBox_Reg_Offset + i, 4'b1111, cfg_read_data_expect_value);				
				soc_aa_cfg_read(AA_MailBox_Reg_Offset + i, 4'b1111);

				check_cnt = check_cnt + 1;
				if (cfg_read_data_captured !== cfg_read_data_expect_value) begin
					$display($time, "=> test005_aa_mailbox_soc_cfg [ERROR] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
					error_cnt = error_cnt + 1;
				end	
				else
					$display($time, "=> test005_aa_mailbox_soc_cfg [PASS] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
				$display("-----------------");
			end
			$display("test005_aa_mailbox_soc_cfg: AA Mail Box read/write test - end");
			$display("--------------------------------------------------------------------");
			$display("test005_aa_mailbox_soc_cfg: soc cfg read/write test - check soc to fpga cfg write value part with random value");

			$display("test005_aa_mailbox_soc_cfg: AA Mail Box read/write test - start");
			for (i=0;i<32'h20;i=i+4) begin

				soc_to_fpga_mailbox_write_addr_expect_value =  SOC_to_FPGA_MailBox_Base + i;				
				soc_to_fpga_mailbox_write_addr_BE_expect_value = 4'b1111;
				soc_to_fpga_mailbox_write_data_expect_value = 	$random;
				soc_aa_cfg_write(i, soc_to_fpga_mailbox_write_addr_BE_expect_value, soc_to_fpga_mailbox_write_data_expect_value);
				repeat(20) @(posedge fpga_coreclk);		//wait for fpga get the data by delay, 10T should be ok, i use 20T for better margin, TODO use event to snyc it or support pipeline test

				//Address part
				check_cnt = check_cnt + 1;
				if ( soc_to_fpga_mailbox_write_addr_expect_value !== soc_to_fpga_mailbox_write_addr_captured[27:0]) begin
					$display($time, "=> test005_aa_mailbox_soc_cfg [ERROR] soc_to_fpga_mailbox_write_addr_expect_value=%x, soc_to_fpga_mailbox_write_addr_captured[27:0]=%x", soc_to_fpga_mailbox_write_addr_expect_value, soc_to_fpga_mailbox_write_addr_captured[27:0]);
					error_cnt = error_cnt + 1;
				end	
				else
					$display($time, "=> test005_aa_mailbox_soc_cfg [PASS] soc_to_fpga_mailbox_write_addr_expect_value=%x, soc_to_fpga_mailbox_write_addr_captured[27:0]=%x", soc_to_fpga_mailbox_write_addr_expect_value, soc_to_fpga_mailbox_write_addr_captured[27:0]);

				//BE part
				check_cnt = check_cnt + 1;
				if ( soc_to_fpga_mailbox_write_addr_BE_expect_value !== soc_to_fpga_mailbox_write_addr_captured[31:28]) begin
					$display($time, "=> test005_aa_mailbox_soc_cfg [ERROR] soc_to_fpga_mailbox_write_addr_BE_expect_value=%x, soc_to_fpga_mailbox_write_addr_captured[31:28]=%x", soc_to_fpga_mailbox_write_addr_BE_expect_value, soc_to_fpga_mailbox_write_addr_captured[31:28]);
					error_cnt = error_cnt + 1;
				end	
				else
					$display($time, "=> test005_aa_mailbox_soc_cfg [PASS] soc_to_fpga_mailbox_write_addr_BE_expect_value=%x, soc_to_fpga_mailbox_write_addr_captured[31:28]=%x", soc_to_fpga_mailbox_write_addr_BE_expect_value, soc_to_fpga_mailbox_write_addr_captured[31:28]);

				//data part
				check_cnt = check_cnt + 1;
				if (soc_to_fpga_mailbox_write_data_expect_value !== soc_to_fpga_mailbox_write_data_captured) begin
					$display($time, "=> test005_aa_mailbox_soc_cfg [ERROR] soc_to_fpga_mailbox_write_data_expect_value=%x, soc_to_fpga_mailbox_write_data_captured=%x", soc_to_fpga_mailbox_write_data_expect_value, soc_to_fpga_mailbox_write_data_captured);
					error_cnt = error_cnt + 1;
				end	
				else
					$display($time, "=> test005_aa_mailbox_soc_cfg [PASS] soc_to_fpga_mailbox_write_data_expect_value=%x, soc_to_fpga_mailbox_write_data_captured=%x", soc_to_fpga_mailbox_write_data_expect_value, soc_to_fpga_mailbox_write_data_captured);
				$display("-----------------");
			end
			$display("test005_aa_mailbox_soc_cfg: AA Mail Box read/write test - end");
			$display("--------------------------------------------------------------------");

			#100;
		end
	endtask

	task test001_aa_internal_soc_cfg;
		begin

			//Test offset 0x100~0xfff for AA internal register 
			$display("test001_aa_internal_soc_cfg: AA internal register read/write test - start");

			cfg_read_data_expect_value = 	32'h1;	
			soc_aa_cfg_write(AA_Internal_Reg_Offset, 4'b1111, cfg_read_data_expect_value);				
			soc_aa_cfg_read(AA_Internal_Reg_Offset, 4'b1111);

			check_cnt = check_cnt + 1;
			if (cfg_read_data_captured !== cfg_read_data_expect_value) begin
				$display($time, "=> test001_aa_internal_soc_cfg [ERROR] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
				error_cnt = error_cnt + 1;
				end	
			else
				$display($time, "=> test001_aa_internal_soc_cfg [PASS] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
			$display("-----------------");

			cfg_read_data_expect_value = 	32'h0;	
			soc_aa_cfg_write(AA_Internal_Reg_Offset + 4, 4'b1111, cfg_read_data_expect_value);				
			soc_aa_cfg_read(AA_Internal_Reg_Offset + 4, 4'b1111);

			check_cnt = check_cnt + 1;
			if (cfg_read_data_captured !== cfg_read_data_expect_value) begin
				$display($time, "=> test001_aa_internal_soc_cfg [ERROR] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
				error_cnt = error_cnt + 1;
				end	
			else
				$display($time, "=> test001_aa_internal_soc_cfg [PASS] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
			$display("-----------------");


			$display("test001_aa_internal_soc_cfg: AA Mail Box read/write test - end");
			$display("--------------------------------------------------------------------");

			#100;
		end
	endtask

	task test001_aa_internal_soc_cfg_full_range;
		begin

			//Test offset 0x100~0xfff for AA internal register 
			$display("test001_aa_internal_soc_cfg_full_range: AA internal register read/write test - start");
			for (i=0;i<32'h100;i=i+4) begin

				cfg_read_data_expect_value = 	32'ha5a5_a5a5;	
				soc_aa_cfg_write(AA_Internal_Reg_Offset + i, 4'b1111, cfg_read_data_expect_value);				
				soc_aa_cfg_read(AA_Internal_Reg_Offset + i, 4'b1111);

				check_cnt = check_cnt + 1;
				if (cfg_read_data_captured !== cfg_read_data_expect_value) begin
					$display($time, "=> test001_aa_internal_soc_cfg_full_range [ERROR] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
					error_cnt = error_cnt + 1;
				end	
				else
					$display($time, "=> test001_aa_internal_soc_cfg_full_range [PASS] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
				$display("-----------------");
			end
			$display("test001_aa_internal_soc_cfg_full_range: AA Mail Box read/write test - end");
			$display("--------------------------------------------------------------------");

			#100;
		end
	endtask


	initial begin		//get soc wishbone read data result.
		while (1) begin
			@(posedge soc_coreclk);
			if (wbs_ack==1 && wbs_we == 0) begin
				//$display($time, "=> get wishbone read data result be : cfg_read_data_captured =%x, wbs_rdata=%x", cfg_read_data_captured, wbs_rdata);
				cfg_read_data_captured = wbs_rdata ;		//use block assignment
				//$display($time, "=> get wishbone read data result af : cfg_read_data_captured =%x, wbs_rdata=%x", cfg_read_data_captured, wbs_rdata);
				#0 -> soc_cfg_read_event;
				$display($time, "=> soc wishbone read data result : send soc_cfg_read_event"); 
			end	
		end
	end


	initial begin		//when soc cfg write to AA, then AA in soc generate soc_to_fpga_mailbox_write, 
	   stream_data_addr_or_data = 0;
		while (1) begin
			@(posedge fpga_coreclk);
			//New AA version, all stream data with last = 1.  
			if (fpga_is_as_tvalid == 1 && fpga_is_as_tid == TID_UP_AA && fpga_is_as_tuser == TUSER_AXILITE_WRITE && fpga_is_as_tlast == 1) begin
			
                if(stream_data_addr_or_data == 1'b0) begin
                    //Address
                    $display($time, "=> get soc_to_fpga_mailbox_write_addr_captured be : soc_to_fpga_mailbox_write_addr_captured =%x, fpga_is_as_tdata=%x", soc_to_fpga_mailbox_write_addr_captured, fpga_is_as_tdata);
                    soc_to_fpga_mailbox_write_addr_captured = fpga_is_as_tdata ;		//use block assignment
                    $display($time, "=> get soc_to_fpga_mailbox_write_addr_captured af : soc_to_fpga_mailbox_write_addr_captured =%x, fpga_is_as_tdata=%x", soc_to_fpga_mailbox_write_addr_captured, fpga_is_as_tdata);
                    //Next should be data
                    stream_data_addr_or_data = 1; 
                end else begin
                    //Data
                    $display($time, "=> get soc_to_fpga_mailbox_write_data_captured be : soc_to_fpga_mailbox_write_data_captured =%x, fpga_is_as_tdata=%x", soc_to_fpga_mailbox_write_data_captured, fpga_is_as_tdata);
                    soc_to_fpga_mailbox_write_data_captured = fpga_is_as_tdata ;		//use block assignment
                    $display($time, "=> get soc_to_fpga_mailbox_write_data_captured af : soc_to_fpga_mailbox_write_data_captured =%x, fpga_is_as_tdata=%x", soc_to_fpga_mailbox_write_data_captured, fpga_is_as_tdata);
                    #0 -> soc_to_fpga_mailbox_write_event;
                    $display($time, "=> soc_to_fpga_mailbox_write_data_captured : send soc_to_fpga_mailbox_write_event");                    
                    //Next should be address
                    stream_data_addr_or_data = 0;
                end
			end	
			
			
		end
	end


	initial begin		//get upstream soc_to_fpga_axilite_read_completion
		while (1) begin
			@(posedge fpga_coreclk);
			if (fpga_is_as_tvalid == 1 && fpga_is_as_tid == TID_UP_AA && fpga_is_as_tuser == TUSER_AXILITE_READ_CPL) begin
				$display($time, "=> get soc_to_fpga_axilite_read_cpl_captured be : soc_to_fpga_axilite_read_cpl_captured =%x, fpga_is_as_tdata=%x", soc_to_fpga_axilite_read_cpl_captured, fpga_is_as_tdata);
				soc_to_fpga_axilite_read_cpl_captured = fpga_is_as_tdata ;		//use block assignment
				$display($time, "=> get soc_to_fpga_axilite_read_cpl_captured af : soc_to_fpga_axilite_read_cpl_captured =%x, fpga_is_as_tdata=%x", soc_to_fpga_axilite_read_cpl_captured, fpga_is_as_tdata);
				#0 -> soc_to_fpga_axilite_read_cpl_event;
				$display($time, "=> soc_to_fpga_axilite_read_cpl_captured : send soc_to_fpga_axilite_read_cpl_event");
			end	
		end
	end


	task test004;
		//input [7:0] compare_data;

		begin
			for (i=0;i<CoreClkPhaseLoop;i=i+1) begin
				$display("test004: TX/RX test - loop %02d", i);
				fork 
					soc_apply_reset(40+i*10, 40);			//change coreclk phase in soc
					fpga_apply_reset(40,40);		//fix coreclk phase in fpga
				join
				#40;
				fpga_as_to_is_init();
				//soc_cc_is_enable=1;
				fpga_cc_is_enable=1;
				fork 
					soc_is_cfg_write(0, 4'b0001, 1);				//ioserdes rxen
					fpga_cfg_write(0,1,1,0);
				join
				$display($time, "=> soc rxen_ctl=1");
				$display($time, "=> fpga rxen_ctl=1");

				#400;
				fork 
					soc_is_cfg_write(0, 4'b0001, 3);				//ioserdes txen
					fpga_cfg_write(0,3,1,0);
				join
				$display($time, "=> soc txen_ctl=1");
				$display($time, "=> fpga txen_ctl=1");

				#200;
				fpga_as_is_tdata = 32'h5a5a5a5a;
				#40;
				#200;

				test004_fpga_to_soc_mail_box_write();		//target to AA
				#200;
			end
		end
	endtask

	reg[31:0]idx1;

	task test004_fpga_to_soc_mail_box_write;
		//input [7:0] compare_data;

		//FPGA to SOC Axilite test
		begin
			@ (posedge fpga_coreclk);
			fpga_as_is_tready <= 1;
			
			for(idx1=0; idx1<32'h20/4; idx1=idx1+1)begin		//
				fpga_axilite_write(FPGA_to_SOC_AA_BASE + AA_MailBox_Reg_Offset + idx1*4, 4'b1111, 32'h11111111 * idx1);
					//mailbox supported range address = 0x0000_2000 ~ 0000_201F
					//BE = 4'b1111
					//data = 32'h11111111 * idx1
			end

			$display($time, "=> test004_fpga_to_soc_mail_box_write done");
		end
	endtask

	task fpga_axilite_write;
		input [27:0] address;
		input [3:0] BE;
		input [31:0] data;
		begin
			fpga_as_is_tdata <= (BE<<28) + address;	//for axilite write address phase
			//$strobe($time, "=> fpga_as_is_tdata in address phase = %x", fpga_as_is_tdata);
			fpga_as_is_tstrb <=  4'b0000;
			fpga_as_is_tkeep <=  4'b0000;
			fpga_as_is_tid <=  TID_DN_AA ;		//target to Axis-Axilite
			fpga_as_is_tuser <=  TUSER_AXILITE_WRITE;		//for axilite write
			fpga_as_is_tlast <=  1'b0;
			fpga_as_is_tvalid <= 1;

			@ (posedge fpga_coreclk);
			while (fpga_is_as_tready == 0) begin		// wait util fpga_is_as_tready == 1 then change data
					@ (posedge fpga_coreclk);
			end

			fpga_as_is_tdata <=  data;	//for axilite write data phase
			fpga_as_is_tstrb <=  4'b0000;
			fpga_as_is_tkeep <=  4'b0000;
			fpga_as_is_tid <=  TID_DN_AA;		//target to Axis-Axilite
			fpga_as_is_tuser <=  TUSER_AXILITE_WRITE;		//for axilite write
			fpga_as_is_tlast <=  1'b0;
			fpga_as_is_tvalid <= 1;

			@ (posedge fpga_coreclk);
			while (fpga_is_as_tready == 0) begin		// wait util fpga_is_as_tready == 1 then change data
					@ (posedge fpga_coreclk);
			end
			fpga_as_is_tvalid <= 0;
		
		end
	endtask


	task test003;
		//input [7:0] compare_data;

		begin
			for (i=0;i<CoreClkPhaseLoop;i=i+1) begin
				$display("test003: fpga_cfg_read test - loop %02d", i);
				fork 
					soc_apply_reset(40+i*10, 40);			//change coreclk phase in soc
					fpga_apply_reset(40,40);		//fix coreclk phase in fpga
				join
				
				#40;
				
				fpga_as_to_is_init();	
				
				//soc_cc_is_enable=1;
				fpga_cc_is_enable=1;
				fork 
					soc_is_cfg_write(0, 4'b0001, 1);				//ioserdes rxen
					fpga_cfg_write(0,1,1,0);
				join
				$display($time, "=> soc rxen_ctl=1");
				$display($time, "=> fpga rxen_ctl=1");

				#400;
				fork 
					soc_is_cfg_write(0, 4'b0001, 3);				//ioserdes txen
					fpga_cfg_write(0,3,1,0);
				join
				$display($time, "=> soc txen_ctl=1");
				$display($time, "=> fpga txen_ctl=1");

				#200;
				fpga_as_is_tdata = 32'h5a5a5a5a;
				#40;
				#200;

				test003_fpga_to_soc_cfg_read();

				#200;
			end
		end
	endtask

	task fpga_as_to_is_init;
		//input [7:0] compare_data;

		begin
			//init fpga as to is signal, set fpga_as_is_tready = 1 for receives data from soc
			@ (posedge fpga_coreclk);
			fpga_as_is_tdata <=  32'h0;
			fpga_as_is_tstrb <=  4'b0000;
			fpga_as_is_tkeep <=  4'b0000;
			fpga_as_is_tid <=  TID_DN_UP;
			fpga_as_is_tuser <=  TUSER_AXIS;
			fpga_as_is_tlast <=  1'b0;
			fpga_as_is_tvalid <= 0;
			fpga_as_is_tready <= 1;
			$display($time, "=> fpga_as_to_is_init done");
		end
	endtask

	reg[31:0]idx2;

	task test003_fpga_to_soc_cfg_read;		//target to io serdes
		//input [7:0] compare_data;

		//FPGA to SOC Axilite test
		begin

			@ (posedge fpga_coreclk);
			fpga_as_is_tready <= 1;
			
			for(idx2=0; idx2<32/4; idx2=idx2+1)begin		//
				//step 1. fpga issue cfg read request to soc
				soc_to_fpga_axilite_read_cpl_expect_value = 32'h3;
				fpga_axilite_read_req(FPGA_to_SOC_IS_BASE + idx2*4);
					//read address = h0000_3000 ~ h0000_301F for io serdes
				//step 2. fpga wait for read completion from soc
				$display($time, "=> test003_fpga_to_soc_cfg_read :wait for soc_to_fpga_axilite_read_cpl_event");
				@(soc_to_fpga_axilite_read_cpl_event);		//wait for fpga get the read cpl.
				$display($time, "=> test003_fpga_to_soc_cfg_read : got soc_to_fpga_axilite_read_cpl_event");

				$display($time, "=> test003_fpga_to_soc_cfg_read : soc_to_fpga_axilite_read_cpl_captured=%x", soc_to_fpga_axilite_read_cpl_captured);

				//Data part
				check_cnt = check_cnt + 1;
				if ( soc_to_fpga_axilite_read_cpl_expect_value !== soc_to_fpga_axilite_read_cpl_captured) begin
					$display($time, "=> test003_fpga_to_soc_cfg_read [ERROR] soc_to_fpga_axilite_read_cpl_expect_value=%x, soc_to_fpga_axilite_read_cpl_captured[27:0]=%x", soc_to_fpga_axilite_read_cpl_expect_value, soc_to_fpga_axilite_read_cpl_captured[27:0]);
					error_cnt = error_cnt + 1;
				end	
				else
					$display($time, "=> test003_fpga_to_soc_cfg_read [PASS] soc_to_fpga_axilite_read_cpl_expect_value=%x, soc_to_fpga_axilite_read_cpl_captured[27:0]=%x", soc_to_fpga_axilite_read_cpl_expect_value, soc_to_fpga_axilite_read_cpl_captured[27:0]);
				
			end
			$display($time, "=> test003_fpga_to_soc_cfg_read done");
		end
	endtask


	task fpga_axilite_read_req;
		input [31:0] address;
		begin
			fpga_as_is_tdata <= address;	//for axilite read address req phase
			$strobe($time, "=> fpga_axilite_read_req in address req phase = %x - tvalid", fpga_as_is_tdata);
			fpga_as_is_tstrb <=  4'b0000;
			fpga_as_is_tkeep <=  4'b0000;
			fpga_as_is_tid <=  TID_DN_AA;		//target to Axis-Axilite
			fpga_as_is_tuser <=  TUSER_AXILITE_READ_REQ;		//for axilite read req
			fpga_as_is_tlast <=  1'b0;
			fpga_as_is_tvalid <= 1;

			@ (posedge fpga_coreclk);
			while (fpga_is_as_tready == 0) begin		// wait util fpga_is_as_tready == 1 then change data
					@ (posedge fpga_coreclk);
			end
			$display($time, "=> fpga_axilite_read_req in address req phase = %x - transfer", fpga_as_is_tdata);
			fpga_as_is_tvalid <= 0;
		
		end
	endtask

	task fpga_is_as_data_valid;
		// input [31:0] address;
		begin
			fpga_as_is_tready <= 1;		//TODO change to other location for set fpga_as_is_tready
			//force fpga_is_as_tvalid=1;
			
			$strobe($time, "=> fpga_is_as_data_valid wait fpga_is_as_tvalid");
			@ (posedge fpga_coreclk);
			while (fpga_is_as_tvalid == 0) begin		// wait util fpga_is_as_tvalid == 1 
					@ (posedge fpga_coreclk);
			end
			$strobe($time, "=> fpga_is_as_data_valid wait fpga_is_as_tvalid done, fpga_is_as_tvalid = %b", fpga_is_as_tvalid);
		
		end
	endtask

	task test002;		//test002_fpga_axis_req
		//input [7:0] compare_data;

		begin
			for (i=0;i<CoreClkPhaseLoop;i=i+1) begin
				$display("test002: fpga_axis_req - loop %02d", i);
				fork 
					soc_apply_reset(40+i*10, 40);			//change coreclk phase in soc
					fpga_apply_reset(40,40);		//fix coreclk phase in fpga
				join
				#40;

				fpga_as_to_is_init();
				
				//soc_cc_is_enable=1;
				fpga_cc_is_enable=1;
				fork 
					soc_is_cfg_write(0, 4'b0001, 1);				//ioserdes rxen
					fpga_cfg_write(0,1,1,0);
				join
				$display($time, "=> soc rxen_ctl=1");
				$display($time, "=> fpga rxen_ctl=1");

				#400;
				fork 
					soc_is_cfg_write(0, 4'b0001, 3);				//ioserdes txen
					fpga_cfg_write(0,3,1,0);
				join
				$display($time, "=> soc txen_ctl=1");
				$display($time, "=> fpga txen_ctl=1");

				#200;
				fpga_as_is_tdata = 32'h5a5a5a5a;
				#40;
				#200;

				test002_fpga_axis_req();		//target to Axis Switch

				#200;
			end
		end
	endtask

	reg[31:0]idx3;

	task test002_fpga_axis_req;
		//input [7:0] compare_data;

		//FPGA to SOC Axilite test
		begin
			//force User project up_as_tready = 1;
			force dut.AXIS_SW0.up_as_tready = 1;

			@ (posedge fpga_coreclk);
			fpga_as_is_tready <= 1;
			
			for(idx3=0; idx3<32; idx3=idx3+1)begin		//
				fpga_axis_req(32'h11111111 * (idx3 & 32'h0000_000F), TID_DN_UP);		//target to User Project
				//if (idx3 > 12 ) 			force dut.AXIS_SW0.up_as_tready = 1;
			end
			release dut.AXIS_SW0.up_as_tready;
			
			$display($time, "=> test002_fpga_axis_req done");
		end
	endtask

	task fpga_axis_req;
		input [31:0] data;
		input [1:0] tid;
		begin
			fpga_as_is_tdata <= data;	//for axis write data
			$strobe($time, "=> fpga_axis_req fpga_as_is_tdata = %x", fpga_as_is_tdata);
			fpga_as_is_tstrb <=  4'b0000;
			fpga_as_is_tkeep <=  4'b0000;
			fpga_as_is_tid <=  tid;		//set target
			fpga_as_is_tuser <=  TUSER_AXIS;		//for axis req
			fpga_as_is_tlast <=  1'b0;
			fpga_as_is_tvalid <= 1;

			@ (posedge fpga_coreclk);
			while (fpga_is_as_tready == 0) begin		// wait util fpga_is_as_tready == 1 then change data
					@ (posedge fpga_coreclk);
			end
			fpga_as_is_tvalid <= 0;
		
		end
	endtask

	task test006;
		//input [7:0] compare_data;

		begin
			for (i=0;i<CoreClkPhaseLoop;i=i+1) begin
				$display("test006: fpga to soc cfg write test - loop %02d", i);
				fork 
					soc_apply_reset(40+i*10, 40);			//change coreclk phase in soc
					fpga_apply_reset(40,40);		//fix coreclk phase in fpga
				join
				
				#40;
				
				fpga_as_to_is_init();	
				
				//soc_cc_is_enable=1;
				fpga_cc_is_enable=1;
				fork 
					soc_is_cfg_write(0, 4'b0001, 1);				//ioserdes rxen
					fpga_cfg_write(0,1,1,0);
				join
				$display($time, "=> soc rxen_ctl=1");
				$display($time, "=> fpga rxen_ctl=1");

				#400;
				fork 
					soc_is_cfg_write(0, 4'b0001, 3);				//ioserdes txen
					fpga_cfg_write(0,3,1,0);
				join
				$display($time, "=> soc txen_ctl=1");
				$display($time, "=> fpga txen_ctl=1");

				#200;
				fpga_as_is_tdata = 32'h5a5a5a5a;
				#40;
				#200;

				test006_fpga_to_soc_cfg_write();

				#200;
			end
		end
	endtask

	reg[31:0]idx6;

	task test006_fpga_to_soc_cfg_write;		//target to AA internal register
		//input [7:0] compare_data;

		//FPGA to SOC Axilite test
		begin

			@ (posedge fpga_coreclk);
			fpga_as_is_tready <= 1;
			
			//step 1. check default value
			$display($time, "=> test006_fpga_to_soc_cfg_write - for AA_Internal_Reg default value check");
			cfg_read_data_expect_value = 	32'h0;			//default value after reset = 0
			soc_aa_cfg_read(AA_Internal_Reg_Offset, 4'b1111);

			check_cnt = check_cnt + 1;
			if (cfg_read_data_captured !== cfg_read_data_expect_value) begin
				$display($time, "=> test006_fpga_to_soc_cfg_write [ERROR] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
				error_cnt = error_cnt + 1;
			end	
			else
				$display($time, "=> test006_fpga_to_soc_cfg_write [PASS] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
			$display("-----------------");


			//step 2. fpga issue fpga to soc cfg write request
			@ (posedge fpga_coreclk);
			cfg_read_data_expect_value = 	32'h1;	
			fpga_axilite_write_req(FPGA_to_SOC_AA_BASE + AA_Internal_Reg_Offset , 4'b0001, cfg_read_data_expect_value);
				//write address = h0000_2100 ~ h0000_2FFF for AA internal register
			//step 3. fpga wait for write to soc
			repeat(100) @ (posedge soc_coreclk);    //TODO fpga wait for write to soc
			//fpga_is_as_data_valid();

			soc_aa_cfg_read(AA_Internal_Reg_Offset, 4'b1111);

			check_cnt = check_cnt + 1;
			if (cfg_read_data_captured !== cfg_read_data_expect_value) begin
				$display($time, "=> test006_fpga_to_soc_cfg_write [ERROR] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
				error_cnt = error_cnt + 1;
			end	
			else
				$display($time, "=> test006_fpga_to_soc_cfg_write [PASS] cfg_read_data_expect_value=%x, cfg_read_data_captured=%x", cfg_read_data_expect_value, cfg_read_data_captured);
			$display("-----------------");
	
			$display($time, "=> test006_fpga_to_soc_cfg_write done");
		end
	endtask

	task fpga_axilite_write_req;
		input [27:0] address;
		input [3:0] BE;
		input [31:0] data;

		begin
			fpga_as_is_tdata[27:0] <= address;	//for axilite write address phase
			fpga_as_is_tdata[31:28] <= BE;	
			$strobe($time, "=> fpga_axilite_write_req in address phase = %x - tvalid", fpga_as_is_tdata);
			fpga_as_is_tstrb <=  4'b0000;
			fpga_as_is_tkeep <=  4'b0000;
			fpga_as_is_tid <=  TID_DN_AA;		//target to Axis-Axilite
			fpga_as_is_tuser <=  TUSER_AXILITE_WRITE;		//for axilite write req
			fpga_as_is_tlast <=  1'b0;
			fpga_as_is_tvalid <= 1;

			@ (posedge fpga_coreclk);
			while (fpga_is_as_tready == 0) begin		// wait util fpga_is_as_tready == 1 then change data
					@ (posedge fpga_coreclk);
			end
			$display($time, "=> fpga_axilite_write_req in address phase = %x - transfer", fpga_as_is_tdata);

			fpga_as_is_tdata <= data;	//for axilite write data phase
			$strobe($time, "=> fpga_axilite_write_req in data phase = %x - tvalid", fpga_as_is_tdata);
			fpga_as_is_tstrb <=  4'b0000;
			fpga_as_is_tkeep <=  4'b0000;
			fpga_as_is_tid <=  TID_DN_AA;		//target to Axis-Axilite
			fpga_as_is_tuser <=  TUSER_AXILITE_WRITE;		//for axilite write req
			fpga_as_is_tlast <=  1'b1;		//tlast = 1
			fpga_as_is_tvalid <= 1;

			@ (posedge fpga_coreclk);
			while (fpga_is_as_tready == 0) begin		// wait util fpga_is_as_tready == 1 then change data
					@ (posedge fpga_coreclk);
			end
			$display($time, "=> fpga_axilite_write_req in data phase = %x - transfer", fpga_as_is_tdata);
			
			
			fpga_as_is_tvalid <= 0;
		
		end
	endtask

// soc_axis_loopback
initial begin
	//connect_fpga_soc_serdes();
	soc_axis_loopback();
end

/*
	task connect_fpga_soc_serdes;
		begin
			$display($time, "=> connect_fpga_soc_serdes connect serdes tx/rx");
			force fpga_fsic.serial_rclk = dut.serial_tclk;
			force dut.serial_rclk = fpga_fsic.serial_tclk;

			force fpga_fsic.serial_rxd = dut.serial_txd;
			force dut.serial_rxd = fpga_fsic.serial_txd;
		end
	endtask
*/

	task soc_axis_loopback;
		//input [31:0] data;
		//input [1:0] tid;
		begin
			$display($time, "=> soc_axis_loopback force dut.AXIS_SW0.up_as_tvalid = 1");
			force dut.AXIS_SW0.up_as_tvalid = dut.AXIS_SW0.as_up_tvalid;
			force dut.AXIS_SW0.up_as_tdata = dut.AXIS_SW0.as_up_tdata;
			force dut.AXIS_SW0.up_as_tstrb =  dut.AXIS_SW0.as_up_tstrb;
			force dut.AXIS_SW0.up_as_tkeep =  dut.AXIS_SW0.as_up_tkeep;
			//force dut.AXIS_SW0.up_as_tid =    dut.AXIS_SW0.as_up_tid;
			force dut.AXIS_SW0.up_as_tuser =  dut.AXIS_SW0.as_up_tuser;
			force dut.AXIS_SW0.up_as_tlast =  dut.AXIS_SW0.as_up_tlast;

		
		end
	endtask




/*	
	task test00n;
		begin
		end
	endtask
*/

	//apply reset
	task soc_apply_reset;
		input real delta1;		// for POR De-Assert
		input real delta2;		// for reset De-Assert
		begin
			#(40);
			$display($time, "=> soc POR Assert"); 
			soc_resetb = 0;
			//$display($time, "=> soc reset Assert"); 
			//soc_rst = 1;
			#(delta1);

			$display($time, "=> soc POR De-Assert"); 
			soc_resetb = 1;

			#(delta2);
			//$display($time, "=> soc reset De-Assert"); 
			//soc_rst = 0;
		end	
	endtask
	
	task fpga_apply_reset;
		input real delta1;		// for POR De-Assert
		input real delta2;		// for reset De-Assert
		begin
			#(40);
			$display($time, "=> fpga POR Assert"); 
			fpga_resetb = 0;
			$display($time, "=> fpga reset Assert"); 
			fpga_rst = 1;
			#(delta1);

			$display($time, "=> fpga POR De-Assert"); 
			fpga_resetb = 1;

			#(delta2);
			$display($time, "=> fpga reset De-Assert"); 
			fpga_rst = 0;
		end
	endtask

	task soc_is_cfg_write;
		input [11:0] offset;		//4K range
		input [3:0] sel;
		input [31:0] data;
		
		begin
			@ (posedge soc_coreclk);		
			wbs_adr <= IS_BASE;			
			wbs_adr[11:2] <= offset[11:2];	//only provide DW address 
			
			wbs_wdata <= data;
			wbs_sel <= sel;
			wbs_cyc <= 1'b1;
			wbs_stb <= 1'b1;
			wbs_we <= 1'b1;	

			@(posedge soc_coreclk);
			while(wbs_ack==0) begin
				@(posedge soc_coreclk);
			end

			$display($time, "=> soc_is_cfg_write : wbs_adr=%x, wbs_sel=%b, wbs_wdata=%x", wbs_adr, wbs_sel, wbs_wdata); 
		end
	endtask

	task soc_is_cfg_read;
		input [11:0] offset;		//4K range
		input [3:0] sel;
		
		begin
			@ (posedge soc_coreclk);		
			wbs_adr <= IS_BASE;			
			wbs_adr[11:2] <= offset[11:2];	//only provide DW address 
			
			wbs_sel <= sel;
			wbs_cyc <= 1'b1;
			wbs_stb <= 1'b1;
			wbs_we <= 1'b0;	

			@(posedge soc_coreclk);
			while(wbs_ack==0) begin
				@(posedge soc_coreclk);
			end

			$display($time, "=> soc_is_cfg_read : wbs_adr=%x, wbs_sel=%b", wbs_adr, wbs_sel); 
			//#1;		//add delay to make sure cfg_read_data_captured get the correct data 
			@(soc_cfg_read_event);
			$display($time, "=> soc_is_cfg_read : got soc_cfg_read_event"); 
		end
	endtask

	task soc_aa_cfg_write;
		input [11:0] offset;		//4K range
		input [3:0] sel;
		input [31:0] data;
		
		begin
			@ (posedge soc_coreclk);		
			wbs_adr <= AA_BASE;
			wbs_adr[11:2] <= offset[11:2];	//only provide DW address 
			
			wbs_wdata <= data;
			wbs_sel <= sel;
			wbs_cyc <= 1'b1;
			wbs_stb <= 1'b1;
			wbs_we <= 1'b1;	
			
			@(posedge soc_coreclk);
			while(wbs_ack==0) begin
				@(posedge soc_coreclk);
			end

			$display($time, "=> soc_aa_cfg_write : wbs_adr=%x, wbs_sel=%b, wbs_wdata=%x", wbs_adr, wbs_sel, wbs_wdata); 
		end
	endtask

	task soc_aa_cfg_read;
		input [11:0] offset;		//4K range
		input [3:0] sel;
		
		begin
			@ (posedge soc_coreclk);		
			wbs_adr <= AA_BASE;
			wbs_adr[11:2] <= offset[11:2];	//only provide DW address 
			
			wbs_sel <= sel;
			wbs_cyc <= 1'b1;
			wbs_stb <= 1'b1;
			wbs_we <= 1'b0;		
			
			@(posedge soc_coreclk);
			while(wbs_ack==0) begin
				@(posedge soc_coreclk);
			end
			$display($time, "=> soc_aa_cfg_read : wbs_adr=%x, wbs_sel=%b", wbs_adr, wbs_sel); 
			//#1;		//add delay to make sure cfg_read_data_captured get the correct data 
			@(soc_cfg_read_event);
			$display($time, "=> soc_aa_cfg_read : got soc_cfg_read_event"); 
		end
	endtask
	
	task soc_up_cfg_write;
		input [11:0] offset;		//4K range
		input [3:0] sel;
		input [31:0] data;
		
		begin
			@ (posedge soc_coreclk);		
			wbs_adr <= UP_BASE;
			wbs_adr[11:2] <= offset[11:2];	//only provide DW address 
			
			wbs_wdata <= data;
			wbs_sel <= sel;
			wbs_cyc <= 1'b1;
			wbs_stb <= 1'b1;
			wbs_we <= 1'b1;	
			
			@(posedge soc_coreclk);
			while(wbs_ack==0) begin
				@(posedge soc_coreclk);
			end

			$display($time, "=> soc_up_cfg_write : wbs_adr=%x, wbs_sel=%b, wbs_wdata=%x", wbs_adr, wbs_sel, wbs_wdata); 
		end
	endtask	

	task soc_up_cfg_read;
		input [11:0] offset;		//4K range
		input [3:0] sel;
		
		begin
			@ (posedge soc_coreclk);		
			wbs_adr <= UP_BASE;
			wbs_adr[11:2] <= offset[11:2];	//only provide DW address 
			
			wbs_sel <= sel;
			wbs_cyc <= 1'b1;
			wbs_stb <= 1'b1;
			wbs_we <= 1'b0;		
			
			@(posedge soc_coreclk);
			while(wbs_ack==0) begin
				@(posedge soc_coreclk);
			end
			
			$display($time, "=> soc_up_cfg_read : wbs_adr=%x, wbs_sel=%b", wbs_adr, wbs_sel); 
			//#1;		//add delay to make sure cfg_read_data_captured get the correct data 
			@(soc_cfg_read_event);
			$display($time, "=> soc_up_cfg_read : got soc_cfg_read_event"); 
		end
	endtask


	task fpga_cfg_write;		//input addr, data, strb and valid_delay 
		input [pADDR_WIDTH-1:0] axi_awaddr;
		input [pDATA_WIDTH-1:0] axi_wdata;
		input [3:0] axi_wstrb;
		input [7:0] valid_delay;
		
		begin
			fpga_axi_awaddr <= axi_awaddr;
			fpga_axi_awvalid <= 0;
			fpga_axi_wdata <= axi_wdata;
			fpga_axi_wstrb <= axi_wstrb;
			fpga_axi_wvalid <= 0;
			//$display($time, "=> fpga_delay_valid before : valid_delay=%x", valid_delay); 
			repeat (valid_delay) @ (posedge fpga_coreclk);
			//$display($time, "=> fpga_delay_valid after  : valid_delay=%x", valid_delay); 
			fpga_axi_awvalid <= 1;
			fpga_axi_wvalid <= 1;
			@ (posedge fpga_coreclk);
			while (fpga_axi_awready == 0) begin		//assume both fpga_axi_awready and fpga_axi_wready assert as the same time.
					@ (posedge fpga_coreclk);
			end
			$display($time, "=> fpga_cfg_write : fpga_axi_awaddr=%x, fpga_axi_awvalid=%b, fpga_axi_awready=%b, fpga_axi_wdata=%x, axi_wstrb=%x, fpga_axi_wvalid=%b, fpga_axi_wready=%b", fpga_axi_awaddr, fpga_axi_awvalid, fpga_axi_awready, fpga_axi_wdata, axi_wstrb, fpga_axi_wvalid, fpga_axi_wready); 
			fpga_axi_awvalid <= 0;
			fpga_axi_wvalid <= 0;
		end
		
	endtask

endmodule




