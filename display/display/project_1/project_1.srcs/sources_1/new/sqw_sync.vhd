----------------------------------------------------------------------------
-- Author:  Li Ling
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity sqw_sync is

  port(

    clk     : in  std_logic;
    srst    : in  std_logic;
    sqw_in  : in  std_logic;
    sqw_rise: out std_logic;
    led_sqw : out std_logic

  );

end entity;

architecture rtl of sqw_sync is

  signal s1, s2 : std_logic := '0'; -- Synchronization registers
  signal prev   : std_logic := '0'; -- Previous state of sqw_in
  signal led_r  : std_logic := '0'; -- LED toggle register

begin

  led_sqw <= led_r; -- Drive LED output

  process(clk)
  begin
    if rising_edge(clk) then
      if srst='1' then
        s1 <= '0'; s2 <= '0'; -- Reset synchronization registers
        prev <= '0';          -- Reset previous state
        sqw_rise <= '0';      -- Reset rising edge signal
        led_r <= '0';         -- Reset LED state
      else
        s1 <= sqw_in;         -- Synchronize sqw_in
        s2 <= s1;             -- Further synchronization
        sqw_rise <= '0';      -- Default no rising edge
        if (s2='1' and prev='0') then
          sqw_rise <= '1';    -- Detect rising edge
          led_r <= not led_r; -- Toggle LED
        end if;
        prev <= s2;           -- Update previous state
      end if;
    end if;
  end process;

end architecture;