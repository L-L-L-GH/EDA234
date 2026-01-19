----------------------------------------------------------------------------
-- Author:  Li Ling
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity clock_7seg_mux is
  port(
    clk   : in  std_logic;  -- 100MHz
    srst  : in  std_logic;  -- reset

    mode_date : in std_logic;  -- '0': YYYYMMDD, '1': HHMMSS

    year  : in unsigned(7 downto 0); -- 0..99
    month : in unsigned(7 downto 0); -- 1..12
    date  : in unsigned(7 downto 0); -- 1..31
    hour  : in unsigned(7 downto 0); -- 0..23
    min   : in unsigned(7 downto 0); -- 0..59
    sec   : in unsigned(7 downto 0); -- 0..59

    segments_out : out std_logic_vector(6 downto 0); -- gfedcba, '0'=ON
    AN           : out std_logic_vector(7 downto 0)  -- '0'=enable digit
  );
end entity;

architecture rtl of clock_7seg_mux is

  constant CLK_FREQ     : integer := 100_000_000;
  constant REFRESH_FREQ : integer := 1000;
  constant REFRESH_MAX  : integer := CLK_FREQ / REFRESH_FREQ - 1;

  signal refresh_cnt : integer range 0 to REFRESH_MAX := 0;
  signal mux_tick    : std_logic := '0';

  signal digit_idx : integer range 0 to 7 := 0;

  -- precomputed decimal digits (integers)
  signal y_i, mo_i, d_i, h_i, mi_i, s_i : integer range 0 to 99 := 0;
  signal y_t, y_o   : integer range 0 to 9 := 0;
  signal mo_t, mo_o : integer range 0 to 9 := 0;
  signal d_t, d_o   : integer range 0 to 9 := 0;
  signal h_t, h_o   : integer range 0 to 9 := 0;
  signal mi_t, mi_o : integer range 0 to 9 := 0;
  signal s_t, s_o   : integer range 0 to 9 := 0;

  signal digit_to_decode : integer range 0 to 15 := 15; -- 0..9 valid, 15=blank

begin

  -- refresh tick
  process(clk)
  begin
    if rising_edge(clk) then
      if srst = '1' then
        refresh_cnt <= 0;
        mux_tick <= '0';
      else
        mux_tick <= '0';
        if refresh_cnt = REFRESH_MAX then
          refresh_cnt <= 0;
          mux_tick <= '1';
        else
          refresh_cnt <= refresh_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  -- digit index rotate
  process(clk)
  begin
    if rising_edge(clk) then
      if srst = '1' then
        digit_idx <= 0;
      else
        if mux_tick = '1' then
          if digit_idx = 7 then
            digit_idx <= 0;
          else
            digit_idx <= digit_idx + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- compute decimal split
  process(year, month, date, hour, min, sec)
  begin
    y_i  <= to_integer(year);
    mo_i <= to_integer(month);
    d_i  <= to_integer(date);
    h_i  <= to_integer(hour);
    mi_i <= to_integer(min);
    s_i  <= to_integer(sec);

    y_t  <= y_i  / 10;  y_o  <= y_i  mod 10;
    mo_t <= mo_i / 10;  mo_o <= mo_i mod 10;
    d_t  <= d_i  / 10;  d_o  <= d_i  mod 10;
    h_t  <= h_i  / 10;  h_o  <= h_i  mod 10;
    mi_t <= mi_i / 10;  mi_o <= mi_i mod 10;
    s_t  <= s_i  / 10;  s_o  <= s_i  mod 10;
  end process;

  -- AN select (active-low)
  process(digit_idx)
  begin
    case digit_idx is
      when 0 => AN <= "11111110";
      when 1 => AN <= "11111101";
      when 2 => AN <= "11111011";
      when 3 => AN <= "11110111";
      when 4 => AN <= "11101111";
      when 5 => AN <= "11011111";
      when 6 => AN <= "10111111";
      when others => AN <= "01111111";
    end case;
  end process;

  -- choose digit value by mode
  process(mode_date, digit_idx, y_t, y_o, mo_t, mo_o, d_t, d_o, h_t, h_o, mi_t, mi_o, s_t, s_o)
  begin
    digit_to_decode <= 15; -- blank default

    if mode_date = '0' then
      -- Date mode: display "20YYMMDD"
      case digit_idx is
        when 0 => digit_to_decode <= d_o;
        when 1 => digit_to_decode <= d_t;
        when 2 => digit_to_decode <= mo_o;
        when 3 => digit_to_decode <= mo_t;
        when 4 => digit_to_decode <= y_o;
        when 5 => digit_to_decode <= y_t;
        when 6 => digit_to_decode <= 0; -- '0'
        when others => digit_to_decode <= 2; -- '2'
      end case;
    else
      -- Time mode: display "HHMMSS" 
      case digit_idx is
        when 0 => digit_to_decode <= s_o;
        when 1 => digit_to_decode <= s_t;
        when 2 => digit_to_decode <= mi_o;
        when 3 => digit_to_decode <= mi_t;
        when 4 => digit_to_decode <= h_o;
        when 5 => digit_to_decode <= h_t;
        when others => digit_to_decode <= 15; -- blank
      end case;
    end if;
  end process;

  -- digit decoder
  process(digit_to_decode)
  begin
    case digit_to_decode is
      when 0 => segments_out <= "1000000";
      when 1 => segments_out <= "1111001";
      when 2 => segments_out <= "0100100";
      when 3 => segments_out <= "0110000";
      when 4 => segments_out <= "0011001";
      when 5 => segments_out <= "0010010";
      when 6 => segments_out <= "0000010";
      when 7 => segments_out <= "1111000";
      when 8 => segments_out <= "0000000";
      when 9 => segments_out <= "0010000";
      when 15 => segments_out <= "1111111"; -- blank
      when others => segments_out <= "0111111"; -- 'E'
    end case;
  end process;

end architecture;
