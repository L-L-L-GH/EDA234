----------------------------------------------------------------------------
-- Author:  Li Ling, Wentao Chen, Hanyin Gu, Ruxuan Wen
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.TWIUtils.all;

entity top is
  port (
    CLK100MHZ : in  std_logic;
    BTNC : in std_logic;
    BTND : in std_logic;
    SW   : in std_logic_vector(15 downto 0);

    row  : in  std_logic_vector(3 downto 0);
    col  : out std_logic_vector(3 downto 0);

    aud_pwm : out std_logic;
    aud_sd  : out std_logic;

    LED  : out std_logic_vector(3 downto 0);

    SEG  : out std_logic_vector(6 downto 0);
    AN   : out std_logic_vector(7 downto 0);

    I2C_SCL : inout std_logic;
    I2C_SDA : inout std_logic;
    SQW_IN  : in std_logic;

    lcd_rs   : out std_logic;
    lcd_rw   : out std_logic;
    lcd_e    : out std_logic;
    lcd_data : out std_logic_vector(3 downto 0);
    refresh_led : out std_logic;
    TMP_SCL     : inout std_logic;
    TMP_SDA     : inout std_logic
  );
end entity;

architecture rtl of top is
  signal clk : std_logic;
  signal srst, lcd_rst_n : std_logic;

  -- Keypad signals
  signal key_fire : std_logic;
  signal key_val  : integer range 0 to 15;

  -- Display mode signals
  signal disp_mode   : std_logic_vector(1 downto 0);
  signal mode_change : std_logic;

  -- Button debounce pulse
  signal btnd_pulse : std_logic;

  -- sqw
  signal sqw_rise : std_logic;
  signal led_sqw  : std_logic;

  -- rtc
  signal rd_sec, rd_min, rd_hour, rd_dow, rd_date, rd_month, rd_year : unsigned(7 downto 0);
  signal busy, done, error : std_logic;
  signal etype : error_type;
  signal read_done_pulse : std_logic;

  -- Set fields
  signal set_sec, set_min, set_hour, set_dow, set_date, set_month, set_year : unsigned(7 downto 0);
  signal mode_date_7seg : std_logic := '0';

  -- Temperature signals
  signal TEMP_FINAL_O : integer range -8192 to 8191;
  signal w_raw_temp : std_logic_vector(12 downto 0);
  signal w_rdy : std_logic;
  signal w_err : std_logic;

begin
  clk <= CLK100MHZ;
  mode_date_7seg <= '0' when (disp_mode = "00") else '1';


  set_sec   <= to_unsigned(56, 8);
  set_dow   <= to_unsigned(5,  8);
  set_date  <= to_unsigned(22, 8);
  set_month <= to_unsigned(01, 8);
  set_year  <= to_unsigned(26, 8);
  set_hour  <= resize(unsigned(SW(10 downto 6)), 8);
  set_min   <= resize(unsigned(SW(5 downto 0)), 8);

  Inst_TempSensorCtl: entity work.TempSensorCtl
    generic map(
        CLOCKFREQ => 100 -- 100MHz
    )
    port map(
        TMP_SCL => TMP_SCL,
        TMP_SDA => TMP_SDA,
        CLK_I   => clk,
        SRST_I  => srst,
        TEMP_O  => w_raw_temp, -- Output connected to intermediate signal
        RDY_O   => w_rdy,
        ERR_O   => w_err
    );

  -- Temperature conversion module instance
  Inst_TempConversion: entity work.TempConversion
    port map(
        CLK_I      => clk,
        RAW_TEMP_I => w_raw_temp, -- Input connected to intermediate signal
        TEMP_X10_O => TEMP_FINAL_O -- Output connected to the desired display location
    );

  -- Reset synchronization instance
  u_rst: entity work.reset_sync
    port map(clk=>clk, rst_in=>BTNC, srst=>srst, lcd_rst_n=>lcd_rst_n);

  -- Button debounce instance
  u_btnd: entity work.debounce_pulse
    generic map(DEBOUNCE_CYCLES => 2_000_000)
    port map(clk=>clk, srst=>srst, din=>BTND, pulse=>btnd_pulse);

  -- Keypad frontend instance
  u_kp: entity work.keypad_frontend
    port map(clk=>clk, row=>row, col=>col, key_val=>key_val, key_fire=>key_fire);

  -- Mode control instance
  u_mode: entity work.mode_ctrl
    port map(clk=>clk, srst=>srst, key_fire=>key_fire, key_val=>key_val,
             disp_mode=>disp_mode, mode_change=>mode_change);

  -- Square wave synchronization instance
  u_sqw: entity work.sqw_sync
    port map(clk=>clk, srst=>srst, sqw_in=>SQW_IN, sqw_rise=>sqw_rise, led_sqw=>led_sqw);

  -- RTC subsystem instance
  u_rtc: entity work.rtc_subsystem
    port map(
      clk=>clk, srst=>srst,
      btnd_pulse=>btnd_pulse,
      sqw_rise=>sqw_rise,
      set_sec=>set_sec, set_min=>set_min, set_hour=>set_hour,
      set_dow=>set_dow, set_date=>set_date, set_month=>set_month, set_year=>set_year,
      I2C_SCL=>I2C_SCL, I2C_SDA=>I2C_SDA,
      rd_sec=>rd_sec, rd_min=>rd_min, rd_hour=>rd_hour, rd_dow=>rd_dow,
      rd_date=>rd_date, rd_month=>rd_month, rd_year=>rd_year,
      busy=>busy, done=>done, error=>error, etype=>etype,
      read_done_pulse=>read_done_pulse
    );

  -- LED control instance
  u_led: entity work.led_hold
    port map(clk=>clk, srst=>srst, done_p=>done, error_l=>error, busy=>busy, led_sqw=>led_sqw, LED=>LED);

  -- 7-segment display multiplexer instance
  u_7seg: entity work.clock_7seg_mux
    port map(
      clk => clk, srst => srst,
      mode_date => mode_date_7seg,
      year=>rd_year, month=>rd_month, date=>rd_date,
      hour=>rd_hour, min=>rd_min, sec=>rd_sec,
      segments_out=>SEG, AN=>AN
    );

  -- LCD subsystem instance
  u_lcd: entity work.lcd_subsystem
    port map(
      clk=>clk, srst=>srst, lcd_rst_n=>lcd_rst_n,
      disp_mode=>disp_mode, mode_change=>mode_change, read_done_p=>read_done_pulse,
      rd_sec=>rd_sec, rd_min=>rd_min, rd_hour=>rd_hour,
      rd_date=>rd_date, rd_month=>rd_month, rd_year=>rd_year,
      temp_x10=>TEMP_FINAL_O,
      lcd_rs=>lcd_rs, lcd_rw=>lcd_rw, lcd_e=>lcd_e, lcd_data=>lcd_data,
      refresh_led=>refresh_led
    );

  -- Voice subsystem instance
  u_voice: entity work.voice_subsystem
    port map(clk=>clk, srst=>srst, key_fire=>key_fire, key_val=>key_val,
             aud_pwm=>aud_pwm, aud_sd=>aud_sd);
end architecture;