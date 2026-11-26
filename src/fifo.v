// fifo.v : 8 x 16 synchronous FIFO, sky130_fd_sc_hd
//
//  * One-hot read/write pointers (advance = rotate, no decoder, flat AND-OR
//    read mux).
//  * Thermometer occupancy th[k] = (count > k): full/empty are single bits,
//    no counter, adder or pointer comparator on the critical path.
//  * dout/full/empty come straight from dedicated flops.
//  * Synchronous reset through a 2-flop synchronizer (rst_n is false-pathed
//    in fifo.sdc). Storage array has no reset.
//
// Standard (non-FWFT): a read accepted in cycle N (rd_en && !empty) shows its
// data on dout in cycle N+1. Writes when full / reads when empty are ignored.

`default_nettype none

module fifo #(
    parameter integer WIDTH = 8,
    parameter integer DEPTH = 16        // any value >= 2
) (
    input  wire             clk,
    input  wire             rst_n,      // active-low, synchronized internally
    input  wire             wr_en,
    input  wire [WIDTH-1:0] din,
    input  wire             rd_en,
    output reg  [WIDTH-1:0] dout,
    output wire             full,
    output wire             empty
);

    // ------------------------------------------------------------ reset sync
    reg [1:0] rst_sync;
    always @(posedge clk) rst_sync <= {rst_sync[0], rst_n};
    wire rst_n_i = rst_sync[1];

    // ------------------------------------------------------------ control
    reg [DEPTH-1:0] wr_ptr;             // one-hot
    reg [DEPTH-1:0] rd_ptr;             // one-hot
    reg [DEPTH-1:0] wr_slot;            // wr_ptr gated by not-full, registered

    reg [DEPTH-2:0] occ;                // th[DEPTH-2:0]
    reg             not_full;           // ~th[DEPTH-1]
    wire [DEPTH-1:0] th = {~not_full, occ};

    reg full_q, empty_q;
    assign full  = full_q;
    assign empty = empty_q;

    wire push = wr_en & not_full;
    wire pop  = rd_en & occ[0];         // occ[0] = not empty

    wire [DEPTH-1:0] th_nxt = (push & ~pop) ? {th[DEPTH-2:0], 1'b1} :
                              (pop & ~push) ? {1'b0, th[DEPTH-1:1]} :
                                              th;

    wire [DEPTH-1:0] wr_ptr_nxt = push ? {wr_ptr[DEPTH-2:0], wr_ptr[DEPTH-1]} : wr_ptr;

    always @(posedge clk) begin
        if (!rst_n_i) begin
            wr_ptr   <= {{(DEPTH-1){1'b0}}, 1'b1};
            wr_slot  <= {{(DEPTH-1){1'b0}}, 1'b1};
            rd_ptr   <= {{(DEPTH-1){1'b0}}, 1'b1};
            occ      <= {(DEPTH-1){1'b0}};
            not_full <= 1'b1;
            full_q   <= 1'b0;
            empty_q  <= 1'b1;
        end else begin
            wr_ptr   <= wr_ptr_nxt;
            wr_slot  <= wr_ptr_nxt & {DEPTH{~th_nxt[DEPTH-1]}};
            if (pop)  rd_ptr <= {rd_ptr[DEPTH-2:0], rd_ptr[DEPTH-1]};
            occ      <=  th_nxt[DEPTH-2:0];
            not_full <= ~th_nxt[DEPTH-1];
            full_q   <=  th_nxt[DEPTH-1];
            empty_q  <= ~th_nxt[0];
        end
    end

    // ------------------------------------------------------------ storage
    reg [WIDTH*DEPTH-1:0] store;        // flat vector: plain flops, no memory inference

    integer j;
    always @(posedge clk) begin
        for (j = 0; j < DEPTH; j = j + 1)
            if (wr_en & wr_slot[j])
                store[j*WIDTH +: WIDTH] <= din;
    end

    reg [WIDTH-1:0] rd_data;
    integer k;
    always @(*) begin
        rd_data = {WIDTH{1'b0}};
        for (k = 0; k < DEPTH; k = k + 1)
            rd_data = rd_data | (store[k*WIDTH +: WIDTH] & {WIDTH{rd_ptr[k]}});
    end

    always @(posedge clk) begin
        if (!rst_n_i) dout <= {WIDTH{1'b0}};
        else if (pop) dout <= rd_data;
    end

endmodule

`default_nettype wire
