library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axi_bus_decoder is
    generic (
        -- Users to add parameters here
        osc_freq_g            : integer := 100_000_000;
        one_wire_freq_g       : integer := 1_000_000;--1us min resolution
        reset_presence_length : integer := 512;
        data_width_g          : integer := 8;
        -- User parameters ends
        -- Do not modify the parameters beyond this line

        -- Width of S_AXI data bus
        c_s_axi_data_width : integer := 32;
        -- Width of S_AXI address bus
        c_s_axi_addr_width : integer := 4
    );
    port (
        -- Users to add ports here
        DQ_io              : inout    std_logic;
        -- User ports ends
        -- Do not modify the ports beyond this line

        -- Global Clock Signal
        s_axi_aclk         : in    std_logic;
        -- Global Reset Signal. This Signal is Active LOW
        s_axi_aresetn      : in    std_logic;
        -- Write address (issued by master, acceped by Slave)
        s_axi_awaddr       : in    std_logic_vector(c_s_axi_addr_width - 1 downto 0);
        -- Write channel Protection type. This signal indicates the
        -- privilege and security level of the transaction, and whether
        -- the transaction is a data access or an instruction access.
        s_axi_awprot       : in    std_logic_vector(2 downto 0);
        -- Write address valid. This signal indicates that the master signaling
        -- valid write address and control information.
        s_axi_awvalid      : in    std_logic;
        -- Write address ready. This signal indicates that the slave is ready
        -- to accept an address and associated control signals.
        s_axi_awready      : out   std_logic;
        -- Write data (issued by master, acceped by Slave)
        s_axi_wdata        : in    std_logic_vector(c_s_axi_data_width - 1 downto 0);
        -- Write strobes. This signal indicates which byte lanes hold
        -- valid data. There is one write strobe bit for each eight
        -- bits of the write data bus.
        s_axi_wstrb        : in    std_logic_vector((c_s_axi_data_width / 8) - 1 downto 0);
        -- Write valid. This signal indicates that valid write
        -- data and strobes are available.
        s_axi_wvalid       : in    std_logic;
        -- Write ready. This signal indicates that the slave
        -- can accept the write data.
        s_axi_wready       : out   std_logic;
        -- Write response. This signal indicates the status
        -- of the write transaction.
        s_axi_bresp        : out   std_logic_vector(1 downto 0);
        -- Write response valid. This signal indicates that the channel
        -- is signaling a valid write response.
        s_axi_bvalid       : out   std_logic;
        -- Response ready. This signal indicates that the master
        -- can accept a write response.
        s_axi_bready       : in    std_logic;
        -- Read address (issued by master, acceped by Slave)
        s_axi_araddr       : in    std_logic_vector(c_s_axi_addr_width - 1 downto 0);
        -- Protection type. This signal indicates the privilege
        -- and security level of the transaction, and whether the
        -- transaction is a data access or an instruction access.
        s_axi_arprot       : in    std_logic_vector(2 downto 0);
        -- Read address valid. This signal indicates that the channel
        -- is signaling valid read address and control information.
        s_axi_arvalid      : in    std_logic;
        -- Read address ready. This signal indicates that the slave is
        -- ready to accept an address and associated control signals.
        s_axi_arready      : out   std_logic;
        -- Read data (issued by slave)
        s_axi_rdata        : out   std_logic_vector(c_s_axi_data_width - 1 downto 0);
        -- Read response. This signal indicates the status of the
        -- read transfer.
        s_axi_rresp        : out   std_logic_vector(1 downto 0);
        -- Read valid. This signal indicates that the channel is
        -- signaling the required read data.
        s_axi_rvalid       : out   std_logic;
        -- Read ready. This signal indicates that the master can
        -- accept the read data and response information.
        s_axi_rready       : in    std_logic
    );
end entity axi_bus_decoder;

