`timescale 1ns/1ps
// Standalone, bounded-state-machine Puyo-style hardware game accelerator.
// Coordinates: x=0..5, y=0..13; y=0,1 hidden; spawn pivot=(2,1).
// Color 0=empty, 1..4=game colors. orientation: up/right/down/left=0/1/2/3.
module PuyoEngine #(
    parameter integer AUTO_DROP_MS = 700,
    parameter integer SOFT_DROP_MS = 40,
    parameter integer FALL_STEP_MS = 40,
    parameter integer CLEAR_DELAY_MS = 180,
    parameter integer FIXED_SEQUENCE = 0,
    parameter SEQUENCE_FILE = "",
    parameter integer ENABLE_DEBUG = 0
)(
    input wire clk, reset, restart, tick_ms,
    input wire move_left, move_right, rotate_left, rotate_right, soft_drop,
    input wire start_enable,
    input wire dbg_mode, dbg_we,
    input wire [6:0] dbg_addr,
    input wire [2:0] dbg_data,
    input wire dbg_resolve, dbg_set_active,
    input wire [3:0] dbg_active_x, dbg_active_y,
    input wire [1:0] dbg_orientation,
    input wire [5:0] dbg_colors,
    output wire [251:0] board_flat,
    output reg active_valid,
    output reg [3:0] active_x, active_y,
    output reg [1:0] orientation,
    output reg [2:0] color_a, color_b, next_a, next_b,
    output reg [31:0] score,
    output reg [7:0] chain, last_chain,
    output reg game_over,
    output wire busy,
    output wire [7:0] state_debug,
    output reg [83:0] clear_mask
);
    localparam [7:0] S_WAIT=0, S_SPAWN=1, S_ACTIVE=2, S_LOCK=3,
        S_GRAVITY_INIT=4, S_GRAVITY=5, S_FALL_WAIT=6, S_SCAN_INIT=7,
        S_SCAN=8, S_BFS_POP=9, S_BFS_NEIGHBOR=10, S_MARK=11,
        S_CLEAR_WAIT=12, S_CLEAR=13, S_GAME_OVER=14;
    reg [7:0] state;
    reg [2:0] board [0:83];
    reg [5:0] sequence_rom [0:255];
    reg [7:0] sequence_index;
    reg [15:0] random_state;
    reg [31:0] drop_timer, animation_timer;
    reg [2:0] gravity_x;
    reg [3:0] gravity_y;
    reg gravity_moved;
    reg [83:0] visited;
    reg [6:0] queue [0:83];
    reg [7:0] scan_index, head, tail, mark_index, removed_count;
    reg [6:0] current_cell;
    reg [2:0] component_color;
    reg [1:0] neighbor_direction;
    integer init_i, reset_i, clear_i;
    genvar flat_i;
    generate for (flat_i=0; flat_i<84; flat_i=flat_i+1) begin: BOARD_VIEW
        assign board_flat[flat_i*3 +: 3] = board[flat_i];
    end endgenerate
    assign state_debug = state;
    assign busy = (state != S_ACTIVE && state != S_WAIT && state != S_GAME_OVER);

    // Constant-size initialization is supported by Vivado. A 256-line hex file
    // supplies {satellite_color,pivot_color}, each color in 1..4, when requested.
    initial begin
        for (init_i=0; init_i<256; init_i=init_i+1)
            sequence_rom[init_i] = ((init_i % 4)+1) | ((((init_i/4)%4)+1)<<3);
        if (SEQUENCE_FILE != "") $readmemh(SEQUENCE_FILE, sequence_rom);
    end

    function [15:0] advance_random;
        input [15:0] value;
        reg [15:0] r;
        integer k;
        begin
            r=value;
            for (k=0;k<4;k=k+1) r={r[14:0],r[15]^r[13]^r[12]^r[10]};
            advance_random=r;
        end
    endfunction
    wire [15:0] new_random = advance_random(random_state);

    function integer satellite_dx;
        input [1:0] dir;
        begin satellite_dx=(dir==1) ? 1 : ((dir==3) ? -1 : 0); end
    endfunction
    function integer satellite_dy;
        input [1:0] dir;
        begin satellite_dy=(dir==0) ? -1 : ((dir==2) ? 1 : 0); end
    endfunction
    function pair_fits;
        input integer px, py;
        input [1:0] dir;
        integer sx, sy;
        begin
            sx=px+satellite_dx(dir); sy=py+satellite_dy(dir);
            pair_fits=0;
            // Guard both coordinates before either variable-index board read.
            if (px>=0 && px<6 && py>=0 && py<14 && sx>=0 && sx<6 && sy>=0 && sy<14)
                pair_fits=(board[py*6+px]==0 && board[sy*6+sx]==0);
        end
    endfunction

    integer candidate_x, candidate_y;
    reg [1:0] candidate_orientation;
    reg lock_requested, drop_due;
    always @* begin
        candidate_x=active_x; candidate_y=active_y;
        candidate_orientation=orientation;
        drop_due=0; lock_requested=0;
        if (state==S_ACTIVE) begin
            if (move_left && !move_right) begin
                if (pair_fits(candidate_x-1,candidate_y,candidate_orientation)) candidate_x=candidate_x-1;
            end else if (move_right && !move_left) begin
                if (pair_fits(candidate_x+1,candidate_y,candidate_orientation)) candidate_x=candidate_x+1;
            end
            if (rotate_left && !rotate_right) begin
                if (pair_fits(candidate_x,candidate_y,candidate_orientation-2'd1))
                    candidate_orientation=candidate_orientation-2'd1;
            end else if (rotate_right && !rotate_left) begin
                if (pair_fits(candidate_x,candidate_y,candidate_orientation+2'd1))
                    candidate_orientation=candidate_orientation+2'd1;
            end
            drop_due=tick_ms && (soft_drop ?
                ((SOFT_DROP_MS<=1) || (drop_timer>=SOFT_DROP_MS-1)) :
                ((AUTO_DROP_MS<=1) || (drop_timer>=AUTO_DROP_MS-1)));
            if (drop_due) begin
                if (pair_fits(candidate_x,candidate_y+1,candidate_orientation)) candidate_y=candidate_y+1;
                else lock_requested=1;
            end
        end
    end

    integer neighbor_index, cell_x, cell_y;
    reg neighbor_valid;
    always @* begin
        cell_x=current_cell%6; cell_y=current_cell/6;
        neighbor_index=0; neighbor_valid=0;
        case (neighbor_direction)
            0: if (cell_x>0) begin neighbor_index=current_cell-1; neighbor_valid=1; end
            1: if (cell_x<5) begin neighbor_index=current_cell+1; neighbor_valid=1; end
            2: if (cell_y>0) begin neighbor_index=current_cell-6; neighbor_valid=1; end
            3: if (cell_y<13) begin neighbor_index=current_cell+6; neighbor_valid=1; end
        endcase
    end
    wire [6:0] gravity_index = gravity_y*6+gravity_x;
    wire gravity_can_move = (board[gravity_index]!=0 && board[gravity_index+7'd6]==0);

    // The sole owner of board storage, including debug fixture writes.
    always @(posedge clk) begin
        if (reset || restart) begin
            for (reset_i=0;reset_i<84;reset_i=reset_i+1) begin
                board[reset_i]<=0;
                queue[reset_i]<=0;
            end
            state<=S_WAIT; active_valid<=0; active_x<=2; active_y<=1; orientation<=0;
            color_a<=0; color_b<=0;
            if (FIXED_SEQUENCE) begin next_a<=sequence_rom[0][2:0]; next_b<=sequence_rom[0][5:3]; end
            else begin next_a<=3'd2; next_b<=3'd1; end // 16'hACE1 low bit pairs
            sequence_index<=1; random_state<=16'hACE1;
            score<=0; chain<=0; last_chain<=0; game_over<=0;
            clear_mask<=0; visited<=0; drop_timer<=0; animation_timer<=0;
            gravity_x<=0; gravity_y<=12; gravity_moved<=0;
            scan_index<=0; head<=0; tail<=0; mark_index<=0; removed_count<=0;
            current_cell<=0; component_color<=0; neighbor_direction<=0;
        end else if (ENABLE_DEBUG && dbg_mode) begin
            if (dbg_we && dbg_addr<84 && dbg_data<=4) board[dbg_addr]<=dbg_data;
            if (dbg_resolve) begin
                state<=S_GRAVITY_INIT; active_valid<=0; chain<=0; last_chain<=0;
                clear_mask<=0; visited<=0; drop_timer<=0; animation_timer<=0;
                head<=0; tail<=0; mark_index<=0; removed_count<=0; scan_index<=0;
                current_cell<=0; component_color<=0; neighbor_direction<=0; game_over<=0;
            end else if (dbg_set_active && pair_fits(dbg_active_x,dbg_active_y,dbg_orientation)) begin
                active_x<=dbg_active_x; active_y<=dbg_active_y; orientation<=dbg_orientation;
                color_a<=dbg_colors[2:0]; color_b<=dbg_colors[5:3];
                active_valid<=1; state<=S_ACTIVE; game_over<=0; drop_timer<=0;
                chain<=0; last_chain<=0;
            end
        end else begin
            case(state)
                S_WAIT: if (start_enable) state<=S_SPAWN;
                S_SPAWN: begin
                    chain<=0; drop_timer<=0;
                    if (!pair_fits(2,1,0)) begin
                        active_valid<=0; game_over<=1; state<=S_GAME_OVER;
                    end else begin
                        active_x<=2; active_y<=1; orientation<=0; active_valid<=1;
                        color_a<=next_a; color_b<=next_b;
                        if (FIXED_SEQUENCE) begin
                            next_a<=sequence_rom[sequence_index][2:0]; next_b<=sequence_rom[sequence_index][5:3];
                            sequence_index<=sequence_index+1'b1;
                        end else begin
                            next_a<={1'b0,new_random[1:0]}+3'd1;
                            next_b<={1'b0,new_random[3:2]}+3'd1;
                            random_state<=new_random;
                        end
                        state<=S_ACTIVE;
                    end
                end
                S_ACTIVE: begin
                    active_x<=candidate_x[3:0]; active_y<=candidate_y[3:0]; orientation<=candidate_orientation;
                    if (drop_due) drop_timer<=0;
                    else if (tick_ms) drop_timer<=drop_timer+1'b1;
                    if (lock_requested) state<=S_LOCK;
                end
                S_LOCK: begin
                    board[active_y*6+active_x]<=color_a;
                    board[(active_y+satellite_dy(orientation))*6+active_x+satellite_dx(orientation)]<=color_b;
                    active_valid<=0; state<=S_GRAVITY_INIT;
                end
                S_GRAVITY_INIT: begin
                    gravity_x<=0; gravity_y<=12; gravity_moved<=0; state<=S_GRAVITY;
                end
                S_GRAVITY: begin
                    if (gravity_can_move) begin
                        board[gravity_index+7'd6]<=board[gravity_index]; board[gravity_index]<=0; gravity_moved<=1;
                    end
                    if (gravity_y==0) begin
                        gravity_y<=12;
                        if (gravity_x==5) begin
                            animation_timer<=0;
                            if (gravity_moved || gravity_can_move) state<=S_FALL_WAIT;
                            else state<=S_SCAN_INIT;
                        end else gravity_x<=gravity_x+1'b1;
                    end else gravity_y<=gravity_y-1'b1;
                end
                S_FALL_WAIT: if (tick_ms) begin
                    if ((FALL_STEP_MS<=1) || animation_timer>=FALL_STEP_MS-1) state<=S_GRAVITY_INIT;
                    else animation_timer<=animation_timer+1'b1;
                end
                S_SCAN_INIT: begin
                    visited<=0; clear_mask<=0; scan_index<=0; removed_count<=0; state<=S_SCAN;
                end
                S_SCAN: begin
                    if (scan_index==84) begin
                        if (removed_count!=0) begin animation_timer<=0; state<=S_CLEAR_WAIT; end
                        else state<=S_SPAWN;
                    end else if (visited[scan_index] || board[scan_index]==0) scan_index<=scan_index+1'b1;
                    else begin
                        visited[scan_index]<=1; queue[0]<=scan_index[6:0]; head<=0; tail<=1;
                        component_color<=board[scan_index]; state<=S_BFS_POP;
                    end
                end
                S_BFS_POP: begin
                    if (head==tail) begin
                        if (tail>=4) begin mark_index<=0; state<=S_MARK; end
                        else begin scan_index<=scan_index+1'b1; state<=S_SCAN; end
                    end else begin
                        current_cell<=queue[head]; head<=head+1'b1; neighbor_direction<=0; state<=S_BFS_NEIGHBOR;
                    end
                end
                S_BFS_NEIGHBOR: begin
                    if (neighbor_valid) begin
                        if (!visited[neighbor_index] && board[neighbor_index]==component_color) begin
                            visited[neighbor_index]<=1;
                            if (tail<84) begin queue[tail]<=neighbor_index[6:0]; tail<=tail+1'b1; end
                        end
                    end
                    if (neighbor_direction==3) state<=S_BFS_POP;
                    else neighbor_direction<=neighbor_direction+1'b1;
                end
                S_MARK: begin
                    clear_mask[queue[mark_index]]<=1; removed_count<=removed_count+1'b1;
                    if (mark_index+1'b1==tail) begin scan_index<=scan_index+1'b1; state<=S_SCAN; end
                    else mark_index<=mark_index+1'b1;
                end
                S_CLEAR_WAIT: if (tick_ms) begin
                    if ((CLEAR_DELAY_MS<=1) || animation_timer>=CLEAR_DELAY_MS-1) state<=S_CLEAR;
                    else animation_timer<=animation_timer+1'b1;
                end
                S_CLEAR: begin
                    for (clear_i=0;clear_i<84;clear_i=clear_i+1)
                        if (clear_mask[clear_i]) board[clear_i]<=0;
                    score<=score+removed_count*32'd10*(chain+32'd1);
                    chain<=chain+1'b1; last_chain<=chain+1'b1;
                    clear_mask<=0; state<=S_GRAVITY_INIT;
                end
                S_GAME_OVER: begin active_valid<=0; end
                default: state<=S_WAIT;
            endcase
        end
    end
endmodule
