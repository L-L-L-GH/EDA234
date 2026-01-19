----------------------------------------------------------------------------
-- Author:  Wentao Chen
----------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
--Editor： Ruxuan Wen
-- Top-level module: Integrates temperature acquisition, ASCII conversion, and sends data to the phone via Bluetooth
-- Modified functionality: Optimized state machine to ensure temperature is sent only once after receiving "go"
entity UART_Loopback_Top is
    Generic (
        -- [Important] Please modify this according to the actual clock frequency of your development board
        SYSTEM_CLK_FREQ : integer := 100000000; -- For example: 50MHz (50000000) or 100MHz (100000000)
        BAUD_RATE       : integer := 9600       -- Keep baud rate at 9600
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

    -- Bluetooth reception related
    signal w_bt_rx_done : std_logic;
    signal w_bt_data    : std_logic_vector(7 downto 0);
    signal w_pc_tx_busy : std_logic;

    -- Temperature sensor related signals
    signal w_dq_in    : std_logic;
    signal w_dq_out   : std_logic;
    signal w_dq_oe    : std_logic;
    signal w_temp_raw : std_logic_vector(15 downto 0);
    signal w_temp_done: std_logic; -- Sensor's raw completion signal (periodic pulse)

    -- ASCII conversion and transmission control related signals
    signal w_ascii_data  : std_logic_vector(7 downto 0);
    signal w_ascii_start : std_logic;
    signal w_bt_tx_done  : std_logic; 
    signal w_bt_tx_busy  : std_logic;

    -- Command control signals
    signal w_trigger_conversion : std_logic;
    
    -- Optimized state machine: WAIT_G -> WAIT_O -> ARMED (ready to send)
    type cmd_state_t is (WAIT_G, WAIT_O, ARMED);
    signal current_cmd_state : cmd_state_t := WAIT_G;

    -- =========================================================================
    -- Component Declarations
    -- =========================================================================
    
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
    -- 1. Optimized command parsing and trigger logic
    -------------------------------------------------------------------------
    -- Core logic:
    -- w_trigger_conversion goes high only when the state machine is in ARMED (received "go") and the sensor is done (w_temp_done).
    w_trigger_conversion <= '1' when (current_cmd_state = ARMED and w_temp_done = '1') else '0';

    process(i_clk, i_rst_n)
    begin
        if i_rst_n = '0' then
            current_cmd_state <= WAIT_G;
        elsif rising_edge(i_clk) then
            
            -- Priority 1: If transmission is triggered, immediately return to the initial state to prevent continuous transmission
            if current_cmd_state = ARMED and w_temp_done = '1' then
                current_cmd_state <= WAIT_G;
            
            -- Priority 2: Process characters received via Bluetooth
            elsif w_bt_rx_done = '1' then
                case current_cmd_state is
                    when WAIT_G =>
                        if w_bt_data = x"67" then -- ASCII 'g'
                            current_cmd_state <= WAIT_O;
                        else
                            current_cmd_state <= WAIT_G;
                        end if;
                    when WAIT_O =>
                        if w_bt_data = x"6F" then -- ASCII 'o'
                            current_cmd_state <= ARMED; -- Received "go", enter ready state
                        elsif w_bt_data = x"67" then -- Fault tolerance: if "ggo", stay waiting for 'o'
                             current_cmd_state <= WAIT_O;
                        else
                            current_cmd_state <= WAIT_G; -- Character error, reset
                        end if;
                    when ARMED =>
                        -- If data is received while in ready state, stay ready or reset as needed
                        -- Here, stay ready, waiting for temperature data
                        null; 
                    when others =>
                        current_cmd_state <= WAIT_G;
                end case;
            end if;
        end if;
    end process;


    -------------------------------------------------------------------------
    -- 2. Handle DS18S20 bidirectional IO port
    -------------------------------------------------------------------------
    TMP_DQ <= '0' when w_dq_oe = '1' else 'Z';
    w_dq_in <= TMP_DQ;

    -------------------------------------------------------------------------
    -- 3. Instantiate DS18S20 driver (continuous operation)
    -------------------------------------------------------------------------
    inst_ds18s20 : ds18s20_onewire
    port map (
        clk      => i_clk,
        rst_n    => i_rst_n,
        dq_in    => w_dq_in,
        dq_out   => w_dq_out,
        dq_oe    => w_dq_oe,
        temp_raw => w_temp_raw,
        done     => w_temp_done  
    );

    -------------------------------------------------------------------------
    -- 4. Instantiate ASCII converter
    -------------------------------------------------------------------------
    inst_temp_to_ascii : Temp_to_ASCII
    port map (
        clk           => i_clk,
        rst_n         => i_rst_n,
        i_temp_data   => w_temp_raw,
        i_temp_done   => w_trigger_conversion, -- Connect controlled trigger signal
        i_uart_done   => w_bt_tx_done,
        o_uart_data   => w_ascii_data,
        o_uart_start  => w_ascii_start
    );

    -------------------------------------------------------------------------
    -- 5. FPGA -> Bluetooth transmission module (TX)
    -------------------------------------------------------------------------
    inst_uart_tx_BLE : UART_TX
    generic map (
        CLK_per_bit => c_CLK_PER_BIT
    )
    port map (
        i_clk      => i_clk,
        i_reset    => i_rst_n,
        i_tx_start => w_ascii_start,
        i_tx_data  => w_ascii_data,
        o_tx_busy  => w_bt_tx_busy,
        o_tx_done  => w_bt_tx_done,
        o_tx_bit   => o_bt_tx
    );

    -------------------------------------------------------------------------
    -- 6. Auxiliary function: Bluetooth reception -> PC display (for debugging)
    -------------------------------------------------------------------------
    inst_uart_rx_BLE : UART_RX
    generic map (
        CLK_per_bit => c_CLK_PER_BIT
    )
    port map (
        i_clk     => i_clk,
        i_reset   => i_rst_n,
        i_rx_bit  => i_bt_rx,
        o_rx_done => w_bt_rx_done,
        o_rx_data => w_bt_data, 
        o_rx_busy => open
    );

    inst_uart_tx_PC : UART_TX
    generic map (
        CLK_per_bit => c_CLK_PER_BIT
    )
    port map (
        i_clk      => i_clk,
        i_reset    => i_rst_n,
        i_tx_start => w_bt_rx_done,
        i_tx_data  => w_bt_data,
        o_tx_busy  => w_pc_tx_busy,
        o_tx_done  => open,
        o_tx_bit   => o_pc_tx
    );

end Behavioral;