architecture arch_imp of axi_bus_decoder is

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

    -- AXI4LITE signals
    signal   axi_awaddr        : std_logic_vector(c_s_axi_addr_width - 1 downto 0);
    signal   axi_awready       : std_logic;
    signal   axi_wready        : std_logic;
    signal   axi_bresp         : std_logic_vector(1 downto 0);
    signal   axi_bvalid        : std_logic;
    signal   axi_araddr        : std_logic_vector(c_s_axi_addr_width - 1 downto 0);
    signal   axi_arready       : std_logic;
    signal   axi_rdata         : std_logic_vector(c_s_axi_data_width - 1 downto 0);
    signal   axi_rresp         : std_logic_vector(1 downto 0);
    signal   axi_rvalid        : std_logic;

    -- Example-specific design signals
    -- local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
    -- ADDR_LSB is used for addressing 32/64 bit registers/memories
    -- ADDR_LSB = 2 for 32 bits (n downto 2)
    -- ADDR_LSB = 3 for 64 bits (n downto 3)
    constant addr_lsb          : integer := (c_s_axi_data_width / 32) + 1;
    constant opt_mem_addr_bits : integer := 1;
    ------------------------------------------------
    ---- Signals for user logic register space example
    --------------------------------------------------
    ---- Number of Slave Registers 4
    signal   slv_reg0          : std_logic_vector(c_s_axi_data_width - 1 downto 0);
    signal   slv_reg1          : std_logic_vector(c_s_axi_data_width - 1 downto 0);
    signal   slv_reg2          : std_logic_vector(c_s_axi_data_width - 1 downto 0);
    signal   slv_reg3          : std_logic_vector(c_s_axi_data_width - 1 downto 0);
    signal   slv_reg_rden      : std_logic;
    signal   slv_reg_wren      : std_logic;
    signal   reg_data_out      : std_logic_vector(c_s_axi_data_width - 1 downto 0);
    signal   byte_index        : integer;
    signal   aw_en             : std_logic;
    ---- User Signals
    signal rx_data_ready_s :  std_logic;
    signal busy_s  :  std_logic;
    signal error_s :  std_logic;

