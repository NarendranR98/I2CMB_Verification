`timescale 1ns / 10ps

module top();
parameter int WB_ADDR_WIDTH = 2;
parameter int WB_DATA_WIDTH = 8;
parameter int NUM_I2C_BUSSES = 1;
parameter int I2C_ADDR_WIDTH = 7;                        
parameter int I2C_DATA_WIDTH = 8;
bit  clk;
bit  rst = 1'b1;
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

//*************************************************************************************************************************************

typedef bit i2c_op_t;
bit [WB_ADDR_WIDTH-1:0] mon_adr;
bit [WB_DATA_WIDTH-1:0] mon_dat_wr_o;
bit mon_we;
bit [I2C_ADDR_WIDTH-1:0] mon_adr_i;
i2c_op_t op_i;
bit [I2C_DATA_WIDTH-1:0] mon_data_i[] ;
reg [I2C_ADDR_WIDTH-1:0] cmdr_read_data=8'b0;;
bit[I2C_DATA_WIDTH-1:0] data_array[];
bit[I2C_DATA_WIDTH-1:0] read_data_array[];
reg [WB_DATA_WIDTH-1:0] dpr_read_data;
bit[I2C_DATA_WIDTH-1:0] read_data_array_alternate[];
bit transfer_complete = 1'b0;
int i;
bit op;
int k;

//************************************************************************************************************************************
//IICMB Registers
enum bit[1:0] {
      CSR  = 2'b00,   // Control/Status Register
      DPR  = 2'b01,   // Data/Parameter Register
      CMDR = 2'b10,   // Command Register
      FSMR = 2'b11    // FSM States Register
}registers;

// ***********************************************************************************************************************************
// Clock generator
initial begin : clk_gen
    forever #5 clk = ~clk;
end
// ****************************************************************************
// Reset generator
initial begin: rst_gen
  #113ns rst=1'b0;
end
// ****************************************************************************
// Monitor Wishbone bus and display transfers in the transcript
// initial begin: wb_monitoring
// wb_bus.monitor(adr,dat_wr_o,op);
// end
// ****************************************************************************
// Monitor Wishbone bus and display transfers in the transcript
//i2c monitor
initial begin: monitor_i2c_bus
  forever begin
    i2c_bus.monitor(mon_adr_i, op_i, mon_data_i);
    if(mon_data_i.size()>0) begin
     if(op_i==1'b0) begin
        $display("========== I2C_BUS WRITE Transfer ==========");
     end
     else if(op_i==1'b1) begin
        $display("========== I2C_BUS READ  Transfer ==========");
     end
     for(int i=0;i<mon_data_i.size();i++) begin
        $display("          Address: %h             Data: %d",mon_adr_i, mon_data_i[i]);
     end
    end
  end
end
// ****************************************************************************
// Define the flow of the simulation
initial begin: test_flow
  //*****************************start the core and interrupt
    wb_bus.master_write(CSR,8'b1xxxxxxx); //Enable the IICMB core after power-up
    wb_bus.master_write(CSR,8'b11xxxxxx); //Enable the interrupt irq
    $display("Now the Core is enabled.");

    //$display("\n ========== Task 1 : Write 32 incrementing values, from 0 to 31, to the i2c_bus ================\n");
    fork
      i2c_write();
      project_1_task_1();
    join
    //$display("\n=========== Task 2: Read 32 values from the i2c_bus ( 100 to 131 ) =============================\n");
    fork
      i2c_read();
      project_1_task_2();
    join
    //$display("\n=================== Task 3: Alternate writes and reads for 64 transfers ========================\n");
    fork
      i2c_alternate_write_read();
      project_1_task_3();
    join_any
    disable fork;

    //$display("stop at %t ns",$time);
    $finish;
end
//*****************************************************************************************************************************
task DPR_Read(); //DPR read 
  wb_bus.master_read(DPR,dpr_read_data);
endtask
//********************************************************************************************************************************

task ack_wait();
wait(irq);  //Check Interrupt
  wb_bus.master_read(CMDR, cmdr_read_data);
  if(cmdr_read_data[7] == 1'b0) begin
    $display("Slave doesnt acknowledge as DON bit didnt go high");
  end
endtask

//***************************************************************************************************************************
task i2c_write();
  i2c_bus.wait_for_i2c_transfer(op, data_array);
endtask

//***************************************************************************************************
task i2c_read();
  i2c_bus.wait_for_i2c_transfer(op, data_array);
  //$display("Slave OP  %d",op);
  
  assert (op == 1'b1) else $error("OP gone wrong task2");
  read_data_array=new[32];

  if(op==1) begin
    foreach(read_data_array[i]) begin
      read_data_array[i]=100+i;
    end
    i2c_bus.provide_read_data(read_data_array,transfer_complete);
    wait(transfer_complete==1'b1);
  end
endtask

//***************************************************************************************************
task i2c_alternate_write_read();
  k=0;
  read_data_array_alternate=new[1];
  
  repeat(128) begin  //(0-127)
    //$display("Slave Wait started task3");
    i2c_bus.wait_for_i2c_transfer(op, data_array);
    //$display("Slave OP  %d",op);
    
    if(op==1) begin
      read_data_array_alternate[0]= 63 - k;
      i2c_bus.provide_read_data(read_data_array_alternate,transfer_complete);
      wait(transfer_complete==1);
      //$display("task3 Transfer completed, %d ",transfer_complete);
      k++;
    end    
  end
endtask
/////////////////////////////////////////////////////////////////////////
task project_1_task_1(); //this is task 1 where we write values to slave 
  wb_bus.master_write(DPR,8'b00000101);//DPR Offset 0x01 R/W Access
  wb_bus.master_write(CMDR,8'bxxxxx110); //CMDR Offset 0x02 R/W Access write 110 Set BUS
  ack_wait();
  wb_bus.master_write(CMDR,8'bxxxxx100); //CMDR write 100 to start
  ack_wait();
  wb_bus.master_write(DPR,8'b00101100); //Write 0x44 to DPR for address of slave 0x22
  wb_bus.master_write(CMDR,8'bxxxxx001); //Write 001 to CMDR Write cmd
  ack_wait();
  $display("Task 1: Write 32 incrementing values, from 0 to 31, to the i2c_bus");
  for(int i=0;i<32;i++) begin 
  wb_bus.master_write(DPR,i);            //Write DPR value to slave 0x22
  wb_bus.master_write(CMDR,8'bxxxxx001); //Write 001 to CMDR Write command.
  ack_wait();
  end
  //$display("Write byte “xxxxx101” to the CMDR. This is Stop command.");
  wb_bus.master_write(CMDR,8'bxxxxx101); //Write 101 to CMDR Write cmd
  ack_wait();
endtask
/////////////////////////////////////////////////////////////////////////
task project_1_task_2();
  wb_bus.master_write(DPR,8'b00000101); //DPR Offset 0x01 R/W Access
  wb_bus.master_write(CMDR,8'bxxxxx110);//CMDR Offset 0x02 R/W Access write 110
  ack_wait();
  wb_bus.master_write(CMDR,8'bxxxxx100);//CMDR write 100 to start
  ack_wait();
  wb_bus.master_write(DPR,8'b01011001); //Write 0x89 to DPR for address of slave 0x22
  wb_bus.master_write(CMDR,8'bxxxxx001);//Write 001 to CMDR Write cmd
  ack_wait();
  $display("Task 2: Read 32 values from the i2c_bus • Return incrementing data from 100 to 131");
  for(int i = 0;i < 32; i++) begin
    wb_bus.master_write(CMDR,8'bxxxxx010);
    ack_wait();
    DPR_Read();
  end
  wb_bus.master_write(CMDR,8'bxxxxx101); //Write 101 to CMDR Write cmd - stop
  ack_wait();
endtask
//************************************************************************************************************
task project_1_task_3();
  i=64;
  wb_bus.master_write(DPR,8'b00000101);        //DPR Offset 0x01 R/W Access
  wb_bus.master_write(CMDR,8'bxxxxx110);     //CMDR Offset 0x02 R/W Access write 110 - set bus
  ack_wait();
  $display("\nTask 3: Alternate writes and reads for 64 transfers:\n");
  repeat(64) begin
  //-------------------------------------WRITE-------------------------------------------------                                            
   wb_bus.master_write(CMDR,8'bxxxxx100); ///CMDR write 100 to start
   ack_wait();
   wb_bus.master_write(DPR,8'b01000100);   //Write 0x44 to DPR for address of slave 0x22 Master Write
   wb_bus.master_write(CMDR,8'bxxxxx001);            //Write 001 to CMDR Write cmd
   ack_wait();
   wb_bus.master_write(DPR,i);             //Write DPR value to slave 0x22
   wb_bus.master_write(CMDR,8'bxxxxx001);  ////Write 001 to CMDR Write cmd
   ack_wait();
   wb_bus.master_write(CMDR,8'bxxxxx101);             //Write 101 to CMDR Write cmd
   ack_wait();
  //--------------------------------------READ------------------------------------------------                                          
   wb_bus.master_write(CMDR,8'bxxxxx100); //CMDR write 100 to start
   ack_wait();
   wb_bus.master_write(DPR,8'b01011001);   //Write 0x89 to DPR for address of slave 0x22
   wb_bus.master_write(CMDR,8'bxxxxx001);               //Write 001 to CMDR Write cmd
   ack_wait();
   wb_bus.master_write(CMDR,8'bxxxxx010);
   ack_wait();
   DPR_Read();
   wb_bus.master_write(CMDR,8'bxxxxx101); //Write 101 to CMDR Write cmd - STOP
   ack_wait();
  i++;
  end
endtask
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
// ****************************************************************************
// Instantiate the I2C Slave Bus Functional Model
i2c_if       #(
      .I2C_ADDR_WIDTH(I2C_ADDR_WIDTH),
      .I2C_DATA_WIDTH(I2C_DATA_WIDTH)
      )
i2c_bus (
  // SCL and SDA signals
    .scl(scl),
    .sda(sda)
  );
endmodule
