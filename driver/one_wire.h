#include "sleep.h"
//Number of one_wire devices to resolve
#define num_of_one_wire_dev 2
//slv_reg0
#define enable_mask 0x01
#define rd_wr_mask 0x02
#define reset_mask 0x04
#define bit_byte_mode_mask 0x08
//slv_reg1
#define transmit_data_mask 0xFF
//slv_reg2
#define receive_data_mask 0xFF
//slv_reg3
#define receive_ready_mask 0x01
#define busy_mask 0x02
#define error_mask 0x04

int *slv_reg0;
int *slv_reg1;
int *slv_reg2;
int *slv_reg3;

long int ROM_LUT[num_of_one_wire_dev];
//slv_reg1

void one_wire_config(int one_wire_base_addr){
    slv_reg0 = one_wire_base_addr + 0;
    slv_reg1 = one_wire_base_addr + 4;
    slv_reg2 = one_wire_base_addr + 8;
    slv_reg3 = one_wire_base_addr + 12;
}
//Reset-Presence hand shake function
//returns 1 if any error occurs
int ow_initialize(void){
    int error;
    *slv_reg0 = reset_mask|enable_mask;
    usleep(1024);
    *slv_reg0 = 0;
    usleep(15);
    error = (*slv_reg3 & 4) >> 2;
    return error;
}
void ow_byte_write(int data){

    *slv_reg1 = data & transmit_data_mask;
    *slv_reg0 = rd_wr_mask | enable_mask;
    usleep(640);
    *slv_reg0 = 0;
    usleep(15);
}
unsigned ow_byte_read(void){
    int rd_data;
    *slv_reg0 =  enable_mask;
    usleep(640);
    *slv_reg0 = 0;
    usleep(15);
    rd_data = *slv_reg2;
    rd_data = rd_data & 255;//first 8 bit
    return rd_data;
}

void ow_bit_write(int data){

    *slv_reg1 = data & transmit_data_mask;
    *slv_reg0 = bit_byte_mode_mask | rd_wr_mask | enable_mask;
    usleep(80);
    *slv_reg0 = 0;
    usleep(15);
}
unsigned ow_bit_read(void){
    int rd_data;
    *slv_reg0 = bit_byte_mode_mask | enable_mask;
    usleep(80);
    *slv_reg0 = 0;
    usleep(15);
    rd_data = *slv_reg2;
    rd_data = rd_data & 1;//first bit
    return rd_data;
}
//ROM search algorithm implementation according to AN937 application note
//returns 1 if successfull
//int *rom_lut_handler is address of 64-bit ROM Code array
//bit write after reads disables the other device (o disables 1 vice versa)
//as there are 2 devices only 2 collusion will occur!!!
int rom_search_op(int *rom_lut_handler){
    int status = 0;
    int error = 0;
    int rom_buff = 0;
    int read_bit[2];
    int collusion;

    for (int dev_count = 0; dev_count < num_of_one_wire_dev;dev_count++){
            status = ow_initialize();
            ow_byte_write(0xF0);//SEARCH ROM Command
            error += status;
        for (int i = 0; i<64;i++){
            read_bit[0] = ow_bit_read();
            read_bit[1] = ow_bit_read();
            if ( (read_bit[0] == 0) && (read_bit[1] == 1) )//No collusion all devices have a 0 bit
            {
                rom_buff += 0;//bit field is 0 no change
                ow_bit_write(0);//proceed with 0 selection
            }
            else if ( (read_bit[0] == 1) && (read_bit[1] == 0) )//No collusion all devices have a 1 bit
            {
                rom_buff += (1 << (i%8) );//bit field is 1, current index is made 1
                ow_bit_write(1);//proceed with 1 selection
            }
            else if ( (read_bit[0] == 0) && (read_bit[1] == 0) )//collusion devices a device has 0 another has 1
            {
                if (collusion == i)//previous collusion reached select 1 this time
                {
                    rom_buff += (1 << (i%8) );
                    ow_bit_write(1);//proceed with 1 selection
                }
                else//new collusion found mark it assume 0 one as it's first time
                {
                    collusion = i;
                    ow_bit_write(0);//proceed with 0 selection
                }
            }
            else//undefined state
            {
            	print("Undefined State!!!\n\r");
                return 0;
            }

            if (i % 8 == 7)
            {
                *rom_lut_handler = rom_buff;
                rom_lut_handler ++;
                rom_buff = 0;
            }
        }
    }
    return 1;
}
//learn single device ROM
int read_rom_op(int *read_rom_handler){

    int status = ow_initialize();

    ow_byte_write(0x33);//READ ROM Command allowed in single dev use

    //Reading 64 bit ROM Code
    for(int i = 0; i<8;i++){
		*read_rom_handler = ow_byte_read();
		read_rom_handler++;
	}

    return status;
}
//Temprature read operation form single max31826 dev
//returns 1 if successfull
//int *read_temp_handler is address of read data array
int single_max31826_dev_op(int *read_temp_handler){
	print("Hello, This is Single MAX31826 One Wire Device operation Test of MAX31826!!!\n\r");
	int status = 0;
	int error = 0;

	status = ow_initialize();
	error += status;
	ow_byte_write(0xCC);//SKIP ROM Command allowed in single dev use
	ow_byte_write(0x44);//CONVERT T Command starts temp conv
    usleep(150000);//Waiting Tconv(150ms)
	status = ow_initialize();
	error += status;
	ow_byte_write(0xCC);//SKIP ROM Command
	ow_byte_write(0xBE);//READ SCRATCH PAD 1 Command
	for(int i = 0; i<9;i++){
		*read_temp_handler = ow_byte_read();
		read_temp_handler++;
	}
	if (error > 0)
		return 0;
	else
		return 1;
}
//Temprature read operation form two max31826 devices
void max31826_dev_op(double *temp_array){
    print("Hello, This is MAX31826 One Wire Device Full Operation Test of MAX31826!!!\n\r");

    int status = 0;
    int rom_code_lut[2][8];
    int read_buff[9];
    double temp;

    status = rom_search_op(rom_code_lut);
    xil_printf("Found ROM_CODES;");
    xil_printf("\n DEV_0 :");
    for (int i = 0; i < 8; i++){
        xil_printf("%X ", rom_code_lut[0][i]);
    }
    xil_printf("\n DEV_1 :");
    for (int i = 0; i < 8; i++){
        xil_printf("%X ", rom_code_lut[1][i]);
    }

    //Sending both devices convert command to save time
	status = ow_initialize();
	ow_byte_write(0xCC);//SKIP ROM Command allowed in single dev use
	ow_byte_write(0x44);//CONVERT T Command starts temp conv
    usleep(150000);//Waiting Tconv(150ms)

    for(int dev_num = 0; dev_num<2;dev_num++){
        status = ow_initialize();
        ow_byte_write(0x55);
        for(int i = 0; i<8;i++){
            ow_byte_write(rom_code_lut[dev_num][i]);
        }
	    ow_byte_write(0xBE);//READ SCRATCH PAD 1 Command
	    for(int i = 0; i<9;i++){
	    	read_buff[i] = ow_byte_read();
	    }
        temp = ( (read_buff[1] & 0x07) << 4) + ( (read_buff[0] & 0xF0) >> 4) + 0.125*(read_buff[0] & 0x0F);//finding absolute value of temp
        temp *= 1-2*( (read_buff[1] & 0x80) >> 8);//adding sign
        *temp_array = temp;
        temp_array++;
        xil_printf("\n DEV_%d; location : %X",dev_num, (read_buff[4] & 0x0F) );
    }

}
