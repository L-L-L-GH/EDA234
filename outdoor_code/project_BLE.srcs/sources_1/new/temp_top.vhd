----------------------------------------------------------------------------
-- Author:  Ruxuan Wen
----------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Top-level module: Integrates temperature acquisition, ASCII conversion, and sends data to the phone via Bluetooth
entity UART_Loopback_Top is
    Generic (
        -- [Important] Please modify this according to the actual clock frequency of your development board
        SYSTEM_CLK_FREQ : integer := 100000000; -- For example: 50MHz (50000000) or 100MHz (100000000)
        BAUD_RATE       : integer := 9600       -- Keep the baud rate at 9600
    );
    Port (
        i_clk      : in    STD_LOGIC; -- System clock
        i_rst_n    : in    STD_LOGIC; -- Reset button (active low)
        
        -- DS18S20 temperature sensor interface
        TMP_DQ     : inout STD_LOGIC; -- Temperature sensor data line (bidirectional)

        -- BLE Bluetooth module interface
        i_bt_rx    : in    STD_LOGIC; -- Receive data from Bluetooth (connect to Bluetooth TX)
        o_bt_tx    : out   STD_LOGIC; -- Send data to Bluetooth (connect to Bluetooth RX)

        -- USB/PC interface (reserved for debugging, can observe data sent from the phone)
        i_pc_rx    : in    STD_LOGIC; -- Receive data from the computer
        o_pc_tx    : out   STD_LOGIC  -- Send data to the computer
    );
end UART_Loopback_Top;

architecture Behavioral of UART_Loopback_Top is

    -- Automatically calculate the division count value
    constant c_CLK_PER_BIT : integer := SYSTEM_CLK_FREQ / BAUD_RATE;

    -- =========================================================================
    -- Signal Definitions
    -- =========================================================================

    -- Bluetooth reception related (for debugging, forwards data sent from the phone to the computer)
    signal w_bt_rx_done : std_logic;
    signal w_bt_data    : std_logic_vector(7 downto 0);
    signal w_pc_tx_busy : std_logic;

    -- Temperature sensor related signals
    signal w_dq_in    : std_logic;
    signal w_dq_out   : std_logic;
    signal w_dq_oe    : std_logic;
    signal w_temp_raw : std_logic_vector(15 downto 0);
    signal w_temp_done: std_logic;

    -- ASCII conversion and transmission control related signals
    signal w_ascii_data  : std_logic_vector(7 downto 0);
    signal w_ascii_start : std_logic;
    signal w_bt_tx_done  : std_logic; -- Bluetooth transmission complete signal (feedback to ASCII module)
    signal w_bt_tx_busy  : std_logic;

    -- =========================================================================
    -- Component Declarations
    -- =========================================================================
    
    -- 1. UART reception module
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

    -- 2. UART transmission module
    component UART_TX is
        generic ( CLK_per_bit : integer );
        port (
            i_clk      : in std_logic;
            i_reset    : in std_logic;
            i_tx_start : in std_logic;
            i_tx_data  : in std_logic_vector(7 downto 0);
            o_tx_busy  : out std_logic;
            o_tx_done  : out std_logic; -- Note: We need this signal to feedback to the ASCII converter
            o_tx_bit   : out std_logic
        );
    end component;

    -- 3. DS18S20 driver module
    component ds18s20_onewire is
        port(
            clk      : in  std_logic;
            rst_n    : in  std_logic;
            dq_in    : in  std_logic;
            dq_out   : out std_logic;
            dq_oe    : out std_logic;
            temp_raw : out std_logic_vector(15 downto 0);
            done     : out std_logic
        );
    end component;

    -- 4. Temperature to ASCII and transmission control module
    component Temp_to_ASCII is
        port (
            clk           : in  std_logic;
            rst_n         : in  std_logic;
            i_temp_data   : in  std_logic_vector(15 downto 0);
            i_temp_done   : in  std_logic;
            i_uart_done   : in  std_logic;
            o_uart_data   : out std_logic_vector(7 downto 0);
            o_uart_start  : out std_logic
        );
    end component;

