----------------------------------------------------------------------------
-- Author:  Li Ling
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity debounce_pulse is
  generic (
    DEBOUNCE_CYCLES : natural := 2_000_000
  );
  port (
    clk   : in  std_logic;
    srst  : in  std_logic;
    din   : in  std_logic;
    pulse : out std_logic       -- 1-cycle pulse on the rising edge of the debounced signal
  );
end entity;

architecture rtl of debounce_pulse is
  signal s1, s2           : std_logic := '0';
  signal last_sample      : std_logic := '0';
  signal deb              : std_logic := '0';
  signal prev_deb         : std_logic := '0';
  signal cnt              : unsigned(21 downto 0) := (others => '0');
begin
  -- 2 Flip-Flop Synchronizer
  process(clk)
  begin
    if rising_edge(clk) then
      if srst='1' then
        s1 <= '0';
        s2 <= '0';
      else
        s1 <= din;
        s2 <= s1;
      end if;
    end if;
  end process;

  -- Debounce + pulse
  process(clk)
  begin
    if rising_edge(clk) then
      if srst='1' then
        last_sample <= '0';
        deb         <= '0';
        prev_deb    <= '0';
        cnt         <= (others=>'0');
        pulse       <= '0';
      else
        pulse <= '0';

        if s2 /= last_sample then
          last_sample <= s2;
          cnt <= (others=>'0');
        else
          if cnt < to_unsigned(DEBOUNCE_CYCLES-1, cnt'length) then
            cnt <= cnt + 1;
          else
            deb <= last_sample;
          end if;
        end if;

        if (deb='1') and (prev_deb='0') then
          pulse <= '1';
        end if;
        prev_deb <= deb;
      end if;
    end if;
  end process;
end architecture;