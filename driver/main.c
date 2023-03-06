#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "one_wire.h"
#include "sleep.h"

#define APP_MODE 0 //0 is 2 device scenario, 1 is multidevice scenario

int main()
{


    init_platform();
    one_wire_config(XPAR_ONE_WIRE_CONTROLLER_0_BASEADDR);
    #if APP_MODE
    	int result = 0;
        int status = 0;
	    int scratch_pad1_array[9];
        int read_rom_array[8];
        int rom_code_array[2][8];
        //Single Device Scenario
        result = single_max31826_dev_op(scratch_pad1_array);
        usleep(10000);
        status = read_rom_op(read_rom_array);
        usleep(10000);
        status = rom_search_op(rom_code_array);
    #else
        double temp_array[2];
        //Two Device Full Scenario
        max31826_dev_op(temp_array);
    #endif

    cleanup_platform();
    return 0;
}
