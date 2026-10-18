`timescale 1ns / 1ps
// Active-high physical controls. All outputs remain in the clk domain.
module PuyoInput #(
    parameter integer CLK_HZ = 25000000,
    parameter integer DEBOUNCE_MS = 10,
    parameter integer DAS_MS = 180,
    parameter integer ARR_MS = 60
)(
    input wire clk, reset, tick_ms,
    input wire raw_left, raw_right, raw_down,
    input wire raw_rot_l, raw_rot_r, raw_restart,
    output reg event_left, event_right,
    output reg event_rot_l, event_rot_r, event_restart,
    output wire soft_drop
);
    localparam integer DB = (DEBOUNCE_MS < 1) ? 1 : DEBOUNCE_MS;
    localparam integer DAS = (DAS_MS < 1) ? 1 : DAS_MS;
    localparam integer ARR = (ARR_MS < 1) ? 1 : ARR_MS;
    wire [5:0] raw = {raw_restart,raw_rot_r,raw_rot_l,raw_down,raw_right,raw_left};
    (* ASYNC_REG = "TRUE" *) reg [5:0] sync_meta, sync_clean;
    reg [5:0] stable, previous;
    reg [31:0] debounce_count [0:5];
    wire [1:0] desired_direction = stable[1:0] == 2'b01 ? 2'b01 :
                                   stable[1:0] == 2'b10 ? 2'b10 : 2'b00;
    reg [1:0] direction;
    reg repeating;
    reg [31:0] repeat_count;
    integer b;
    assign soft_drop = stable[2];

    // Two flip-flops precede the millisecond-domain stability test.
    always @(posedge clk) begin
        if (reset) begin
            sync_meta <= 0;
            sync_clean <= 0;
            stable <= 0;
            for (b=0;b<6;b=b+1) debounce_count[b] <= 0;
        end else begin
            sync_meta <= raw;
            sync_clean <= sync_meta;
            if (tick_ms) begin
                for (b=0;b<6;b=b+1) begin
                    if (sync_clean[b] == stable[b]) debounce_count[b] <= 0;
                    else if (debounce_count[b] == DB-1) begin
                        stable[b] <= sync_clean[b];
                        debounce_count[b] <= 0;
                    end else debounce_count[b] <= debounce_count[b] + 1;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            previous <= 0;
            direction <= 0;
            repeating <= 0;
            repeat_count <= 0;
            event_left <= 0;
            event_right <= 0;
            event_rot_l <= 0;
            event_rot_r <= 0;
            event_restart <= 0;
        end else begin
            previous <= stable;
            event_left <= 0;
            event_right <= 0;
            event_rot_l <= stable[3] && !previous[3];
            event_rot_r <= stable[4] && !previous[4];
            event_restart <= stable[5] && !previous[5];
            // Both directions together cancel movement, including repeat.
            // Releasing one of the two begins a fresh hold of the other.
            if (desired_direction != direction) begin
                direction <= desired_direction;
                repeat_count <= 0;
                repeating <= 0;
                event_left <= desired_direction == 2'b01;
                event_right <= desired_direction == 2'b10;
            end else if (desired_direction == 0) begin
                repeat_count <= 0;
                repeating <= 0;
            end else if (tick_ms) begin
                if ((!repeating && repeat_count == DAS-1) ||
                    (repeating && repeat_count == ARR-1)) begin
                    event_left <= desired_direction == 2'b01;
                    event_right <= desired_direction == 2'b10;
                    repeat_count <= 0;
                    repeating <= 1;
                end else repeat_count <= repeat_count + 1;
            end
        end
    end
endmodule
