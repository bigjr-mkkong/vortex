`include "VX_define.vh"

'define VORTEX_ONLY_TEST
'ifdef VORTX_ONLY_TEST

`define DCP_VADDR 40
`define DCP_PADDR 40
`define TLB_SRC_IDX 2
`define TLB_SRC_NUM 2**`TLB_SRC_IDX`

'else
`include "dcp.h"`
'endif

module dcp_vortex_port(
    // Clock
    input  wire                             clk,
    input  wire                             reset,

    // MMU port
    output wire                             tlb_req_o,
    input  wire                             tlb_ack_i,
    input  wire                             tlb_exc_val_i,
    input  wire ['TLB_SEC_NUM-1  : 0]       tlb_ptw_src_i,
    output wire ['DCP_VADDR-1    : 0]       tlb_vaddr_o,
    input  wire ['DCP_PADDR-1    : 0]       tlb_paddr_i

    //PMEM req
    output wire                             mem_req_valid_o,
    output wire [`VX_MEM_ADDR_WIDTH-1:0]    mem_req_paddr_o,
    output wire                             mem_req_rw_o,
    output wire [`VX_MEM_BYTEEN_WIDTH-1:0]  mem_req_byteen_o,
    output wire [`VX_MEM_DATA_WIDTH-1:0]    mem_req_data_o,
    output wire [`VX_MEM_TAG_WIDTH-1:0]     mem_req_tag_o,
    input  wire                             mem_req_ready_i,

    //PMEM rsp
    input wire                              mem_rsp_valid_i,
    input wire [`VX_MEM_DATA_WIDTH-1:0]     mem_rsp_data_i,
    input wire [`VX_MEM_TAG_WIDTH-1:0]      mem_rsp_tag_i,
    output wire                             mem_rsp_ready_o,

    // DCR write request
    input  wire                         dcr_wr_valid,
    input  wire [`VX_DCR_ADDR_WIDTH-1:0] dcr_wr_addr,
    input  wire [`VX_DCR_DATA_WIDTH-1:0] dcr_wr_data,

    //State
    output wire                             busy
);
    
typedef enum logic [2:0]{
    INIT = 2'd1,
    WAITING_TLB = 2'd2,
    WAITING_RDY = 2'd3,
    DNE = 'X
}state_e;

    logic                             vxmem_req_valid_o;
    logic                             vxmem_req_rw_o;
    logic [`VX_MEM_BYTEEN_WIDTH-1:0]  vxmem_req_byteen_o;
    logic [`VX_MEM_ADDR_WIDTH-1:0]    vxmem_req_addr_o;
    logic [`VX_MEM_DATA_WIDTH-1:0]    vxmem_req_data_o;
    logic [`VX_MEM_TAG_WIDTH-1:0]     vxmem_req_tag_o;
    logic                             vxmem_req_ready_i;

    logic [`VX_MEM_ADDR_WIDTH-1:0]    tlbmem_req_addr_buf;

    logic                             vxmem_rsp_valid_i;
    logic [`VX_MEM_DATA_WIDTH-1:0]    vxmem_rsp_data_i;
    logic [`VX_MEM_TAG_WIDTH-1:0]     vxmem_rsp_tag_i;
    logic                             vxmem_rsp_ready_o;

    //These regs are used to preserve vortex request across state
    logic                             vxmem_req_rw_buf;
    logic [`VX_MEM_BYTEEN_WIDTH-1:0]  vxmem_req_byteen_buf;
    logic [`VX_MEM_DATA_WIDTH-1:0]    vxmem_req_data_buf;
    logic [`VX_MEM_TAG_WIDTH-1:0]     vxmem_req_tag_buf;

    logic save_req;
    logic save_paddr;

    state_e state, state_next;

    always_ff @(posedge clk) begin
        if(reset) begin
            vxmem_req_rw_buf <= 0; 
            vxmem_req_byteen_buf <= 0;
            vxmem_req_data_buf <= 0;
            vxmem_req_tag_buf <= 0;
            tlbmem_req_addr_buf <= 0;

            state <= INIT;
        end else begin
            vxmem_req_rw_buf        <= save_req	    ?   vxmem_req_rw_o      :vxmem_req_rw_buf; 
            vxmem_req_byteen_buf    <= save_req	    ?   vxmem_req_byteen_o  :vxmem_req_byteen_buf;
            vxmem_req_data_buf      <= save_req	    ?   vxmem_req_data_o    :vxmem_req_data_buf;
            vxmem_req_tag_buf       <= save_req	    ?   vxmem_req_tag_o     :vxmem_req_tag_buf;
            tlbmem_req_addr_buf     <= save_paddr	?   tlb_paddr_i         :tlbmem_req_addr_buf;

            state <= state_next;
        end
    end

    //send request to tlb
    assign tlb_vaddr_o = vxmem_req_vaddr_o;

    //send request to mem
    assign mem_req_paddr_o = tlbmem_req_addr_buf;
    assign mem_req_rw_o = vxmem_req_rw_buf;
    assign mem_req_byteen_o = vxmem_req_byteen_buf;
    assign mem_req_data_o = vxmem_req_data_buf;
    assign mem_req_tag_o = vxmem_req_tag_buf;

    //send mem rsp signals directly into vortex
    assign vxmem_rsp_valid_i = mem_rsp_valid_i;
    assign vxmem_rsp_data_i = mem_rsp_data_i;
    assign vxmem_rsp_tag_i = mem_rsp_tag_i;
    assign mem_rsp_ready_o = vxmem_rsp_ready_o;


    always_comb begin
        vxmem_req_ready_i = 0;
        mem_req_valid_o = 0;
        tlb_req_o = 0;
        save_req = 0;
        save_paddr = 0;
        case (state) begin
            INIT:
            begin
                vxmem_req_ready_i = 1;
                if(vxmem_req_valid_o) begin
                    save_req = 1;
                    state_next = WAITING_TLB;
                end else begin
                    state_next = INIT;
                end
            end

            WAITING_TLB:
            begin
                tlb_req_o = 1;
                if(tlb_ack_i) begin
                    mem_req_valid_o = 1;
                    if (mem_req_ready_i) begin
                        state_next = INIT;
                    end else begin
                        save_paddr = 1;
                        state_next = WAITING_RDY;
                    end
                end else begin
                    state_next = WAITING_TLB;
                end
            end

            WAITING_RDY:
            begin
                mem_req_valid_o = 1;
                if(mem_req_ready_i) begin
                    state_next = INIT;
                end else begin
                    state_next = WAITING_RDY;
                end
            end
        end
    end
    

    Vortex vortex (
        `SCOPE_IO_BIND  (0)

        .clk            (clk),
        .reset          (reset),

        .mem_req_valid  (vxmem_req_valid_o),
        .mem_req_rw     (vxmem_req_rw_o),
        .mem_req_byteen (vxmem_req_byteen_o),   
        .mem_req_addr   (vxmem_req_vaddr_o),
        .mem_req_data   (vxmem_req_data_o),
        .mem_req_tag    (vxmem_req_tag_o),      
        .mem_req_ready  (vxmem_req_ready_i),

        .mem_rsp_valid  (vxmem_rsp_valid_i),
        .mem_rsp_data   (vxmem_rsp_data_i),
        .mem_rsp_tag    (vxmem_rsp_tag_i),      
        .mem_rsp_ready  (vxmem_rsp_ready_o),

        .dcr_wr_valid   (dcr_wr_valid),     
        .dcr_wr_addr    (dcr_wr_addr),      
        .dcr_wr_data    (dcr_wr_data),      

        .busy           (busy)              
    );

endmodule
