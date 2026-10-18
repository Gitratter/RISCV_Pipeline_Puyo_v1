`timescale 1ns/1ps
`default_nettype none
// Portable 25 MHz subsystem; no vendor primitives here. CPU supervisor consumes
// input events and issues game commands through MMIO, not direct button wiring.
module PuyoSystem #(
    parameter integer CLK_HZ=25000000,
    parameter integer DEBOUNCE_MS=10, DAS_MS=180, ARR_MS=60,
    parameter integer AUTO_DROP_MS=700, SOFT_DROP_MS=40,
    parameter integer FALL_STEP_MS=40, CLEAR_DELAY_MS=180,
    parameter integer FIXED_SEQUENCE=0,
    parameter SEQUENCE_FILE="",
    // Vivado stages this registered Memory Initialization File into each run.
    parameter IMEM_INIT_FILE="puyo_supervisor.mem"
)(
    input wire clk, reset,
    input wire raw_left,raw_right,raw_down,raw_rot_l,raw_rot_r,raw_restart,
    output wire [3:0] vga_red,vga_green,vga_blue,
    output wire hsync,vsync,
    output wire [15:0] led
);
    wire tick_ms;
    wire [31:0] milliseconds;
    MillisecondTick #(.CLK_HZ(CLK_HZ)) timer(
        .clk(clk),.reset(reset),.tick_ms(tick_ms),.milliseconds(milliseconds));
    wire el,er,erl,err,ers,down;
    wire cl,cr,crl,crr,restart,soft_drop,start_enable;
    PuyoInput #(.CLK_HZ(CLK_HZ),.DEBOUNCE_MS(DEBOUNCE_MS),.DAS_MS(DAS_MS),.ARR_MS(ARR_MS)) controls(
        .clk(clk),.reset(reset),.tick_ms(tick_ms),
        .raw_left(raw_left),.raw_right(raw_right),.raw_down(raw_down),
        .raw_rot_l(raw_rot_l),.raw_rot_r(raw_rot_r),.raw_restart(raw_restart),
        .event_left(el),.event_right(er),.event_rot_l(erl),.event_rot_r(err),
        .event_restart(ers),.soft_drop(down));
    wire [251:0] board;
    wire [83:0] clear_mask;
    wire active,busy,game_over;
    wire [3:0] ax,ay;
    wire [1:0] orientation;
    wire [2:0] ca,cb,na,nb;
    wire [7:0] chain,last_chain,game_state;
    wire [31:0] score;
    PuyoEngine #(.AUTO_DROP_MS(AUTO_DROP_MS),.SOFT_DROP_MS(SOFT_DROP_MS),
        .FALL_STEP_MS(FALL_STEP_MS),.CLEAR_DELAY_MS(CLEAR_DELAY_MS),
        .FIXED_SEQUENCE(FIXED_SEQUENCE),.SEQUENCE_FILE(SEQUENCE_FILE)) game(
        .clk(clk),.reset(reset),.restart(restart),.tick_ms(tick_ms),
        .start_enable(start_enable),.move_left(cl),.move_right(cr),
        .rotate_left(crl),.rotate_right(crr),.soft_drop(soft_drop),
        .dbg_mode(1'b0),.dbg_we(1'b0),.dbg_addr(7'd0),.dbg_data(3'd0),
        .dbg_resolve(1'b0),.dbg_set_active(1'b0),.dbg_active_x(4'd0),
        .dbg_active_y(4'd0),.dbg_orientation(2'd0),.dbg_colors(6'd0),
        .board_flat(board),.active_valid(active),.active_x(ax),.active_y(ay),
        .orientation(orientation),.color_a(ca),.color_b(cb),.next_a(na),.next_b(nb),
        .score(score),.chain(chain),.last_chain(last_chain),.game_over(game_over),
        .busy(busy),.state_debug(game_state),.clear_mask(clear_mask));
    wire mmio_valid,mmio_write,mmio_ready;
    wire [31:0] mmio_addr,mmio_wdata,mmio_rdata;
    wire [31:0] cycles,retired,mem_stalls,load_stalls,flushes;
    wire fault;
    wire [7:0] legacy_output;
    // BRAM address/enable/write controls must not be driven by asynchronous
    // reset FFs. Retiming the board reset makes the CPU reset fully synchronous.
    reg cpu_reset = 1'b1;
    always @(posedge clk) cpu_reset <= reset;
    TD8_RISCV_V31_Core #(.IMEM_INIT_FILE(IMEM_INIT_FILE)) cpu(
        .clk(clk),.reset(cpu_reset),.cpu_enable(1'b1),.input_port(8'd0),
        .debug_reg_addr(5'd0),.output_port(legacy_output),
        .debug_pc(),.debug_instruction(),.debug_reg_data(),.debug_mem_word0(),
        .debug_trap_cause(),.debug_trap_value(),.fault(fault),
        .retire_valid(),.retire_pc(),.retire_instruction(),
        .mmio_valid(mmio_valid),.mmio_write(mmio_write),.mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata),.mmio_rdata(mmio_rdata),.mmio_ready(mmio_ready),
        .counter_cycle(cycles),.counter_instret(retired),.counter_mem_stall(mem_stalls),
        .counter_load_stall(load_stalls),.counter_flush(flushes));
    PuyoMMIO peripherals(
        .clk(clk),.reset(reset),.valid(mmio_valid),.write(mmio_write),
        .address(mmio_addr),.write_data(mmio_wdata),.ready(mmio_ready),.read_data(mmio_rdata),
        .event_left(el),.event_right(er),.event_rot_l(erl),.event_rot_r(err),.event_restart(ers),
        .soft_drop(down),.busy(busy),.game_over(game_over),.active_valid(active),
        .game_state(game_state),.chain(chain),.last_chain(last_chain),.score(score),
        .milliseconds(milliseconds),.board_flat(board),.next_a(na),.next_b(nb),
        .counter_cycle(cycles),.counter_instret(retired),.counter_mem_stall(mem_stalls),
        .counter_load_stall(load_stalls),.counter_flush(flushes),
        .start_enable(start_enable),.command_left(cl),.command_right(cr),
        .command_rot_l(crl),.command_rot_r(crr),.command_restart(restart),.command_soft_drop(soft_drop));
    wire frame_tick;
    PuyoVideo video(.clk(clk),.reset(reset),.board_flat(board),.active_valid(active),
        .active_x(ax),.active_y(ay),.orientation(orientation),.color_a(ca),.color_b(cb),
        .next_a(na),.next_b(nb),.score(score),.chain(chain),.last_chain(last_chain),
        .game_over(game_over),.busy(busy),
        .clear_mask((game_state==8'd12 || game_state==8'd13) ? clear_mask : 84'd0),
        .vga_red(vga_red),.vga_green(vga_green),.vga_blue(vga_blue),
        .hsync(hsync),.vsync(vsync),.frame_tick(frame_tick));
    assign led = {fault,game_over,busy,start_enable,retired[19:16],legacy_output};
endmodule

module TD8_RISCV_PUYO_TOP(
    input wire clk, input wire [15:0] sw,
    input wire btnL,btnR,btnD,btnU,btnC,
    output wire [3:0] vgaRed,vgaGreen,vgaBlue,
    output wire Hsync,Vsync,
    output wire [15:0] led,
    output wire [6:0] seg, output wire [3:0] an, output wire dp
);
    wire clk25,locked,reset;
    Clock25 clock_generator(.clk100(clk),.reset(sw[15]),.clk25(clk25),.locked(locked));
    ResetSync reset_synchronizer(.clk(clk25),.async_reset(sw[15] || !locked),.reset(reset));
    PuyoSystem system(.clk(clk25),.reset(reset),.raw_left(btnL),.raw_right(btnR),
        .raw_down(btnD),.raw_rot_l(btnC),.raw_rot_r(btnU),.raw_restart(sw[14]),
        .vga_red(vgaRed),.vga_green(vgaGreen),.vga_blue(vgaBlue),
        .hsync(Hsync),.vsync(Vsync),.led(led));
    assign seg=7'b1111111;
    assign an=4'b1111;
    assign dp=1'b1;
endmodule
`default_nettype wire
