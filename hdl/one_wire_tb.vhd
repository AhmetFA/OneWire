library ieee;
use IEEE.STD_LOGIC_1164.all;
use IEEE.numeric_std.all;
use ieee.math_real.all;

entity one_wire_tb is
    generic(
    osc_freq_g            : integer := 100_000_000;
    one_wire_freq_g       : integer := 1_000_000;--1us min resolution
    reset_presence_length : integer := 512;
    data_width_g          : integer := 8
    );
end entity one_wire_tb;

architecture behavioral of one_wire_tb is

    component one_wire is
        generic (
            osc_freq_g            : integer := 100_000_000;
            one_wire_freq_g       : integer := 1_000_000;--1us min resolution
            reset_presence_length : integer := 512;
            data_width_g          : integer := 8
        );
        port (
            clock_i  : in std_logic;
            resetn_i : in std_logic;
            --slv_reg0
            --Bit 0: one_wire_enable, with rising of this bit communication starts
            --Bit 1: rd_wr, 0 is read, 1 is write
            --Bit 2: reset flag if 1 ip will apply reset
            slv_reg0_i : in std_logic_vector(7 downto 0);
            --slv_reg1 for transmit data
            slv_reg1_i : in std_logic_vector(data_width_g - 1 downto 0);
            --rx
            rx_data_ready_o : out std_logic;
            slv_reg2_o      : out std_logic_vector(data_width_g - 1 downto 0);
            --used for scheduling
            busy_o  : out std_logic;-- slv_reg0(8)
            error_o : out std_logic; -- indicating no presence
            -- one wire out
            DQ_io : inout std_logic
        );
    end component;
	

    signal clock_i  :  std_logic;
    signal resetn_i :  std_logic;
    signal slv_reg0_i :  std_logic_vector(7 downto 0);
    signal slv_reg1_i :  std_logic_vector(data_width_g - 1 downto 0);
    signal rx_data_ready_o :  std_logic;
    signal slv_reg2_o      :  std_logic_vector(data_width_g - 1 downto 0);
    signal busy_o  :  std_logic;
    signal error_o :  std_logic;
    signal DQ_io :  std_logic;
    
begin

    one_wire_inst : component one_wire
        generic map (
            osc_freq_g            =>osc_freq_g,
            one_wire_freq_g       =>one_wire_freq_g,
            reset_presence_length =>reset_presence_length,
            data_width_g          =>data_width_g
        )
        port map(
            clock_i  => clock_i,
            resetn_i => resetn_i,
            slv_reg0_i => slv_reg0_i,
            slv_reg1_i => slv_reg1_i,
            rx_data_ready_o => rx_data_ready_o,
            slv_reg2_o      => slv_reg2_o,
            busy_o  => busy_o,
            error_o => error_o,
            DQ_io => DQ_io
        );

	clock_p : process
    begin
        clock_i <= '0';
        wait for 5ns;
        clock_i <= '1';
        wait for 5ns;
    end process;
	
	
	reset_p : process
    begin
        resetn_i <= '0';
		slv_reg0_i <= "00000000";
        wait for 20ns;
        resetn_i <= '1';
        wait for 100ns;
        
        slv_reg0_i <= "00000101";
		wait for 10ns;
        slv_reg0_i <= "00000000";
        
        wait for 1000us;
        wait;
        
    end process;
	

end architecture behavioral;