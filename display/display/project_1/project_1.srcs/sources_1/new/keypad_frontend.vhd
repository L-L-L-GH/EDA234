----------------------------------------------------------------------------
-- Author:  Hanyin Gu
----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity declaration for the keypad frontend
entity keypad_frontend is
  port(
    clk      : in  std_logic; -- Clock signal
    row      : in  std_logic_vector(3 downto 0); -- Input rows
    col      : out std_logic_vector(3 downto 0); -- Output columns
    key_val  : out integer range 0 to 15; -- Key value
    key_fire : out std_logic -- Key press event
  );
end entity;

architecture rtl of keypad_frontend is
  signal key_pressed   : std_logic := '0'; -- Indicates if a key is pressed
  signal key_pressed_d : std_logic := '0'; -- Delayed key press signal
begin
  -- Keyboard scanner instantiation
  u_kb: entity work.keyboard_scanner
    port map(
      clk         => clk,
      row         => row,
      col         => col,
      key_val     => key_val,
      key_pressed => key_pressed
    );

  -- Process to detect key press events
  process(clk)
  begin
    if rising_edge(clk) then
      key_pressed_d <= key_pressed;
      key_fire      <= key_pressed and (not key_pressed_d);
    end if;
  end process;
end architecture;