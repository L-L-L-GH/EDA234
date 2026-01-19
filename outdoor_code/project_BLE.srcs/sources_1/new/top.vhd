----------------------------------------------------------------------------
-- Author:  Wentao Chen
----------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity UART_Loopback_Top is
    Generic (
        SYSTEM_CLK_FREQ : integer := 100000000; 
        BAUD_RATE       : integer := 9600     
    );
    Port (
        i_clk      : in  STD_LOGIC; 
        i_rst_n    : in  STD_LOGIC; 
        --BLE 
        i_bt_rx    : in  STD_LOGIC;
        o_bt_tx    : out STD_LOGIC;
        --USB
        i_pc_rx    : in  STD_LOGIC; 
        o_pc_tx    : out STD_LOGIC 
    );
end UART_Loopback_Top;

architecture Behavioral of UART_Loopback_Top is

  
    constant c_CLK_PER_BIT : integer := SYSTEM_CLK_FREQ / BAUD_RATE;

    
    signal w_rx_done : std_logic;                   
    signal w_data_byte : std_logic_vector(7 downto 0); 
    --signal i_rx_PC : std_logic;
    signal w_rx_done_FPGA : std_logic;
    signal w_data_byte_FPGA : std_logic_vector(7 downto 0);

    signal w_tx_busy : std_logic;                    

    
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

begin

    inst_uart_rx : UART_RX
    generic map (
        CLK_per_bit => c_CLK_PER_BIT 
    )
    port map (
        i_clk     => i_clk,
        i_reset   => i_rst_n,
        i_rx_bit  => i_bt_rx,    
        o_rx_done => w_rx_done,    
        o_rx_data => w_data_byte,  
        o_rx_busy => open         
    );

  
    inst_uart_tx : UART_TX
    generic map (
        CLK_per_bit => c_CLK_PER_BIT 
    )
    port map (
        i_clk      => i_clk,
        i_reset    => i_rst_n,
        i_tx_start => w_rx_done,   
        i_tx_data  => w_data_byte, 
        o_tx_busy  => w_tx_busy,
        o_tx_done  => open,
        o_tx_bit   => o_pc_tx    
    );

  
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