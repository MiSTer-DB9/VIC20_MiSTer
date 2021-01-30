//============================================================================
//  VIC20
//
//  Port to MiSTer
//  Copyright (C) 2017-2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================


module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output [11:0] VIDEO_ARX,
	output [11:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler

`ifdef USE_FB
	// Use framebuffer in DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

`ifdef USE_DDRAM
	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,
`endif

`ifdef USE_SDRAM
	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,
`endif

`ifdef DUAL_SDRAM
	//Secondary SDRAM
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	output	USER_OSD,
output	[1:0] USER_MODE,
input	[7:0] USER_IN,
output	[7:0] USER_OUT,

	input         OSD_STATUS
);

assign ADC_BUS  = 'Z;
wire         CLK_JOY = CLK_50M;         //Assign clock between 40-50Mhz
wire   [2:0] JOY_FLAG  = {status[30],status[31],status[29]}; //Assign 3 bits of status (31:29) o (63:61)
wire         JOY_CLK, JOY_LOAD, JOY_SPLIT, JOY_MDSEL;
wire   [5:0] JOY_MDIN  = JOY_FLAG[2] ? {USER_IN[6],USER_IN[3],USER_IN[5],USER_IN[7],USER_IN[1],USER_IN[2]} : '1;
wire         JOY_DATA  = JOY_FLAG[1] ? USER_IN[5] : '1;
assign       USER_OUT  = JOY_FLAG[2] ? {3'b111,JOY_SPLIT,3'b111,JOY_MDSEL} : JOY_FLAG[1] ? {6'b111111,JOY_CLK,JOY_LOAD} : '1;
assign       USER_MODE = JOY_FLAG[2:1] ;
assign       USER_OSD  = joydb_1[10] & joydb_1[6];

assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
 
assign LED_USER  = ioctl_download | led_disk | tape_led;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;
assign VGA_SCALER= 0;

wire [1:0] ar = status[20:19];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v" 
parameter CONF_STR = {
	"VIC20;;",
	"-;",
	"F1,PRG;",
	"F2,CRT,Load Cart;",
	"F3,CT?,Load Cart;",
	"S0,D64;",
	"-;",
	"F5,TAP,Tape Load;",
	"RG,Tape Play/Pause;",
	"RI,Tape Unload;",
	"OH,Tape Sound,Off,On;",
	"-;",
	"OJK,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O24,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"OUV,UserIO Joystick,Off,DB9MD,DB15 ;",
	"OT,UserIO Players, 1 Player,2 Players;",
	"-;",
	"OCD,Screen center,Both,None,Horz,Vert;",
	"OE,TV mode,PAL,NTSC;",
	"O6,ExtRAM 1,Off,$0400(3KB);",
	"O78,ExtRAM 2,Off,$2000-$3FFF(8KB),$2000-$5FFF(16KB),$2000-$7FFF(24KB);",
	"O9,ExtRAM 3,Off,$A000(8KB);",
	"OB,Cart is writable,No,Yes;", 
	"OF,Kernal,Loadable,Standard;",
	"R0,Reset;",
	"J,Fire;",
	"V,v",`BUILD_DATE
};

wire      extram1 = status[6];
reg [2:0] extram2;
wire      extram3 = status[9];

always_comb begin
	case(status[8:7])
		0: extram2 <= 0;
		1: extram2 <= 1;
		2: extram2 <= 3;
		3: extram2 <= 7;
	endcase
end

/////////////////  CLOCKS  ////////////////////////

wire pal = ~status[14];

wire clk_sys;
pll pll
(
	.refclk(CLK_50M),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.outclk_0(clk_sys),
	.outclk_1(CLK_VIDEO)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
reg         cfg_write;
reg   [5:0] cfg_address;
reg  [31:0] cfg_data;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

reg tv_reset = 0;
always @(posedge CLK_50M) begin
	reg pald = 0, pald2 = 0;
	reg [2:0] state = 0;

	pald  <= pal;
	pald2 <= pald;

	cfg_write <= 0;
	if(pald2 != pald) state <= 1;

	if(!cfg_waitrequest) begin
		if(state) state<=state+1'd1;
		case(state)
			0: tv_reset <= 0;
			1: begin
					tv_reset <= 1;
					cfg_address <= 0;
					cfg_data <= 0;
					cfg_write <= 1;
				end
			3: begin
					cfg_address <= 7;
					cfg_data <= pald2 ? 3999921597 : 702796321;
					cfg_write <= 1;
				end
			5: begin
					cfg_address <= 2;
					cfg_data <= 0;
					cfg_write <= 1;
				end
		endcase
	end
end

reg v20_en = 0;
always @(negedge clk_sys) begin
	reg [1:0] div = 0;

	div <= div + 1'd1;
	v20_en <= !div;
end


/////////////////  HPS  ///////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire [15:0] joya_USB, joyb_USB;
wire [10:0] ps2_key;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
reg         ioctl_wait;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire [31:0] ioctl_file_ext;
wire        forced_scandoubler;

wire [31:0] sd_lba;
wire        sd_rd;
wire        sd_wr;
wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire        img_readonly;

wire [21:0] gamma_bus;

// F1 U D L R 
wire [31:0] joya = joydb_1ena ? (OSD_STATUS? 32'b000000 : {joydb_1[5]|joydb_1[4],joydb_1[3:0]}) : joya_USB;
wire [31:0] joyb = joydb_2ena ? (OSD_STATUS? 32'b000000 : {joydb_1[5]|joydb_1[4],joydb_1[3:0]}) : joydb_1ena ? joya_USB : joyb_USB;

wire [15:0] joydb_1 = JOY_FLAG[2] ? JOYDB9MD_1 : JOY_FLAG[1] ? JOYDB15_1 : '0;
wire [15:0] joydb_2 = JOY_FLAG[2] ? JOYDB9MD_2 : JOY_FLAG[1] ? JOYDB15_2 : '0;
wire        joydb_1ena = |JOY_FLAG[2:1]              ;
wire        joydb_2ena = |JOY_FLAG[2:1] & JOY_FLAG[0];

//----BA 9876543210
//----MS ZYXCBAUDLR
reg [15:0] JOYDB9MD_1,JOYDB9MD_2;
joy_db9md joy_db9md
(
  .clk       ( CLK_JOY    ), //40-50MHz
  .joy_split ( JOY_SPLIT  ),
  .joy_mdsel ( JOY_MDSEL  ),
  .joy_in    ( JOY_MDIN   ),
  .joystick1 ( JOYDB9MD_1 ),
  .joystick2 ( JOYDB9MD_2 )	  
);

//----BA 9876543210
//----LS FEDCBAUDLR
reg [15:0] JOYDB15_1,JOYDB15_2;
joy_db15 joy_db15
(
  .clk       ( CLK_JOY   ), //48MHz
  .JOY_CLK   ( JOY_CLK   ),
  .JOY_DATA  ( JOY_DATA  ),
  .JOY_LOAD  ( JOY_LOAD  ),
  .joystick1 ( JOYDB15_1 ),
  .joystick2 ( JOYDB15_2 )	  
);

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),

	.joy_raw(OSD_STATUS? (joydb_1[5:0]|joydb_2[5:0]) : 6'b000000 ),
	.ps2_key(ps2_key),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_file_ext(ioctl_file_ext),
	.ioctl_wait(ioctl_wait),

	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),

	.joystick_0(joya_USB),
	.joystick_1(joyb_USB)
);

/////////////////  RESET  /////////////////////////

wire sys_reset = RESET | status[0] | buttons[1];
wire reset = sys_reset | cart_reset;

////////////////  LOADING  ////////////////////////

reg  [15:0] dl_addr;
reg   [7:0] dl_data;
reg         dl_wr;
reg         cart_reset = 0;
reg   [4:0] cart_blk = 0;

always @(posedge clk_sys) begin
	reg        old_download = 0;
	reg  [3:0] state = 0;
	reg [15:0] addr;

	dl_wr <= 0;
	old_download <= ioctl_download;

	if(ioctl_download && (ioctl_index == 1)) begin
		state <= 0;
		if(ioctl_wr) begin
			     if(ioctl_addr == 0) addr[7:0]  <= ioctl_dout;
			else if(ioctl_addr == 1) addr[15:8] <= ioctl_dout;
			else begin
				if(addr<'hA000) begin
					dl_addr <= addr;
					dl_data <= ioctl_dout;
					dl_wr   <= 1;
					addr    <= addr + 1'd1;
				end
			end
		end
	end

	if(old_download && ~ioctl_download && (ioctl_index == 1)) state <= 1;
	if(state) state <= state + 1'd1;

	case(state)
		 1: begin dl_addr <= 16'h2d; dl_data <= addr[7:0];  dl_wr <= 1; end
		 3: begin dl_addr <= 16'h2e; dl_data <= addr[15:8]; dl_wr <= 1; end
		 5: begin dl_addr <= 16'h2f; dl_data <= addr[7:0];  dl_wr <= 1; end
		 7: begin dl_addr <= 16'h30; dl_data <= addr[15:8]; dl_wr <= 1; end
		 9: begin dl_addr <= 16'h31; dl_data <= addr[7:0];  dl_wr <= 1; end
		11: begin dl_addr <= 16'h32; dl_data <= addr[15:8]; dl_wr <= 1; end
		13: begin dl_addr <= 16'hae; dl_data <= addr[7:0];  dl_wr <= 1; end
		15: begin dl_addr <= 16'haf; dl_data <= addr[15:8]; dl_wr <= 1; end
	endcase

	if(ioctl_download && !ioctl_index) begin
		state <= 0;
		if(ioctl_wr) begin
			if(ioctl_addr>='h4000 && ioctl_addr<'h8000) begin
				dl_addr <= ioctl_addr[15:0] + 16'h8000;
				dl_data <= ioctl_dout;
				dl_wr   <= 1;
			end
		end
	end

	if(ioctl_download && (ioctl_index[4:1] == 1)) begin
		if(ioctl_wr) begin
				  if(ioctl_addr == 0 && ioctl_index == 2) addr[7:0]  <= ioctl_dout;
			else if(ioctl_addr == 1 && ioctl_index == 2) addr[15:8] <= ioctl_dout;
			else if(addr < 'hC000) begin
				if(addr[15:13] == 3'b000) cart_blk[0] <= 1;
				if(addr[15:13] == 3'b001) cart_blk[1] <= 1;
				if(addr[15:13] == 3'b010) cart_blk[2] <= 1;
				if(addr[15:13] == 3'b011) cart_blk[3] <= 1;
				if(addr[15:13] == 3'b101) cart_blk[4] <= 1;
				dl_addr <= addr;
				dl_data <= ioctl_dout;
				dl_wr   <= 1;
				addr    <= addr + 1'd1;
			end
		end
	end

	if(old_download && ~ioctl_download && (ioctl_index[4:0] == 2)) cart_reset <= 0;
	if(sys_reset) {cart_reset, cart_blk} <= 0;

	if(~old_download & ioctl_download & (ioctl_index[4:0] == 3)) begin
		if(ioctl_file_ext[7:0] >= "2" && ioctl_file_ext[7:0] <= "9") addr <= {ioctl_file_ext[3:0],     12'h000};
		if(ioctl_file_ext[7:0] >= "A" && ioctl_file_ext[7:0] <= "B") addr <= {ioctl_file_ext[3:0]+4'd9,12'h000};
	end
end


///////////////////////////////////////////////////

wire [15:0] joy = joya | joyb;

reg [10:0] v20_key;
always @(posedge clk_sys) begin
	reg [10:0] key;
	
	key <= ps2_key;
	v20_key <= key;
end

reg rom_std;
always @(posedge clk_sys) if(reset) rom_std <= status[15];

VIC20 VIC20
(
	.i_sysclk(clk_sys),
	.i_sysclk_en(v20_en),
	.i_reset(reset|tv_reset),

	//IEC
	.atn_o(v20_iec_atn_o),
	.clk_o(v20_iec_clk_o),
	.data_o(v20_iec_data_o),
	.clk_i(c1541_iec_clk_o),
	.data_i(c1541_iec_data_o),

	.i_joy(~{joy[0],joy[1],joy[2],joy[3]}),
	.i_fire(~joy[4]),

	.i_ram_ext_ro(cart_blk & ~{5{status[11]}}),
	.i_ram_ext({extram3,extram2,extram1}|cart_blk),

	.o_ce_pix(i_ce_pix),
	.o_video_r(r),
	.o_video_g(g),
	.o_video_b(b),
	.o_hsync(hs),
	.o_vsync(vs),
	.o_hblank(hblank),
	.o_vblank(vblank),
	.i_center(status[13:12]+2'b11),
	.i_pal(pal),

	.ps2_key(v20_key),

	.o_audio(audio),

	.cass_read(cass_do),
	.cass_motor(cass_motor),
	.cass_sw(~tap_play),

	.rom_std(rom_std),
	.conf_clk(clk_sys),
	.conf_ai(dl_addr),
	.conf_di(dl_data),
	.conf_wr(dl_wr)
);

wire v20_iec_atn_o;
wire v20_iec_data_o;
wire v20_iec_clk_o;

wire [5:0] audio;

assign AUDIO_L = {1'b0,audio, 9'd0} + {cass_aud,10'd0};
assign AUDIO_R = AUDIO_L;
assign AUDIO_MIX = 0;
assign AUDIO_S = 0;

wire hs, vs, hblank, vblank, i_ce_pix;
wire [3:0] r,g,b;

wire [2:0] scale = status[4:2];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;

wire ce_sd;
assign VGA_F1 = 0;
assign VGA_SL = sl[1:0];

reg ce_pix;
always @(posedge CLK_VIDEO) begin
	reg old_ce;
	
	old_ce <= i_ce_pix;
	ce_pix <= ~old_ce & i_ce_pix;
end


wire [3:0] R,G,B;
wire VSync,HSync,HBlank,VBlank;

reg hs_o, vs_o;
always @(posedge CLK_VIDEO) begin
	if(ce_pix) begin
		hs_o <= ~hs;
		if(~hs_o & ~hs) vs_o <= ~vs;
	end
end

video_cleaner video_cleaner
(
	.clk_vid(CLK_VIDEO),
	.ce_pix(ce_pix),

	.R(r),
	.G(g),
	.B(b),

	.HSync(hs_o),
	.VSync(vs_o),
	.HBlank(hblank),
	.VBlank(vblank),

	// video output signals
	.VGA_R(R),
	.VGA_G(G),
	.VGA_B(B),
	.VGA_VS(VSync),
	.VGA_HS(HSync),

	// optional aligned blank
	.HBlank_out(HBlank),
	.VBlank_out(VBlank)
); 

video_mixer #(256, 1, 1) mixer
(
	.*,

	.clk_vid(CLK_VIDEO),
	.ce_pix_out(CE_PIXEL),

	.hq2x(scale == 1),
	.scanlines(0),
	.scandoubler(scale || forced_scandoubler),

	.mono(0)
);

///////////////////////////////////////////////////

wire led_disk;

wire c1541_iec_data_o;
wire c1541_iec_clk_o;

c1541_sd c1541_sd
(
	.clk_c1541(clk_sys & ce_c1541),
	.clk_sys(clk_sys),

	.rom_addr(ioctl_addr[13:0]),
	.rom_data(ioctl_dout),
	.rom_wr(ioctl_wr && (ioctl_addr[24:14] == 0) && !ioctl_index),
	.rom_std(rom_std),

   .disk_change(img_mounted ),
	.disk_readonly(img_readonly ),

	.iec_reset_i( reset|tv_reset ),
	.iec_atn_i  ( v20_iec_atn_o  ),
	.iec_data_i ( v20_iec_data_o ),
	.iec_clk_i  ( v20_iec_clk_o  ),
	.iec_data_o ( c1541_iec_data_o ),
	.iec_clk_o  ( c1541_iec_clk_o  ),

   .led(led_disk),

	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr)
);

reg ce_c1541;
always @(negedge clk_sys) begin
	int sum = 0;
	int msum;
	
	msum <= pal ? 35468944 : 32727260;

	ce_c1541 <= 0;
	sum = sum + 32000000;
	if(sum >= msum) begin
		sum = sum - msum;
		ce_c1541 <= 1;
	end
end 

/////////////////////////////////////////////////

assign DDRAM_CLK = clk_sys;
ddram ddram
(
	.*,
	.addr((ioctl_download & tap_load) ? ioctl_addr : tap_play_addr),
	.dout(tap_data),
	.din(ioctl_dout),
	.we(tap_wr),
	.rd(tap_rd),
	.ready(tap_data_ready)
);

reg tap_wr;
always @(posedge clk_sys) begin
	reg old_reset;

	old_reset <= reset;
	if(~old_reset && reset) ioctl_wait <= 0;

	tap_wr <= 0;
	if(ioctl_wr & tap_load) begin
		ioctl_wait <= 1;
		tap_wr <= 1;
	end
	else if(~tap_wr & ioctl_wait & tap_data_ready) begin
		ioctl_wait <= 0;
	end
end

reg        tap_rd;
wire       tap_finish;
reg [24:0] tap_play_addr;
reg [24:0] tap_last_addr;
wire [7:0] tap_data;
wire       tap_data_ready;
wire       tap_reset = reset | (ioctl_download & tap_load) | status[18] | (cass_motor & ((tap_last_addr - tap_play_addr) < 80));
reg        tap_wrreq;
wire       tap_wrfull;
wire       tap_loaded = (tap_play_addr < tap_last_addr);
reg        tap_play;
wire       tap_play_btn = status[16];
wire       tap_load = (ioctl_index == 5);

always @(posedge clk_sys) begin
	reg tap_play_btnD, tap_finishD;
	reg tap_cycle = 0;

	tap_play_btnD <= tap_play_btn;
	tap_finishD <= tap_finish;

	if(tap_reset) begin
		//C1530 module requires one more byte at the end due to fifo early check.
		tap_last_addr <= (ioctl_download & tap_load) ? ioctl_addr+2'd2 : 25'd0;
		tap_play_addr <= 0;
		tap_play <= (ioctl_download & tap_load);
		tap_rd <= 0;
		tap_cycle <= 0;
	end
	else begin
		if (~tap_play_btnD & tap_play_btn) tap_play <= ~tap_play;
		if (~tap_finishD & tap_finish) tap_play <= 0;

		tap_rd <= 0;
		tap_wrreq <= 0;

		if(~tap_rd & ~tap_wrreq) begin
			if(tap_cycle) begin
				if(tap_data_ready) begin
					tap_play_addr <= tap_play_addr + 1'd1;
					tap_cycle <= 0;
					tap_wrreq <= 1;
				end
			end
			else begin
				if(~tap_wrfull & tap_loaded) begin
					tap_rd <= 1;
					tap_cycle <= 1;
				end
			end
		end
	end
end

reg [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + (tap_play ? 4'd8 : 4'd1);
wire tape_led = tap_loaded && (act_cnt[26] ? (~(tap_play & cass_motor) && act_cnt[25:18] > act_cnt[7:0]) : act_cnt[25:18] <= act_cnt[7:0]);

wire cass_motor;
wire cass_do;
wire cass_aud = cass_do & status[17] & tap_play & ~cass_motor;

c1530 c1530
(
	.clk(clk_sys),
	.restart(tap_reset),

	.clk_freq(35468944),
	.cpu_freq(985249), // it seems this value works better than original.

	.din(tap_data),
	.wr(tap_wrreq),
	.full(tap_wrfull),
	.empty(tap_finish),

	.play(~cass_motor & tap_play),
	.dout(cass_do)
);

endmodule
