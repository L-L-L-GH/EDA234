----------------------------------------------------------------------------
-- Author:  Li Ling
----------------------------------------------------------------------------

library ieee;

use ieee.std_logic_1164.all;

entity reset_sync is

  port (

    clk       : in  std_logic;

    rst_in    : in  std_logic;  -- BTNC, asynchronous input

    srst      : out std_logic;  -- Synchronized reset, active-high

    lcd_rst_n : out std_logic   -- Active-low reset for LCD

  );

end entity;

architecture rtl of reset_sync is

  signal r1, r2 : std_logic := '0';

begin

  process(clk)

  begin

    if rising_edge(clk) then

      r1 <= rst_in; -- Capture asynchronous reset input
      r2 <= r1;     -- Synchronize reset signal

    end if;

  end process;

  srst      <= r2;       -- Assign synchronized reset
  lcd_rst_n <= not r2;   -- Generate active-low reset for LCD

end architecture;