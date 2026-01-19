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
        SYSTEM_CLK_FREQ : integer := 100000000; 
        BAUD_RATE       : integer := 9600    
    );
    Port (
        i_clk      : in    STD_LOGIC; 
        i_rst_n    : in    STD_LOGIC; 
        TMP_DQ     : inout STD_LOGIC; 
        i_bt_rx    : in    STD_LOGIC; 
        o_bt_tx    : out   STD_LOGIC; 

        i_pc_rx    : in    STD_LOGIC; 
        o_pc_tx    : out   STD_LOGIC  
    );
end UART_Loopback_Top;

architecture Behavioral of UART_Loopback_Top is

 
    constant c_CLK_PER_BIT : integer := SYSTEM_CLK_FREQ / BAUD_RATE;

    signal w_bt_rx_done : std_logic;
    signal w_bt_data    : std_logic_vector(7 downto 0);
    signal w_pc_tx_busy : std_logic;
    signal w_dq_in    : std_logic;
    signal w_dq_out   : std_logic;
    signal w_dq_oe    : std_logic;
    signal w_temp_raw : std_logic_vector(15 downto 0);
    signal w_temp_done: std_logic; 
    signal w_ascii_data  : std_logic_vector(7 downto 0);
    signal w_ascii_start : std_logic;
    signal w_bt_tx_done  : std_logic; 
    signal w_bt_tx_busy  : std_logic;

    signal w_trigger_conversion : std_logic;
    type cmd_state_t is (WAIT_G, WAIT_O, ARMED);
    signal current_cmd_state : cmd_state_t := WAIT_G;

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

    -- w_trigger_conversion goes high only when the state machine is in ARMED (received "go") and the sensor is done (w_temp_done).
    w_trigger_conversion <= '1' when (current_cmd_state = ARMED and w_temp_done = '1') else '0';

    process(i_clk, i_rst_n)
    begin
        if i_rst_n = '0' then
            current_cmd_state <= WAIT_G;
        elsif rising_edge(i_clk) then
            if current_cmd_state = ARMED and w_temp_done = '1' then
                current_cmd_state <= WAIT_G;
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
                            current_cmd_state <= ARMED; 
                        elsif w_bt_data = x"67" then 
                             current_cmd_state <= WAIT_O;
                        else
                            current_cmd_state <= WAIT_G; 
                        end if;
                    when ARMED =>
                        null; 
                    when others =>
                        current_cmd_state <= WAIT_G;
                end case;
            end if;
        end if;
    end process;

    TMP_DQ <= '0' when w_dq_oe = '1' else 'Z';
    w_dq_in <= TMP_DQ;

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

    inst_temp_to_ascii : Temp_to_ASCII
    port map (
        clk           => i_clk,
        rst_n         => i_rst_n,
        i_temp_data   => w_temp_raw,
        i_temp_done   => w_trigger_conversion, 
        i_uart_done   => w_bt_tx_done,
        o_uart_data   => w_ascii_data,
        o_uart_start  => w_ascii_start
    );

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