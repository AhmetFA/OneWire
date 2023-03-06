library ieee;
use IEEE.STD_LOGIC_1164.all;
use IEEE.numeric_std.all;
use ieee.math_real.all;

entity one_wire is
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
        --Bit 3: Byte/Bit Mode
        slv_reg0_i : in std_logic_vector(7 downto 0);
        --slv_reg1 for transmit data
        slv_reg1_i : in std_logic_vector(data_width_g - 1 downto 0);
        --rx
        rx_data_ready_o : out std_logic;
        slv_reg2_o     : out std_logic_vector(data_width_g - 1 downto 0);
        --used for scheduling
        busy_o  : out std_logic;-- slv_reg3(1)
        error_o : out std_logic; -- slvreg3(2) indicating no presence
        -- one wire out
        DQ_io : inout std_logic
    );
end entity one_wire;

architecture logic of one_wire is
    signal us_tick_en_s      : std_logic;
    signal us_tick_s         : std_logic;
    signal us_tick_counter_s : integer range 0 to 2047 := 0;
    constant tick_count_c    : integer                 := integer(ceil(real(osc_freq_g) / real(one_wire_freq_g)));

    signal slot_counter_s         : integer range 0 to 1023         := 0;
    constant one_low_time_c       : integer                         := 10;
    constant zero_low_time_c      : integer                         := 70;
    constant slot_time_c          : integer                         := 80;
    constant tinit_time_c         : integer                         := 5;
    constant sample_window_time_c : integer                         := 15;
    constant tpdhigh_c            : integer                         := 15; -- before presence low wait time
    constant presence_min_time_c  : integer                         := 60;
    constant presence_max_time_c  : integer                         := 240;
    signal data_counter_s         : integer range 0 to data_width_g := 0;

    type operation_states_t is (idle, reset_presence, wr_data, rd_data);
    signal operation_states : operation_states_t := idle;
    --slave register 0
    signal one_wire_enable_s : std_logic;
    signal rd_wr_s           : std_logic;
    signal comm_mode_s : integer range 1 to 8;
    -- DQ
    signal DQ_out_s     : std_logic;
    signal DQ_out_en_s  : std_logic;
    signal DQ_in_buff_s : std_logic;
    --rx-tx data
    signal rx_data_s : std_logic_vector(data_width_g - 1 downto 0);
    signal tx_data_s : std_logic_vector(data_width_g - 1 downto 0);
    --reset - presence
    signal presence_counter_s : integer range 0 to reset_presence_length - 1 := 0;
    signal presence_fall_s    : std_logic                                    := '0';
    signal presence_rise_s    : std_logic                                    := '0';
    
    --attribute MARK_DEBUG                  : string;
    --attribute MARK_DEBUG of operation_states       : signal is "TRUE";
    --attribute MARK_DEBUG of one_wire_enable_s       : signal is "TRUE";
    --attribute MARK_DEBUG of rd_wr_s       : signal is "TRUE";
    --attribute MARK_DEBUG of comm_mode_s       : signal is "TRUE";
    --attribute MARK_DEBUG of DQ_out_s       : signal is "TRUE";
    --attribute MARK_DEBUG of DQ_out_en_s       : signal is "TRUE";
    --attribute MARK_DEBUG of DQ_in_buff_s       : signal is "TRUE";
    --attribute MARK_DEBUG of rx_data_s       : signal is "TRUE";
    --attribute MARK_DEBUG of tx_data_s       : signal is "TRUE";
    --attribute MARK_DEBUG of presence_counter_s       : signal is "TRUE";
    --attribute MARK_DEBUG of presence_fall_s       : signal is "TRUE";
    --attribute MARK_DEBUG of presence_rise_s : signal is "TRUE";
    --attribute MARK_DEBUG of slot_counter_s : signal is "TRUE";
    --attribute MARK_DEBUG of data_counter_s : signal is "TRUE";
    --attribute MARK_DEBUG of us_tick_s : signal is "TRUE";
    --attribute MARK_DEBUG of us_tick_en_s : signal is "TRUE";
    --attribute MARK_DEBUG of us_tick_counter_s : signal is "TRUE";

