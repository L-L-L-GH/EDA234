----------------------------------------------------------------------------
-- Author:  Li Ling
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity led_hold is
  generic (
    HOLD_CYCLES : natural := 20_000_000 -- Number of cycles to hold the LED state
  );
  port(
    clk     : in  std_logic; -- Clock signal
    srst    : in  std_logic; -- Synchronous reset
    done_p  : in  std_logic; -- Done signal
    error_l : in  std_logic; -- Error signal 
    busy    : in  std_logic; -- Busy signal
    led_sqw : in  std_logic; -- LED square wave input
    LED     : out std_logic_vector(3 downto 0) -- LED output vector
  );
end entity;

architecture rtl of led_hold is
  signal done_hold_cnt : unsigned(31 downto 0) := (others => '0'); -- Counter for done signal hold
  signal err_hold_cnt  : unsigned(31 downto 0) := (others => '0'); -- Counter for error signal hold
  signal led_done_hold : std_logic := '0'; -- LED state for done signal
  signal led_err_hold  : std_logic := '0'; -- LED state for error signal
begin
  -- Process to handle LED hold logic
  process(clk)
  begin
    if rising_edge(clk) then
      if srst = '1' then
        done_hold_cnt <= (others => '0');
        err_hold_cnt  <= (others => '0');
        led_done_hold <= '0';
        led_err_hold  <= '0';
      else
        if done_p = '1' then
          led_done_hold <= '1';
          done_hold_cnt <= to_unsigned(HOLD_CYCLES, done_hold_cnt'length);
        elsif done_hold_cnt /= 0 then
          done_hold_cnt <= done_hold_cnt - 1;
        else
          led_done_hold <= '0';
        end if;

        if error_l = '1' then
          led_err_hold <= '1';
          err_hold_cnt <= to_unsigned(HOLD_CYCLES, err_hold_cnt'length);
        elsif err_hold_cnt /= 0 then
          err_hold_cnt <= err_hold_cnt - 1;
        else
          led_err_hold <= '0';
        end if;
      end if;
    end if;
  end process;

  -- Assign LED outputs
  LED(0) <= led_done_hold; -- LED for done signal
  LED(1) <= led_err_hold;  -- LED for error signal
  LED(2) <= busy;          -- LED for busy signal
  LED(3) <= led_sqw;       -- LED for square wave input
end architecture;