begin

    -- =========================================================================
    -- Logic Implementation
    -- =========================================================================

    -------------------------------------------------------------------------
    -- 1. Handle DS18S20 bidirectional IO (Tri-state Buffer)
    -------------------------------------------------------------------------
    -- When dq_oe (Output Enable) is '1', output low level (simulate Open Drain)
    -- When dq_oe is '0', set to high-impedance state 'Z', pulled high by external pull-up resistor
    TMP_DQ <= '0' when w_dq_oe = '1' else 'Z';
    
    -- Read pin status
    w_dq_in <= TMP_DQ;

    -------------------------------------------------------------------------
    -- 2. Instantiate DS18S20 driver
    -------------------------------------------------------------------------
    inst_ds18s20 : ds18s20_onewire
    port map (
        clk      => i_clk,
        rst_n    => i_rst_n,
        dq_in    => w_dq_in,
        dq_out   => w_dq_out,
        dq_oe    => w_dq_oe,
        temp_raw => w_temp_raw,  -- Get raw 16-bit temperature data
        done     => w_temp_done  -- Temperature conversion complete pulse
    );

    -------------------------------------------------------------------------
    -- 3. Instantiate ASCII converter (core control logic)
    -------------------------------------------------------------------------
    -- This module receives temperature data, converts it to character sequence, and controls UART transmission
    inst_temp_to_ascii : Temp_to_ASCII
    port map (
        clk           => i_clk,
        rst_n         => i_rst_n,
        i_temp_data   => w_temp_raw,    -- Input: Raw temperature from sensor
        i_temp_done   => w_temp_done,   -- Input: Sensor read complete signal
        i_uart_done   => w_bt_tx_done,  -- Input: Bluetooth UART transmission complete signal (for handshake)
        o_uart_data   => w_ascii_data,  -- Output: ASCII character to be sent
        o_uart_start  => w_ascii_start  -- Output: Trigger signal for transmission
    );

    -------------------------------------------------------------------------
    -- 4. Instantiate FPGA -> Bluetooth transmission module (TX)
    -------------------------------------------------------------------------
    -- Transmit the converted ASCII characters to the phone via Bluetooth
    inst_uart_tx_BLE : UART_TX
    generic map (
        CLK_per_bit => c_CLK_PER_BIT
    )
    port map (
        i_clk      => i_clk,
        i_reset    => i_rst_n,
        i_tx_start => w_ascii_start, -- Start signal comes from ASCII module
        i_tx_data  => w_ascii_data,  -- Data comes from ASCII module
        o_tx_busy  => w_bt_tx_busy,
        o_tx_done  => w_bt_tx_done,  -- Transmission complete signal, feedback to ASCII module to process next character
        o_tx_bit   => o_bt_tx        -- Physical pin: Connect to Bluetooth module RX
    );

    -------------------------------------------------------------------------
    -- 5. Auxiliary function: Bluetooth reception -> Computer display (Loopback / Debug)
    -------------------------------------------------------------------------
    -- This part is not essential, but keeping it helps with debugging.
    -- If you send commands from your phone, you can see them on the computer serial port assistant via USB.

    -- Receive data sent from Bluetooth
    inst_uart_rx_BLE : UART_RX
    generic map (
        CLK_per_bit => c_CLK_PER_BIT
    )
    port map (
        i_clk     => i_clk,
        i_reset   => i_rst_n,
        i_rx_bit  => i_bt_rx,      -- Physical pin: From Bluetooth TX
        o_rx_done => w_bt_rx_done,
        o_rx_data => w_bt_data,
        o_rx_busy => open
    );

    -- Forward the data received from Bluetooth to the computer
    inst_uart_tx_PC : UART_TX
    generic map (
        CLK_per_bit => c_CLK_PER_BIT
    )
    port map (
        i_clk      => i_clk,
        i_reset    => i_rst_n,
        i_tx_start => w_bt_rx_done, -- As soon as Bluetooth data is received, send it to the computer
        i_tx_data  => w_bt_data,
        o_tx_busy  => w_pc_tx_busy,
        o_tx_done  => open,
        o_tx_bit   => o_pc_tx       -- Physical pin: Connect to USB/PC RX
    );

end Behavioral;