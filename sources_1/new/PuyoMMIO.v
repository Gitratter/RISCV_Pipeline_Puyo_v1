`timescale 1ns/1ps
`default_nettype none
// One transfer per valid && ready edge. The CPU owns input consumption;
// the hardware engine owns all writes to its board.
module PuyoMMIO(
    input wire clk, reset,
    input wire valid, write,
    input wire [31:0] address, write_data,
    output wire ready,
    output reg [31:0] read_data,
    input wire event_left, event_right, event_rot_l, event_rot_r, event_restart,
    input wire soft_drop, busy, game_over, active_valid,
    input wire [7:0] game_state, chain, last_chain,
    input wire [31:0] score, milliseconds,
    input wire [251:0] board_flat,
    input wire [2:0] next_a, next_b,
    input wire [31:0] counter_cycle, counter_instret, counter_mem_stall,
    input wire [31:0] counter_load_stall, counter_flush,
    output reg start_enable,
    output reg command_left, command_right, command_rot_l, command_rot_r,
    output reg command_restart, command_soft_drop
);
    reg [5:0] pending;
    reg [6:0] board_index;
    wire [5:0] events_now = {event_restart, 1'b0,
        event_rot_r && !busy, event_rot_l && !busy,
        event_right && !busy, event_left && !busy};
    wire transfer = valid && ready;
    wire take_events = transfer && !write && address == 32'h2010;
    assign ready = !reset;
    always @(*) begin
        read_data = 0;
        case (address)
            32'h2000: read_data = {31'd0,start_enable};
            32'h2004: read_data = {16'd0, game_state, 4'd0,active_valid,game_over,busy,start_enable};
            32'h2008: read_data = score;
            32'h200c: read_data = {16'd0,last_chain,chain};
            32'h2010: read_data = {26'd0,pending[5],soft_drop,pending[3:0]};
            32'h2018: read_data = milliseconds;
            32'h201c: read_data = {26'd0,next_b,next_a};
            32'h2020: read_data = {25'd0,board_index};
            32'h2024: if(board_index < 84) read_data = {29'd0,board_flat[board_index*3 +: 3]};
            32'h2030: read_data = counter_cycle;
            32'h2034: read_data = counter_instret;
            32'h2038: read_data = counter_mem_stall;
            32'h203c: read_data = counter_load_stall;
            32'h2040: read_data = counter_flush;
            32'h2044: read_data = 32'h5055594f; // 'PUYO', platform ID
            default: read_data = 0; // Reserved aligned words: read zero, writes ignored.
        endcase
    end
    always @(posedge clk) begin
        if (reset) begin
            pending <= 0; board_index <= 0; start_enable <= 0;
            command_left <= 0; command_right <= 0;
            command_rot_l <= 0; command_rot_r <= 0;
            command_restart <= 0; command_soft_drop <= 0;
        end else begin
            command_left <= 0; command_right <= 0;
            command_rot_l <= 0; command_rot_r <= 0; command_restart <= 0;
            // A simultaneous event survives a read-to-clear transaction.
            if(take_events) pending <= events_now;
            else if(busy) pending <= {pending[5] | event_restart,5'b0};
            else pending <= pending | events_now;
            if(transfer && write) begin
                case(address)
                    32'h2000: start_enable <= write_data[0];
                    32'h2014: begin
                        command_soft_drop <= write_data[4];
                        command_restart <= write_data[5];
                        if(write_data[5]) begin pending <= 0; command_soft_drop <= 0; end
                        else if(!busy && !game_over) begin
                            command_left <= write_data[0] && !write_data[1];
                            command_right <= write_data[1] && !write_data[0];
                            command_rot_l <= write_data[2] && !write_data[3];
                            command_rot_r <= write_data[3] && !write_data[2];
                        end
                    end
                    32'h2020: board_index <= write_data[6:0];
                    default: ;
                endcase
            end
        end
    end
endmodule
`default_nettype wire
