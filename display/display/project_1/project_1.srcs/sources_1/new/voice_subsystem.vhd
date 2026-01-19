----------------------------------------------------------------------------
-- Author:  Hanyin Gu
----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity voice_subsystem is

  port(

    clk      : in  std_logic;
    srst     : in  std_logic;
    key_fire : in  std_logic;
    key_val  : in  integer range 0 to 15;
    aud_pwm  : out std_logic;
    aud_sd   : out std_logic

  );

end entity;

architecture rtl of voice_subsystem is

  constant LEN_DATE : unsigned(16 downto 0) := to_unsigned(19275, 17); -- Length of DATE audio
  constant LEN_TEMP : unsigned(16 downto 0) := to_unsigned(19275, 17); -- Length of TEMP audio
  constant LEN_TIME : unsigned(16 downto 0) := to_unsigned(20960, 17); -- Length of TIME audio
  type v_state_type is (V_IDLE, V_PLAY_TEMP, V_PLAY_DATE, V_PLAY_TIME); -- FSM states
  signal v_state  : v_state_type := V_IDLE;
  signal addr_cnt  : unsigned(16 downto 0) := (others => '0'); -- Address counter
  signal clk_div   : unsigned(15 downto 0) := (others => '0'); -- Clock divider
  signal sample_en : std_logic := '0'; -- Sample enable signal
  signal data_temp  : std_logic_vector(7 downto 0); -- TEMP audio data
  signal data_date  : std_logic_vector(7 downto 0); -- DATE audio data
  signal data_time  : std_logic_vector(7 downto 0); -- TIME audio data
  signal data_final : std_logic_vector(7 downto 0); -- Final audio data

  -- Synchronization and edge detection
  signal key_fire_meta : std_logic := '0'; -- Metastability register
  signal key_fire_sync : std_logic := '0'; -- Synchronized key_fire
  signal key_fire_d    : std_logic := '0'; -- Delayed key_fire
  signal start_pulse   : std_logic := '0'; -- Start pulse signal
  signal key_val_lat   : integer range 0 to 15 := 0; -- Latched key value

begin

  aud_sd <= '1'; -- Audio shutdown signal

  -- Synchronize key_fire to clk and generate a 1-cycle pulse
  process(clk)
  begin
    if rising_edge(clk) then
      if srst='1' then
        key_fire_meta <= '0';
        key_fire_sync <= '0';
        key_fire_d    <= '0';
        start_pulse   <= '0';
      else
        key_fire_meta <= key_fire;
        key_fire_sync <= key_fire_meta;
        start_pulse   <= key_fire_sync and (not key_fire_d); -- Rising edge pulse
        key_fire_d    <= key_fire_sync;
      end if;
    end if;
  end process;

  -- Generate 8kHz sample enable signal
  process(clk)
  begin
    if rising_edge(clk) then
      if srst='1' then
        clk_div   <= (others => '0');
        sample_en <= '0';
      else
        if clk_div = 12499 then
          clk_div   <= (others => '0');
          sample_en <= '1';
        else
          clk_div   <= clk_div + 1;
          sample_en <= '0';
        end if;
      end if;
    end if;
  end process;

  -- Voice FSM: key 1 -> PLAY_DATE, key 2 -> PLAY_TIME, key 3 -> PLAY_TEMP
  process(clk)
  begin
    if rising_edge(clk) then
      if srst='1' then
        v_state    <= V_IDLE;
        addr_cnt   <= (others => '0');
        key_val_lat <= 0;
      else
        if (start_pulse='1') and (v_state = V_IDLE) then
          addr_cnt    <= (others => '0');
          key_val_lat <= key_val; -- Latch the key value at trigger time
          if key_val = 1 then
            v_state <= V_PLAY_DATE;
          elsif key_val = 2 then
            v_state <= V_PLAY_TIME;
          elsif key_val = 3 then
            v_state <= V_PLAY_TEMP;
          else
            v_state <= V_IDLE;
          end if;
        elsif sample_en = '1' then
          case v_state is
            when V_PLAY_TEMP =>
              if addr_cnt < (LEN_TEMP - 1) then
                addr_cnt <= addr_cnt + 1;
              else
                v_state  <= V_IDLE;
                addr_cnt <= (others => '0');
              end if;
            when V_PLAY_DATE =>
              if addr_cnt < (LEN_DATE - 1) then
                addr_cnt <= addr_cnt + 1;
              else
                v_state  <= V_IDLE;
                addr_cnt <= (others => '0');
              end if;
            when V_PLAY_TIME =>
              if addr_cnt < (LEN_TIME - 1) then
                addr_cnt <= addr_cnt + 1;
              else
                v_state  <= V_IDLE;
                addr_cnt <= (others => '0');
              end if;
            when others =>
              addr_cnt <= (others => '0');
          end case;
        end if;
      end if;
    end if;
  end process;

  -- ROM instances
  ROM_TEMP_INST : entity work.rom_temp
    port map (
      clka  => clk,
      addra => std_logic_vector(addr_cnt(15 downto 0)),
      douta => data_temp
    );

  ROM_DATE_INST : entity work.rom_date
    port map (
      clka  => clk,
      addra => std_logic_vector(addr_cnt(15 downto 0)),
      douta => data_date
    );

  ROM_TIME_INST : entity work.rom_time
    port map (
      clka  => clk,
      addra => std_logic_vector(addr_cnt(15 downto 0)),
      douta => data_time
    );

  -- Data multiplexer
  data_final <= data_temp when (v_state = V_PLAY_TEMP) else
                data_date when (v_state = V_PLAY_DATE) else
                data_time when (v_state = V_PLAY_TIME) else
                (others => '0');

  -- PWM driver instance
  PWM_INST : entity work.pwm_driver
    port map (
      clk     => clk,
      data_in => data_final,
      pwm_out => aud_pwm
    );

end architecture;
