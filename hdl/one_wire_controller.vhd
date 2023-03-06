library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity one_wire_controller is
    generic (
        -- Users to add parameters here
        osc_freq_g            : integer := 100_000_000;
        one_wire_freq_g       : integer := 1_000_000;--1us min resolution
        reset_presence_length : integer := 512;
        data_width_g          : integer := 8;
        -- User parameters ends
        -- Do not modify the parameters beyond this line

        -- Parameters of Axi Slave Bus Interface S00_AXI
        c_s00_axi_data_width : integer := 32;
        c_s00_axi_addr_width : integer := 4
    );
    port (
        -- Users to add ports here
        DQ_io                : inout    std_logic;
        -- User ports ends
        -- Do not modify the ports beyond this line
        -- Ports of Axi Slave Bus Interface S00_AXI
        s00_axi_aclk         : in    std_logic;
        s00_axi_aresetn      : in    std_logic;
        s00_axi_awaddr       : in    std_logic_vector(c_s00_axi_addr_width - 1 downto 0);
        s00_axi_awprot       : in    std_logic_vector(2 downto 0);
        s00_axi_awvalid      : in    std_logic;
        s00_axi_awready      : out   std_logic;
        s00_axi_wdata        : in    std_logic_vector(c_s00_axi_data_width - 1 downto 0);
        s00_axi_wstrb        : in    std_logic_vector((c_s00_axi_data_width / 8) - 1 downto 0);
        s00_axi_wvalid       : in    std_logic;
        s00_axi_wready       : out   std_logic;
        s00_axi_bresp        : out   std_logic_vector(1 downto 0);
        s00_axi_bvalid       : out   std_logic;
        s00_axi_bready       : in    std_logic;
        s00_axi_araddr       : in    std_logic_vector(c_s00_axi_addr_width - 1 downto 0);
        s00_axi_arprot       : in    std_logic_vector(2 downto 0);
        s00_axi_arvalid      : in    std_logic;
        s00_axi_arready      : out   std_logic;
        s00_axi_rdata        : out   std_logic_vector(c_s00_axi_data_width - 1 downto 0);
        s00_axi_rresp        : out   std_logic_vector(1 downto 0);
        s00_axi_rvalid       : out   std_logic;
        s00_axi_rready       : in    std_logic
    );
end entity one_wire_controller;

architecture arch_imp of one_wire_controller is

    -- component declaration
    component axi_bus_decoder is
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
    end component axi_bus_decoder;

begin

    -- Instantiation of Axi Bus Interface S00_AXI
    axi_bus_decoder_inst : component axi_bus_decoder
        generic map (
            osc_freq_g            =>osc_freq_g,
            one_wire_freq_g       =>one_wire_freq_g,
            reset_presence_length =>reset_presence_length,
            data_width_g          =>data_width_g,
            c_s_axi_data_width => c_s00_axi_data_width,
            c_s_axi_addr_width => c_s00_axi_addr_width
        )
        port map (
            DQ_io              => DQ_io,
            s_axi_aclk         => s00_axi_aclk,
            s_axi_aresetn      => s00_axi_aresetn,
            s_axi_awaddr       => s00_axi_awaddr,
            s_axi_awprot       => s00_axi_awprot,
            s_axi_awvalid      => s00_axi_awvalid,
            s_axi_awready      => s00_axi_awready,
            s_axi_wdata        => s00_axi_wdata,
            s_axi_wstrb        => s00_axi_wstrb,
            s_axi_wvalid       => s00_axi_wvalid,
            s_axi_wready       => s00_axi_wready,
            s_axi_bresp        => s00_axi_bresp,
            s_axi_bvalid       => s00_axi_bvalid,
            s_axi_bready       => s00_axi_bready,
            s_axi_araddr       => s00_axi_araddr,
            s_axi_arprot       => s00_axi_arprot,
            s_axi_arvalid      => s00_axi_arvalid,
            s_axi_arready      => s00_axi_arready,
            s_axi_rdata        => s00_axi_rdata,
            s_axi_rresp        => s00_axi_rresp,
            s_axi_rvalid       => s00_axi_rvalid,
            s_axi_rready       => s00_axi_rready
        );

    -- Add user logic here

    -- User logic ends

end architecture arch_imp;
