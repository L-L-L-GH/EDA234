----------------------------------------------------------------------------
-- Author:  Hanyin Gu
----------------------------------------------------------------------------

library ieee;

use ieee.std_logic_1164.all;

entity mode_ctrl is

  port(

    clk         : in  std_logic;

    srst        : in  std_logic;

    key_fire    : in  std_logic;

    key_val     : in  integer range 0 to 15;

    disp_mode   : out std_logic_vector(1 downto 0); -- 00 DATE, 01 TIME, 10 TEMP

    mode_change : out std_logic

  );

end entity;

architecture rtl of mode_ctrl is

  signal mode_r, mode_d : std_logic_vector(1 downto 0) := "00";

begin

  disp_mode <= mode_r;

  process(clk)

  begin

    if rising_edge(clk) then

      if srst='1' then
        mode_r      <= "00";
        mode_d      <= "00";
        mode_change <= '0';
      else
        mode_change <= '0';
        mode_d <= mode_r;

        if key_fire='1' then
          if    key_val=1 then mode_r <= "00"; -- Switch to DATE mode
          elsif key_val=2 then mode_r <= "01"; -- Switch to TIME mode
          elsif key_val=3 then mode_r <= "10"; -- Switch to TEMP mode
          end if;
        end if;

        if mode_r /= mode_d then
          mode_change <= '1'; -- Indicate mode change
        end if;

      end if;

    end if;

  end process;

end architecture;