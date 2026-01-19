----------------------------------------------------------------------------
-- Author:  Wentao Chen
----------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Top-level module: Forwards data received via Bluetooth directly to the computer
entity UART_Loopback_Top is
    Generic (
        SYSTEM_CLK_FREQ : integer := 100000000; -- For example: 50MHz (50000000) or 100MHz (100000000)
        BAUD_RATE       : integer := 9600      -- Keep the baud rate at 9600
    );
    Port (
        i_clk      : in  STD_LOGIC; -- System clock
        i_rst_n    : in  STD_LOGIC; -- Reset button (active low)
        --BLE 
        i_bt_rx    : in  STD_LOGIC; -- Receive data from Bluetooth (connect to Bluetooth TX)
        o_bt_tx    : out STD_LOGIC;
        --USB
        i_pc_rx    : in  STD_LOGIC; -- Receive data from the computer (connect to USB_TX)
        o_pc_tx    : out STD_LOGIC 
    );
end UART_Loopback_Top;

architecture Behavioral of UART_Loopback_Top is

    -- Automatically calculate the division count value
    constant c_CLK_PER_BIT : integer := SYSTEM_CLK_FREQ / BAUD_RATE;

    -- Internal connection signals
    signal w_rx_done : std_logic;                    -- Reception complete flag
    signal w_data_byte : std_logic_vector(7 downto 0); -- Data bus
    --signal i_rx_PC : std_logic;
    signal w_rx_done_FPGA : std_logic;
    signal w_data_byte_FPGA : std_logic_vector(7 downto 0);

    signal w_tx_busy : std_logic;                    -- Transmission busy flag (can be used for debugging LEDs)

    -- Declare your receiving module
    component UART_RX is
        generic ( CLK_per_bit : integer );
        port (
            i_clk     : in std_logic;
            i_reset   : in std_logic;
            i_rx_bit  : in std_logic;
            o_rx_done : out std_logic;
            o_rx_data : out std_logic_vector(7 downto 0);
            o_rx_busy : out std_logic
        );
    end component;

    -- Send module Declaration
    component UART_TX is
        generic ( CLK_per_bit : integer );
        port (
            i_clk      : in std_logic;
            i_reset    : in std_logic;
            i_tx_start : in std_logic;
            i_tx_data  : in std_logic_vector(7 downto 0);
            o_tx_busy  : out std_logic;
            o_tx_done  : out std_logic;
            o_tx_bit   : out std_logic
        );
    end component;

begin

    -------------------------------------------------------------------------
    -- 1. Instantiate the receiving module (responsible for reading data from Bluetooth)
    -------------------------------------------------------------------------
    inst_uart_rx : UART_RX
    generic map (
        CLK_per_bit => c_CLK_PER_BIT -- Pass the calculated baud rate parameter
    )
    port map (
        i_clk     => i_clk,
        i_reset   => i_rst_n,
        i_rx_bit  => i_bt_rx,    -- Physical pin: from Bluetooth TX
        o_rx_done => w_rx_done,    -- Output pulse: informs the sending module "data has arrived"
        o_rx_data => w_data_byte,  -- Data: passed to the sending module
        o_rx_busy => open          -- Not used for now
    );

    -------------------------------------------------------------------------
    -- 2. Instantiate the sending module (responsible for sending data to the computer)
    -------------------------------------------------------------------------
    inst_uart_tx : UART_TX
    generic map (
        CLK_per_bit => c_CLK_PER_BIT -- Keep the baud rate consistent
    )
    port map (
        i_clk      => i_clk,
        i_reset    => i_rst_n,
        i_tx_start => w_rx_done,   -- Core logic: reception complete signal directly triggers transmission start signal
        i_tx_data  => w_data_byte, -- Core logic: data is directly forwarded
        o_tx_busy  => w_tx_busy,
        o_tx_done  => open,
        o_tx_bit   => o_pc_tx    -- Physical pin: to the computer RX
    );

    -- Data transmitted from PC to FPGA
    inst_uart_rx_FPGA: UART_RX
     generic map(
        CLK_per_bit => c_CLK_PER_BIT
    )
     port map(
        i_clk => i_clk,
        i_reset => i_rst_n,
        i_rx_bit => i_pc_rx,
        o_rx_done => w_rx_done_FPGA,
        o_rx_data => w_data_byte_FPGA,
        o_rx_busy => open
    );
    -- FPGA to BLE
    inst_uart_tx_FPGA: UART_TX
     generic map(
        CLK_per_bit => c_CLK_PER_BIT
    )
     port map(
        i_clk => i_clk,
        i_reset => i_rst_n,
        i_tx_start => w_rx_done_FPGA,
        i_tx_data => w_data_byte_FPGA,
        o_tx_busy => open,
        o_tx_done => open,
        o_tx_bit => o_bt_tx
    );
end Behavioral;