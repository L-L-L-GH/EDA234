----------------------------------------------------------------------------
-- Author:  Wentao Chen
----------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity UART_TX is
  generic (
    CLK_per_bit : integer := 10417--100MHZ/9600
  );
  port (
    i_clk      : in std_logic;
    i_reset    : in std_logic;
    i_tx_start : in std_logic;
    i_tx_data  : in std_logic_vector(7 downto 0);
    o_tx_busy  : out std_logic;
    o_tx_done  : out std_logic;
    o_tx_bit   : out std_logic

  );
end entity UART_TX;

architecture tx of UART_TX is
  type state is (IDLE, START, DATA, STOP);
  signal r_state    : state                              := IDLE;
  signal r_tx_data  : std_logic_vector(7 downto 0)       := (others => '0');
  signal clk_count  : integer range 0 to CLK_per_bit - 1 := 0;
  signal data_index : integer range 0 to 7               := 0;
begin
  process (i_clk, i_reset)
  begin
    --reset signals
    if i_reset = '0' then
      r_state   <= IDLE;
      r_tx_data <= (others => '0');
      o_tx_busy <= '0';
      o_tx_done <= '0';
      o_tx_bit  <= '1';--idle(high)

    elsif rising_edge(i_clk) then
      case r_state is
        when IDLE =>
          o_tx_bit  <= '1';
          o_tx_done <= '0';
          o_tx_busy <= '0';
          --next state : start transmit data
          if i_tx_start = '1' then
            r_tx_data <= i_tx_data;
            r_state   <= START;
          end if;

        when START =>
          o_tx_busy <= '1';
          o_tx_bit  <= '0';--send start bit(low)
          if clk_count = CLK_per_bit - 1 then
            clk_count <= 0;
            data_index <=0;
            r_state   <= DATA;
          else
            clk_count <= clk_count + 1;
          end if;

        when DATA =>
          --send the LSB first
          o_tx_bit <= r_tx_data(data_index);

          if clk_count = CLK_per_bit - 1 then
            clk_count <= 0;
            if data_index = 7 then
             
              r_state    <= STOP;
            else
              data_index <= data_index + 1;
            end if;
          else 
            clk_count<=clk_count+1;
          end if;

        when STOP =>
          o_tx_bit <= '1'; --send end bit(high)
          if clk_count = CLK_per_bit - 1 then
            clk_count <= 0;
            r_state   <= IDLE;
            o_tx_done <= '1';
            o_tx_busy <= '0';
          else
            clk_count <= clk_count + 1;
          end if;
        when others =>
          r_state <= IDLE;
      end case;
    end if;
  end process;

end architecture tx;