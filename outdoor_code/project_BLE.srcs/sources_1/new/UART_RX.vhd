----------------------------------------------------------------------------
-- Author:  Wentao Chen
----------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity UART_RX is
  generic (
    CLK_per_bit : integer := 10417--100MHZ/9600
  );
  port (
    i_clk   : in std_logic;
    i_reset : in std_logic;
    --i_rx_start : in std_logic;
    i_rx_bit  : in std_logic;
    o_rx_done : out std_logic;
    o_rx_data : out std_logic_vector(7 downto 0);
    o_rx_busy : out std_logic
  );
end UART_RX;

architecture Behavioral of UART_RX is
  type state is (IDLE, START, DATA, STOP);
  signal r_state  : state := IDLE;
  signal r_rx_bit : std_logic := '1';
  signal r_rx_bit_meta : std_logic := '1';
  signal r_rx_data  : std_logic_vector(7 downto 0)       := (others => '0');
  signal clk_count  : integer range 0 to CLK_per_bit - 1 := 0;
  signal data_index : integer range 0 to 7               := 0;
begin
  process (i_clk, i_reset)
  begin
    if i_reset = '0' then
      r_state <= IDLE;
      --r_rx_data <= (others => '0');
      o_rx_busy <= '0';
      o_rx_done <= '0';
      clk_count <= 0;
      data_index <= 0;
    elsif rising_edge(i_clk) then
      r_rx_bit_meta <= i_rx_bit;
      r_rx_bit      <= r_rx_bit_meta;
      o_rx_done <= '0';
      case r_state is
        when IDLE =>
          o_rx_busy <= '0';
          clk_count <= 0;
          
          if r_rx_bit = '0' then--start bit(from 1 to 0)
            r_state <= START;
          else
            r_state <= IDLE;
          end if;
        when START =>
        o_rx_busy <= '1';
          -- double check if data arrives
          if clk_count = (CLK_per_bit - 1)/2 then
            if r_rx_bit = '0' then
              r_state <= DATA;
              clk_count <= 0;
            else
              r_state <= IDLE;
            end if;
          else
              clk_count <= clk_count + 1;
          end if;
        when DATA =>
        o_rx_busy <= '1';
        if clk_count =  CLK_per_bit - 1 then
          r_rx_data(data_index) <= r_rx_bit;
          clk_count <= 0;
          --receive finished
          if data_index = 7 then
            data_index <=0;
            r_state <= STOP;
          else
            data_index <= data_index+1;
          end if;
          else
            clk_count <= clk_count+1;          
        end if;
        when STOP =>
        if clk_count = CLK_per_bit - 1 then
          o_rx_done <= '1';
          o_rx_busy <= '0';
          clk_count <= 0;
          r_state <= IDLE;
        else
          clk_count <= clk_count+1;
          
        end if;

        when others =>
        r_state <= IDLE;
      end case;

    end if;
  end process;
  o_rx_data <= r_rx_data;
end Behavioral;