begin

    -- I/O Connections assignments

    s_axi_awready <= axi_awready;
    s_axi_wready  <= axi_wready;
    s_axi_bresp   <= axi_bresp;
    s_axi_bvalid  <= axi_bvalid;
    s_axi_arready <= axi_arready;
    s_axi_rdata   <= axi_rdata;
    s_axi_rresp   <= axi_rresp;
    s_axi_rvalid  <= axi_rvalid;
    -- Implement axi_awready generation
    -- axi_awready is asserted for one S_AXI_ACLK clock cycle when both
    -- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_awready is
    -- de-asserted when reset is low.

    process (s_axi_aclk) is
    begin

        if rising_edge(s_axi_aclk) then
            if (s_axi_aresetn = '0') then
                axi_awready     <= '0';
                aw_en           <= '1';
            else
                if (axi_awready = '0' and s_axi_awvalid = '1' and s_axi_wvalid = '1' and aw_en = '1') then
                    -- slave is ready to accept write address when
                    -- there is a valid write address and write data
                    -- on the write address and data bus. This design
                    -- expects no outstanding transactions.
                    axi_awready <= '1';
                    aw_en       <= '0';
                elsif (s_axi_bready = '1' and axi_bvalid = '1') then
                    aw_en       <= '1';
                    axi_awready <= '0';
                else
                    axi_awready <= '0';
                end if;
            end if;
        end if;

    end process;

    -- Implement axi_awaddr latching
    -- This process is used to latch the address when both
    -- S_AXI_AWVALID and S_AXI_WVALID are valid.

    process (s_axi_aclk) is
    begin

        if rising_edge(s_axi_aclk) then
            if (s_axi_aresetn = '0') then
                axi_awaddr     <= (others => '0');
            else
                if (axi_awready = '0' and s_axi_awvalid = '1' and s_axi_wvalid = '1' and aw_en = '1') then
                    -- Write Address latching
                    axi_awaddr <= s_axi_awaddr;
                end if;
            end if;
        end if;

    end process;

    -- Implement axi_wready generation
    -- axi_wready is asserted for one S_AXI_ACLK clock cycle when both
    -- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_wready is
    -- de-asserted when reset is low.

    process (s_axi_aclk) is
    begin

        if rising_edge(s_axi_aclk) then
            if (s_axi_aresetn = '0') then
                axi_wready     <= '0';
            else
                if (axi_wready = '0' and s_axi_wvalid = '1' and s_axi_awvalid = '1' and aw_en = '1') then
                    -- slave is ready to accept write data when
                    -- there is a valid write address and write data
                    -- on the write address and data bus. This design
                    -- expects no outstanding transactions.
                    axi_wready <= '1';
                else
                    axi_wready <= '0';
                end if;
            end if;
        end if;

    end process;

    -- Implement memory mapped register select and write logic generation
    -- The write data is accepted and written to memory mapped registers when
    -- axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
    -- select byte enables of slave registers while writing.
    -- These registers are cleared when reset (active low) is applied.
    -- Slave register write enable is asserted when valid address and data are available
    -- and the slave is ready to accept the write address and write data.
    slv_reg_wren  <= axi_wready and s_axi_wvalid and axi_awready and s_axi_awvalid;

    process (s_axi_aclk) is

        variable loc_addr : std_logic_vector(opt_mem_addr_bits downto 0);

    begin

        if rising_edge(s_axi_aclk) then
            if (s_axi_aresetn = '0') then
                slv_reg0                                                           <= (others => '0');
                slv_reg1                                                           <= (others => '0');
                --slv_reg2                                                           <= (others => '0');
                --slv_reg3                                                           <= (others => '0');
            else
                loc_addr                                                           := axi_awaddr(addr_lsb + opt_mem_addr_bits downto addr_lsb);
                if (slv_reg_wren = '1') then

                    case loc_addr is

                        when b"00" =>

                            for byte_index in 0 to (c_s_axi_data_width / 8 - 1) loop

                                if (s_axi_wstrb(byte_index) = '1') then
                                    -- Respective byte enables are asserted as per write strobes
                                    -- slave registor 0
                                    slv_reg0(byte_index*8 + 7 downto byte_index*8) <= s_axi_wdata(byte_index * 8 + 7 downto byte_index * 8);
                                end if;

                            end loop;

                        when b"01" =>

                            for byte_index in 0 to (c_s_axi_data_width / 8 - 1) loop

                                if (s_axi_wstrb(byte_index) = '1') then
                                    -- Respective byte enables are asserted as per write strobes
                                    -- slave registor 1
                                    slv_reg1(byte_index*8 + 7 downto byte_index*8) <= s_axi_wdata(byte_index * 8 + 7 downto byte_index * 8);
                                end if;

                            end loop;
                        
                        --Read Only Registers
                        --when b"10" =>
                        --    for byte_index in 0 to (c_s_axi_data_width / 8 - 1) loop
                        --        if (s_axi_wstrb(byte_index) = '1') then
                        --            -- Respective byte enables are asserted as per write strobes
                        --            -- slave registor 2
                        --            slv_reg2(byte_index*8 + 7 downto byte_index*8) <= s_axi_wdata(byte_index * 8 + 7 downto byte_index * 8);
                        --        end if;
                        --    end loop;
                        --when b"11" =>
                        --    for byte_index in 0 to (c_s_axi_data_width / 8 - 1) loop
                        --        if (s_axi_wstrb(byte_index) = '1') then
                        --            -- Respective byte enables are asserted as per write strobes
                        --            -- slave registor 3
                        --            slv_reg3(byte_index*8 + 7 downto byte_index*8) <= s_axi_wdata(byte_index * 8 + 7 downto byte_index * 8);
                        --        end if;
                        --    end loop;

                        when others =>

                            slv_reg0                                               <= slv_reg0;
                            slv_reg1                                               <= slv_reg1;
                            -- Read only Register
                            -- slv_reg2                                               <= slv_reg2;
                            -- slv_reg3                                               <= slv_reg3;

                    end case;

                end if;
            end if;
        end if;

    end process;

    -- Implement write response logic generation
    -- The write response and response valid signals are asserted by the slave
    -- when axi_wready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted.
    -- This marks the acceptance of address and indicates the status of
    -- write transaction.

    process (s_axi_aclk) is
    begin

        if rising_edge(s_axi_aclk) then
            if (s_axi_aresetn = '0') then
                axi_bvalid     <= '0';
                axi_bresp      <= "00";                                                                                              -- need to work more on the responses
            else
                if (axi_awready = '1' and s_axi_awvalid = '1' and axi_wready = '1' and s_axi_wvalid = '1' and axi_bvalid = '0') then
                    axi_bvalid <= '1';
                    axi_bresp  <= "00";
                elsif (s_axi_bready = '1' and axi_bvalid = '1') then                                                                 -- check if bready is asserted while bvalid is high)
                    axi_bvalid <= '0';                                                                                               -- (there is a possibility that bready is always asserted high)
                end if;
            end if;
        end if;

    end process;

    -- Implement axi_arready generation
    -- axi_arready is asserted for one S_AXI_ACLK clock cycle when
    -- S_AXI_ARVALID is asserted. axi_awready is
    -- de-asserted when reset (active low) is asserted.
    -- The read address is also latched when S_AXI_ARVALID is
    -- asserted. axi_araddr is reset to zero on reset assertion.

    process (s_axi_aclk) is
    begin

        if rising_edge(s_axi_aclk) then
            if (s_axi_aresetn = '0') then
                axi_arready     <= '0';
                axi_araddr      <= (others => '1');
            else
                if (axi_arready = '0' and s_axi_arvalid = '1') then
                    -- indicates that the slave has acceped the valid read address
                    axi_arready <= '1';
                    -- Read Address latching
                    axi_araddr  <= s_axi_araddr;
                else
                    axi_arready <= '0';
                end if;
            end if;
        end if;

    end process;

    -- Implement axi_arvalid generation
    -- axi_rvalid is asserted for one S_AXI_ACLK clock cycle when both
    -- S_AXI_ARVALID and axi_arready are asserted. The slave registers
    -- data are available on the axi_rdata bus at this instance. The
    -- assertion of axi_rvalid marks the validity of read data on the
    -- bus and axi_rresp indicates the status of read transaction.axi_rvalid
    -- is deasserted on reset (active low). axi_rresp and axi_rdata are
    -- cleared to zero on reset (active low).
    process (s_axi_aclk) is
    begin

        if rising_edge(s_axi_aclk) then
            if (s_axi_aresetn = '0') then
                axi_rvalid     <= '0';
                axi_rresp      <= "00";
            else
                if (axi_arready = '1' and s_axi_arvalid = '1' and axi_rvalid = '0') then
                    -- Valid read data is available at the read data bus
                    axi_rvalid <= '1';
                    axi_rresp  <= "00"; -- 'OKAY' response
                elsif (axi_rvalid = '1' and s_axi_rready = '1') then
                    -- Read data is accepted by the master
                    axi_rvalid <= '0';
                end if;
            end if;
        end if;

    end process;

    -- Implement memory mapped register select and read logic generation
    -- Slave register read enable is asserted when valid address is available
    -- and the slave is ready to accept the read address.
    slv_reg_rden  <= axi_arready and s_axi_arvalid and (not axi_rvalid);

    process (slv_reg0, slv_reg1, slv_reg2, slv_reg3, axi_araddr, s_axi_aresetn, slv_reg_rden) is

        variable loc_addr : std_logic_vector(opt_mem_addr_bits downto 0);

    begin

        -- Address decoding for reading registers
        loc_addr             := axi_araddr(addr_lsb + opt_mem_addr_bits downto addr_lsb);

        case loc_addr is

            when b"00" =>

                reg_data_out <= slv_reg0;

            when b"01" =>

                reg_data_out <= slv_reg1;

            when b"10" =>

                reg_data_out <= slv_reg2;

            when b"11" =>

                reg_data_out <= slv_reg3;

            when others =>

                reg_data_out <= (others => '0');

        end case;

    end process;

    -- Output register or memory read data
    process (s_axi_aclk,slv_reg0, slv_reg1, slv_reg2, slv_reg3, axi_araddr, s_axi_aresetn, slv_reg_rden) is
        variable loc_addr : std_logic_vector(opt_mem_addr_bits downto 0);
    begin
        loc_addr := axi_araddr(addr_lsb + opt_mem_addr_bits downto addr_lsb);

        if (rising_edge (s_axi_aclk)) then
            if (s_axi_aresetn = '0') then
                axi_rdata     <= (others => '0');
            else
                if (slv_reg_rden = '1') then
                    -- When there is a valid read address (S_AXI_ARVALID) with
                    -- acceptance of read address by the slave (axi_arready),
                    -- output the read dada
                    -- Read address mux
                    axi_rdata <= reg_data_out;     -- register read data
                    if (loc_addr = b"11") and (slv_reg3(0) = '1') then
                        slv_reg3(0) <= '0';
                    end if;
                elsif (rx_data_ready_s = '1') then
                    slv_reg3(0) <= '1';
                end if;
            end if;
        end if;

    end process;

    -- Add user logic here
    one_wire_inst : one_wire
        generic map (
            osc_freq_g            =>osc_freq_g,
            one_wire_freq_g       =>one_wire_freq_g,
            reset_presence_length =>reset_presence_length,
            data_width_g          =>data_width_g
        )
        port map(
            clock_i  => s_axi_aclk,
            resetn_i => s_axi_aresetn,
            slv_reg0_i => slv_reg0(7 downto 0),
            slv_reg1_i => slv_reg1(data_width_g - 1 downto 0),
            rx_data_ready_o => rx_data_ready_s,
            slv_reg2_o      => slv_reg2(data_width_g - 1 downto 0),
            busy_o  => busy_s,
            error_o => error_s,
            DQ_io => DQ_io
        );

        slv_reg3(1) <= busy_s;
        slv_reg3(2) <= error_s;
        slv_reg3(3) <= '0';
        slv_reg3(4) <= '0';
        slv_reg3(5) <= '0';
        slv_reg3(6) <= '0';
        slv_reg3(7) <= '0';
        slv_reg2(31 downto 20) <= x"AFA";
        
    -- User logic ends

end architecture arch_imp;
