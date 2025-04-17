interface i2c_if #(
    int I2C_ADDR_WIDTH = 7,
    int I2C_DATA_WIDTH = 8
)(
    wand scl,
    wand sda
);

    //*******************************   Declaration of variables to be used in i2c_if         *****************************************//
    logic SLC = 1'b0;
    logic SLV = 1'b0;
    logic I2C_Start = 1'b0;
    logic I2C_Stop = 1'b0;
    bit [I2C_ADDR_WIDTH-1:0] addr;
    bit [I2C_DATA_WIDTH-1:0] store_write;
    bit [I2C_DATA_WIDTH-1:0] memq [$];
    bit [I2C_DATA_WIDTH-1:0] rm [];
    bit [I2C_DATA_WIDTH-1:0] temp_rm [];
    bit [I2C_DATA_WIDTH-1:0] twd [];
    bit monitor_done;
    typedef bit i2c_op_t;
    bit [I2C_ADDR_WIDTH-1:0] monitor_address;
    i2c_op_t mon_op;
    bit [I2C_DATA_WIDTH-1:0] monitor_data;
    bit [I2C_DATA_WIDTH-1:0] monitor_memq [$];
    bit [I2C_DATA_WIDTH-1:0] temp_data[]; //for displaying in monitor

    //*********************************************************************************************************************************//

    initial begin : I2C_Start_C //Slave start condition - when sda goes high to low when scl is high
        forever begin
            @(negedge sda);
            if (scl == 1'b1) begin
                I2C_Start = 1'b1;
            end
        end
    end

    initial begin : I2C_Stop_C //Slave stop condition - when sda goes low to high when scl is high
        forever begin
            @(posedge sda);
            if (scl == 1'b1) begin
                I2C_Stop = 1'b1;
            end
        end
    end

    assign sda = SLC ? SLV : 1'bz;

    task wait_for_i2c_transfer(output i2c_op_t op, output bit [I2C_DATA_WIDTH-1:0] write_data[]);
        wait(I2C_Start == 1'b1); //waiting for I2C_Start
        I2C_Start = 1'b0;
        for (int i = 0; i < 7; i++) begin //get address from sda
            @(posedge scl);
            addr = {addr, sda};
        end
        @(posedge scl); //get Read/Write Operation command from the 8th bit
        op = sda;
        SLV = 1'b0;
        @(negedge scl); //send acknowledgement to sda
        SLC = 1'b1;
        I2C_Start = 1'b0;
        I2C_Stop = 1'b0;
        if (op == 1'b0) begin
            @(negedge scl);
            SLC = 1'b0;
            fork //This fork is for repeated start condition
                begin
                    wait(I2C_Start == 1'b1); //repeated start if the required data is not yet written
                end
                begin
                    wait(I2C_Stop == 1'b1); //wait for I2C_Stop if all data has been written
                end
                begin
                    forever begin
                        foreach (store_write[i]) begin //read data from sda and write in an array queue
                            @(posedge scl);
                            store_write[i] = sda;
                        end
                        memq.push_back(store_write); //push back into memory queue
                        SLV = 1'b0;
                        @(negedge scl);
                        SLC = 1'b1;
                        @(negedge scl);
                        SLC = 1'b0;
                    end
                end
            join_any disable fork;
            twd = new[memq.size()];
            for (int i = 0; i < memq.size(); i++) begin
                twd[i] = memq[i];
            end
            write_data = twd;
        end
        memq.delete();
    endtask

    task provide_read_data(input bit [I2C_DATA_WIDTH-1:0] read_data[], output bit transfer_complete);
        //the monitor_done is for the monitor signal to send values to display in monitor
        rm = new[read_data.size()];
        temp_rm = new[read_data.size()];
        transfer_complete = 0;
        monitor_done = 0;
        rm = read_data;
        temp_rm = read_data;
        begin
            foreach (rm[i]) begin
                @(negedge scl);
                SLC = 1'b0;
                //Need to receive ACK from master
                @(posedge scl);
                if (sda == 1'b1) begin
                    //no ack transfer remaining
                    monitor_done = 1'b1;
                    transfer_complete = 1'b1;
                end
                else begin
                    //ack continue to send remaining
                    monitor_done = 1'b0;
                    transfer_complete = 1'b0;
                end
            end
        end
        monitor_done = 1'b1;
        transfer_complete = 1'b1;
        rm.delete();
    endtask

    task monitor(output bit [I2C_ADDR_WIDTH-1:0] addr, output i2c_op_t op, output bit [I2C_DATA_WIDTH-1:0] data[]);
        //waiting for I2C_Start
        @(negedge sda);
        wait(scl == 1'b1);
        //get address from sda
        for (int i = 0; i < 7; i++) begin
            @(posedge scl);
            addr = {addr, sda};
        end
        //get R/W command
        @(posedge scl);
        op = sda;
        wait(SLV == 1'b0);
        //send ack to sda
        @(negedge scl);
        wait(SLC == 1'b1);
        if (op == 1'b0) begin
            @(negedge scl);
            wait(SLC == 1'b0);
            fork
            //repeated I2C_Start
            begin
                wait(I2C_Start == 1'b1);
            end
            begin
                wait(I2C_Stop == 1'b1);
            end
            //read data from sda and write in a array
            begin
                forever begin
                    foreach (monitor_data[i]) begin
                        @(posedge scl);
                        monitor_data[i] = sda;
                    end
                    monitor_memq.push_back(monitor_data);
                    wait(SLV == 1'b0);
                    wait(SLC == 1'b1);
                    wait(SLC == 1'b0);
                end
            end
            join_any disable fork;
            temp_data = new[monitor_memq.size()];
            for (int i = 0; i < monitor_memq.size(); i++) begin
                temp_data[i] = monitor_memq[i];
            end
            data = temp_data;
            monitor_memq.delete();
        end
        else if (op == 1'b1) begin
            wait(monitor_done == 1'b1);
            begin
                if (temp_rm.size() == 1'b0) begin
                    $display("Empty");
                end
                data = temp_rm;
                temp_rm.delete();
            end
            begin
                wait(I2C_Stop == 1'b1); //stop for monitor
            end
        end
    endtask

endinterface
