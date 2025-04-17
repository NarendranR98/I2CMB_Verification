`timescale 1ns / 10ps

module top();

parameter int WB_ADDR_WIDTH = 2;
parameter int WB_DATA_WIDTH = 8;
parameter int NUM_I2C_BUSSES = 1;

bit  clk;
bit  rst;
wire cyc;
wire stb;
wire we;
tri1 ack;
wire [WB_ADDR_WIDTH-1:0] adr;
wire [WB_DATA_WIDTH-1:0] dat_wr_o;
wire [WB_DATA_WIDTH-1:0] dat_rd_i;
wire irq;
tri  [NUM_I2C_BUSSES-1:0] scl;
tri  [NUM_I2C_BUSSES-1:0] sda;

enum bit[1:0] {
      CSR  = 2'b00, 
      DPR  = 2'b01, 
      CMDR = 2'b10, 
      FSMR = 2'b11
}I2CRegs;

//temp variables
bit [WB_ADDR_WIDTH-1:0] addr_wb;
bit [WB_DATA_WIDTH-1:0] data_wb;
bit we_wb;  


// ****************************************************************************
// Clock generator
initial begin : clk_gen
    clk = 1'b0;
    forever #5 clk = ~clk;
end

// ****************************************************************************
// Reset generator
initial begin : rst_gen
     //#2ms;
     rst = 1'b1;
     //#50 $display("reset: %b",rst);
     #113 rst = 1'b0;
end 


// ****************************************************************************
// Monitor Wishbone bus and display transfers in the transcript
initial begin: wb_monitoring
     wb_bus.master_monitor(addr_wb,data_wb,we_wb);
      $display("============== transaction at %t ns ==============",$time);
     $display("addr: %h data: %h we: %b",addr_wb,data_wb,we_wb);  
end

// ****************************************************************************
// Define the flow of the simulation
initial begin : test_flow
     
     wb_bus.master_write(CSR,8'b11xxxxxx);   //Enable the IICMB core after power-up.
     
     wb_bus.master_write(DPR,8'b00000101);         //Write byte 0x05 to the DPR. This is the ID of desired I2C bus.
     wb_bus.master_write(CMDR,8'bxxxxx110);  //Write byte “xxxxx110” to the CMDR. This is Set Bus command.

     wait(irq);  // Wait for interrupt
     // (or until DON bit of CMDR reads '1' as implemented below)
     wb_bus.master_read(CMDR,data_wb);

     wb_bus.master_write(CMDR,8'bxxxxx100);  //Write byte “xxxxx100” to the CMDR. This is Start command.

     wait(irq);  // Wait for interrupt
     // (or until DON bit of CMDR reads '1' as implemented below)
     wb_bus.master_read(CMDR,data_wb); 

     wb_bus.master_write(DPR,8'b01001100);         //Write byte 0x44 to the DPR.This is the slave address 0x22 shifted 1 bit to the left + rightmost bit = '0', which means writing.
     wb_bus.master_write(CMDR,8'bxxxxx001);  //Write byte “xxxxx001” to the CMDR. This is Write command.

     wait(irq);//Wait for interrupt 
     //(or until DON bit of CMDR reads '1'.)
     wb_bus.master_read(CMDR,data_wb);  

     wb_bus.master_write(DPR,8'b01001110); //Write byte 0x78 to the DPR.This is the byte to be written.
     wb_bus.master_write(CMDR,8'bxxxxx001); //Write byte “xxxxx001” to the CMDR. This is Write command.

     wait(irq);  // Wait for interrupt
     // (or until DON bit of CMDR reads '1' as implemented below)
     wb_bus.master_read(CMDR,data_wb);

     wb_bus.master_write(CMDR,8'bxxxx101);//Write byte “xxxxx101” to the CMDR. This is Stop command.
     
     wait(irq);//Wait for interrupt 
     //(or until DON bit of CMDR reads '1'.)
     wb_bus.master_read(CMDR,data_wb);  

     #100 $finish;
end

// ****************************************************************************
// Instantiate the Wishbone master Bus Functional Model
wb_if       #(
      .ADDR_WIDTH(WB_ADDR_WIDTH),
      .DATA_WIDTH(WB_DATA_WIDTH)
      )
wb_bus (
  // System sigals
  .clk_i(clk),
  .rst_i(rst),
  // Master signals
  .cyc_o(cyc),
  .stb_o(stb),
  .ack_i(ack),
  .adr_o(adr),
  .we_o(we),
  // Slave signals
  .cyc_i(),
  .stb_i(),
  .ack_o(),
  .adr_i(),
  .we_i(),
  // Shred signals
  .dat_o(dat_wr_o),
  .dat_i(dat_rd_i)
  );

// ****************************************************************************
// Instantiate the DUT - I2C Multi-Bus Controller
\work.iicmb_m_wb(str) #(.g_bus_num(NUM_I2C_BUSSES)) DUT
  (
    // ------------------------------------
    // -- Wishbone signals:
    .clk_i(clk),         // in    std_logic;                            -- Clock
    .rst_i(rst),         // in    std_logic;                            -- Synchronous reset (active high)
    // -------------
    .cyc_i(cyc),         // in    std_logic;                            -- Valid bus cycle indication
    .stb_i(stb),         // in    std_logic;                            -- Slave selection
    .ack_o(ack),         //   out std_logic;                            -- Acknowledge output
    .adr_i(adr),         // in    std_logic_vector(1 downto 0);         -- Low bits of Wishbone address
    .we_i(we),           // in    std_logic;                            -- Write enable
    .dat_i(dat_wr_o),    // in    std_logic_vector(7 downto 0);         -- Data input
    .dat_o(dat_rd_i),    //   out std_logic_vector(7 downto 0);         -- Data output
    // ------------------------------------
    // ------------------------------------
    // -- Interrupt request:
    .irq(irq),           //   out std_logic;                            -- Interrupt request
    // ------------------------------------
    // ------------------------------------
    // -- I2C interfaces:
    .scl_i(scl),         // in    std_logic_vector(0 to g_bus_num - 1); -- I2C Clock inputs
    .sda_i(sda),         // in    std_logic_vector(0 to g_bus_num - 1); -- I2C Data inputs
    .scl_o(scl),         //   out std_logic_vector(0 to g_bus_num - 1); -- I2C Clock outputs
    .sda_o(sda)          //   out std_logic_vector(0 to g_bus_num - 1)  -- I2C Data outputs
    // ------------------------------------
  );

  // // Instantiate the I2C slave Bus Functional Model
  // i2c_if(
  //   .ADDR_WIDTH(I2C_ADDR_WIDTH),
  //     .DATA_WIDTH(I2C_DATA_WIDTH)
  // );
  // i2c_bus (// Signals : SDA (Signal data) and SCL (Signal Clock)
  //   .scl(scl),
  //   .sda(sda)
  // );

endmodule
