`timescale 1ns/1ps
module tb_system;
    reg clk=0,reset=1;
    always #20 clk=~clk;
    reg l=0,r=0,d=0,rl=0,rr=0,re=0;
    wire [3:0] red,green,blue;
    wire hs,vs;
    wire [15:0] led;
    PuyoSystem #(.CLK_HZ(100000),.DEBOUNCE_MS(2),.DAS_MS(20),.ARR_MS(5),
        .AUTO_DROP_MS(10000),.SOFT_DROP_MS(2),.FALL_STEP_MS(1),
        .CLEAR_DELAY_MS(2),.FIXED_SEQUENCE(1)) dut(
        .clk(clk),.reset(reset),.raw_left(l),.raw_right(r),.raw_down(d),
        .raw_rot_l(rl),.raw_rot_r(rr),.raw_restart(re),
        .vga_red(red),.vga_green(green),.vga_blue(blue),.hsync(hs),.vsync(vs),.led(led));
    integer cycles=0,restarts=0,commands=0,n;
    reg [5:0] expected_next;
    always @(posedge clk) if(!reset) begin
        cycles=cycles+1;
        if(dut.fault) $fatal(1,"Supervisor CPU fault");
        if(dut.restart) restarts=restarts+1;
        if(dut.cl || dut.cr || dut.crl || dut.crr) commands=commands+1;
        if(cycles>80000) $fatal(1,"system timeout");
    end
    task wait_cycles(input integer count);
        repeat(count) @(negedge clk);
    endtask
    initial begin
        wait_cycles(5); reset=0;
        wait(dut.active); @(negedge clk);
        if(!dut.start_enable || dut.retired==0) $fatal(1,"CPU did not boot/start engine");
        if(dut.ax!=2 || dut.ay!=1 || dut.orientation!=0) $fatal(1,"spawn mismatch");
        expected_next={dut.nb,dut.na};
        l=1; wait_cycles(600); l=0; wait_cycles(400);
        if(dut.ax!=1) $fatal(1,"button -> MMIO -> CPU -> command left failed");
        rr=1; wait_cycles(5000); rr=0; wait_cycles(400);
        if(dut.orientation!=1) $fatal(1,"held rotation repeated or was lost");
        r=1; l=1; wait_cycles(4000); r=0; l=0; wait_cycles(400);
        if(dut.ax!=1) $fatal(1,"simultaneous horizontal controls moved");
        d=1; wait(dut.busy); wait(!dut.active); @(negedge clk); d=0;
        wait(dut.active); @(negedge clk);
        if({dut.cb,dut.ca}!==expected_next) $fatal(1,"next/spawn mismatch in system");
        n=0; for(integer i=0;i<84;i=i+1) if(dut.board[i*3 +:3]!=0)n=n+1;
        if(n!=2) $fatal(1,"pair not fixed through real input/CPU path");
        re=1; wait_cycles(3000);
        if(restarts!=1) $fatal(1,"held restart repeated: %0d",restarts);
        if(dut.board!==0 || dut.score!=0 || dut.chain!=0) $fatal(1,"restart did not clear game");
        re=0; wait_cycles(500); re=1; wait_cycles(500); re=0;
        if(restarts!=2) $fatal(1,"restart did not rearm on release");
        if(commands!=2) $fatal(1,"duplicate/lost CPU commands: %0d",commands);
        if(dut.cycles==0 || dut.mem_stalls==0 || dut.flushes==0) $fatal(1,"CPU counters missing");
        $display("PASS tb_system: firmware boot, real input/MMIO control, held rotation/restart, next, pair lock, counters; retire=%0d",dut.retired);
        $finish;
    end
endmodule