begin
    
    main_p : process (clock_i) is
    begin
        if rising_edge(clock_i) then
            if (resetn_i = '0') then
                comm_mode_s <= 8;
                us_tick_en_s       <= '0';
                us_tick_counter_s  <= 0;
                us_tick_s          <= '0';
                one_wire_enable_s  <= '0';
                rd_wr_s            <= '0';
                DQ_in_buff_s       <= '0';
                rx_data_ready_o    <= '0';
                slot_counter_s <= 0;
                presence_counter_s <= 0;
                slv_reg2_o         <= (others => '0');
                rx_data_s <= (others => '0');
                tx_data_s <= (others => '0');
                presence_fall_s <= '0';
                presence_rise_s <= '0';
                presence_counter_s <= 0;
                data_counter_s <= 0;
                busy_o  <= '0';
                error_o <= '0';
                DQ_out_en_s        <= '0';
                operation_states <= idle;
            else
                if (us_tick_en_s = '1') then
                    if (us_tick_counter_s < tick_count_c - 1) then
                        -- we count till the baud number and when us_tick_counter_s reaches last value
                        -- flag_s goes '1' and otherwise it's '0'
                        us_tick_counter_s <= us_tick_counter_s + 1;
                        us_tick_s         <= '0';
                    else
                        us_tick_counter_s <= 0;
                        us_tick_s         <= '1';
                    end if;
                else
                    us_tick_s         <= '0';
                    us_tick_counter_s <= 0;
                end if;
    
                case operation_states is
                    when idle =>
                        data_counter_s <= 0;
                        slot_counter_s <= 0;
                        rx_data_ready_o    <= '0';
                        DQ_out_s           <= 'Z';
                        DQ_out_en_s        <= '0';
                        one_wire_enable_s  <= slv_reg0_i(0);
                        presence_fall_s <= '0';
                        presence_rise_s <= '0';
                        presence_counter_s <= 0;
                        if (slv_reg0_i(0) = '1' and one_wire_enable_s = '0') then
                            us_tick_en_s <= '1';
                            busy_o  <= '1';
                            if (slv_reg0_i(2) = '0') then
                                if (slv_reg0_i(3) = '0') then
                                    comm_mode_s <= 8;--Byte Mode
                                else
                                    comm_mode_s <= 1;--Bit Mode
                                end if;
    
                                rd_wr_s <= slv_reg0_i(1);
                                if (slv_reg0_i(1) = '0') then
                                    operation_states <= rd_data;
                                    rx_data_s        <= (others => '0');
                                else
                                    tx_data_s        <= slv_reg1_i;
                                    operation_states <= wr_data;
                                end if;
                            else
                                operation_states <= reset_presence;
                            end if;
                        else
                            busy_o  <= '0';
                            rd_wr_s <= '0';
                            us_tick_en_s     <= '0';
                            operation_states <= idle;
                        end if;
                    when reset_presence =>
                        if (us_tick_s = '1') then
                            if (slot_counter_s < reset_presence_length - 1) then
							    slot_counter_s <= slot_counter_s + 1;
                                DQ_out_en_s <= '1';
                                DQ_out_s    <= '0';
                            elsif (slot_counter_s < tpdhigh_c + reset_presence_length - 1) then
							    slot_counter_s <= slot_counter_s + 1;
                                DQ_out_en_s <= '0';
                                DQ_out_s    <= 'Z';
                            elsif (slot_counter_s < 2 * reset_presence_length - 1) then
							    slot_counter_s <= slot_counter_s + 1;
                                DQ_in_buff_s <= DQ_io;
                                if (DQ_io = '1') and (DQ_in_buff_s = '0') then --rising edge
                                    presence_rise_s <= '1';
                                    assert false report ("One_Wire_Info: Presence Rose.") severity note;
                                end if;
    
                                if (DQ_io = '0') and (DQ_in_buff_s = '1') then --falling edge
                                    presence_fall_s <= '1';
                                    assert false report ("One_Wire_Info: Presence Fall.") severity note;
                                end if;
    
                                if (presence_fall_s = '1') and (presence_rise_s = '0') then
                                    presence_counter_s <= presence_counter_s + 1;
                                end if;
                            else
                                if (presence_counter_s > presence_min_time_c) and (presence_counter_s < presence_max_time_c) then
                                    error_o <= '0';
                                    assert false report ("One_Wire_Info: Presence Detected.") severity note;
                                else
                                    error_o <= '1';
                                    assert false report ("One_Wire_Warning: No Presence Detected.") severity note;
                                end if;
                                presence_counter_s <= 0;
                                slot_counter_s     <= 0;
                                operation_states   <= idle;
                                rx_data_ready_o <= '1';
                            end if;
                        end if;
                    when wr_data =>
                        if (data_counter_s < comm_mode_s) then
                            if (us_tick_s = '1') then
                                DQ_out_en_s <= '1';
                                if (slot_counter_s < slot_time_c) then
                                    slot_counter_s <= slot_counter_s + 1;
                                    if (tx_data_s(data_counter_s) = '0') and (slot_counter_s < zero_low_time_c) then
                                        DQ_out_s <= '0';
                                    elsif (tx_data_s(data_counter_s) = '1') and (slot_counter_s < one_low_time_c) then
                                        DQ_out_s <= '0';
                                    else
                                        DQ_out_s <= '1';
                                    end if;
                                else
                                    data_counter_s <= data_counter_s + 1;
                                    slot_counter_s <= 0;
                                end if;
                            end if;
                        else
                            DQ_out_en_s      <= '0';
                            data_counter_s   <= 0;
                            slot_counter_s   <= 0;
                            operation_states <= idle;
                        end if;
                    when rd_data =>
                        if (data_counter_s < comm_mode_s) then
                            if (us_tick_s = '1') then
                                if (slot_counter_s < slot_time_c) then
                                    slot_counter_s <= slot_counter_s + 1;
                                    if (slot_counter_s < tinit_time_c) then
                                        DQ_out_en_s <= '1';
                                        DQ_out_s    <= '0';
                                    else
                                        DQ_out_en_s  <= '0';
                                        DQ_out_s     <= '1';
                                        DQ_in_buff_s <= DQ_io;
                                        if (slot_counter_s < sample_window_time_c) then
                                            if (DQ_io = '1') and (DQ_in_buff_s = '0') then
                                                rx_data_s(data_counter_s) <= '1';
                                            end if;
                                        end if;
                                    end if;
                                else
                                    data_counter_s <= data_counter_s + 1;
                                    slot_counter_s <= 0;
                                end if;
                            end if;
                        else
                            rx_data_ready_o <= '1';
                            slv_reg2_o <= rx_data_s;
                            DQ_out_en_s      <= '0';
                            data_counter_s   <= 0;
                            slot_counter_s   <= 0;
                            operation_states <= idle;
                        end if;
                    when others =>
                        operation_states <= idle;
                end case;
            end if;
        end if;
    end process main_p;
    
    DQ_io <= DQ_out_s when (DQ_out_en_s = '1') else 'Z';
end logic;