----------------------------------------------------------------------------
-- Author:  Li Ling
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.TWIUtils.all;

entity rtc_subsystem is

  port(

    clk   : in  std_logic;
    srst  : in  std_logic;

    btnd_pulse : in  std_logic; -- Button pulse input
    sqw_rise   : in  std_logic; -- Square wave rising edge

    -- Set inputs (binary)
    set_sec   : in unsigned(7 downto 0); 
    set_min   : in unsigned(7 downto 0); 
    set_hour  : in unsigned(7 downto 0); 
    set_dow   : in unsigned(7 downto 0); 
    set_date  : in unsigned(7 downto 0); 
    set_month : in unsigned(7 downto 0); 
    set_year  : in unsigned(7 downto 0); 

    -- I2C interface
    I2C_SCL : inout std_logic; 
    I2C_SDA : inout std_logic; 

    rd_sec   : out unsigned(7 downto 0); 
    rd_min   : out unsigned(7 downto 0); 
    rd_hour  : out unsigned(7 downto 0); 
    rd_dow   : out unsigned(7 downto 0); 
    rd_date  : out unsigned(7 downto 0); 
    rd_month : out unsigned(7 downto 0); 
    rd_year  : out unsigned(7 downto 0); 

    busy  : out std_logic; -- Busy signal
    done  : out std_logic; -- Done signal
    error : out std_logic; -- Error signal
    etype : out error_type; -- Error type
    read_done_pulse : out std_logic -- Pulse when read operation finishes
  );

end entity;

architecture rtl of rtc_subsystem is
  -- Scheduler states
  type top_state_t is (T_INIT, T_IDLE, T_ISSUE, T_WAIT);
  signal tstate : top_state_t := T_INIT; -- Current state
  signal op_start      : std_logic := '0'; -- Operation start signal
  signal op_mode       : std_logic_vector(1 downto 0) := "00"; -- Operation mode
  signal pending_mode  : std_logic_vector(1 downto 0) := "10"; -- Pending operation mode
  constant OP_READ     : std_logic_vector(1 downto 0) := "00"; -- Read operation mode

  signal read_req     : std_logic := '0'; -- Read request signal
  signal read_req_clr : std_logic := '0'; -- Clear read request

  -- Configuration signals
  signal cfg_out    : std_logic := '0'; -- Configuration output
  signal cfg_sqw_en : std_logic := '1'; -- Enable square wave output
  signal cfg_rs     : std_logic_vector(1 downto 0) := "00"; -- Square wave rate select

  -- Outputs from DS1307Ctl
  signal busy_i, done_i, err_i : std_logic; -- Internal busy, done, and error signals
  signal etype_i : error_type; -- Internal error type

begin
  busy  <= busy_i; -- Map internal busy signal to output
  done  <= done_i; -- Map internal done signal to output
  error <= err_i; -- Map internal error signal to output
  etype <= etype_i; -- Map internal error type to output

  -- 1Hz read request latch
  process(clk)
  begin
    if rising_edge(clk) then
      if srst='1' then
        read_req <= '0'; -- Reset read request
      else
        if read_req_clr='1' then
          read_req <= '0'; -- Clear read request
        elsif sqw_rise='1' then
          read_req <= '1'; -- Set read request on square wave rising edge
        end if;
      end if;
    end if;
  end process;

  -- Scheduler process
  process(clk)
  begin
    if rising_edge(clk) then
      if srst='1' then
        tstate <= T_INIT; -- Initialize state
        op_start <= '0'; -- Reset operation start
        op_mode <= "00"; -- Reset operation mode
        pending_mode <= "10"; -- Reset pending mode
        read_req_clr <= '0'; -- Reset read request clear
      else
        op_start <= '0'; -- Default operation start
        read_req_clr <= '0'; -- Default read request clear
        case tstate is
          when T_INIT =>
            if busy_i='0' then
              pending_mode <= "10"; -- Write control (SQW=1Hz)
              tstate <= T_ISSUE; -- Transition to issue state
            end if;
          when T_IDLE =>
            if busy_i='0' then
              if btnd_pulse='1' then
                pending_mode <= "01"; -- Write time
                tstate <= T_ISSUE; -- Transition to issue state
              elsif read_req='1' then
                pending_mode <= OP_READ; -- Read operation
                read_req_clr <= '1'; -- Clear read request
                tstate <= T_ISSUE; -- Transition to issue state
              end if;
            end if;
          when T_ISSUE =>
            op_mode  <= pending_mode; -- Set operation mode
            op_start <= '1'; -- Start operation
            tstate   <= T_WAIT; -- Transition to wait state
          when T_WAIT =>
            if done_i='1' then
              tstate <= T_IDLE; -- Transition to idle state
            end if;
          when others =>
            tstate <= T_IDLE; -- Default to idle state
        end case;
      end if;
    end if;
  end process;

  -- Generate read_done_pulse when read operation finishes
  process(clk)
  begin
    if rising_edge(clk) then
      if srst='1' then
        read_done_pulse <= '0'; -- Reset read done pulse
      else
        read_done_pulse <= '0'; -- Default no pulse
        if (done_i='1') and (op_mode=OP_READ) then
          read_done_pulse <= '1'; -- Generate pulse on read completion
        end if;
      end if;
    end if;
  end process;

  -- DS1307Ctl instance
  u_rtc: entity work.DS1307Ctl
    generic map ( CLOCKFREQ_MHZ => 100 )
    port map(
      clk => clk,
      srst => srst,
      op_start => op_start,
      op_mode  => op_mode,
      busy => busy_i,
      done => done_i,
      error => err_i,
      errtype_o => etype_i,
      set_sec => set_sec,
      set_min => set_min,
      set_hour => set_hour,
      set_dow => set_dow,
      set_date => set_date,
      set_month => set_month,
      set_year => set_year,
      cfg_out => cfg_out,
      cfg_sqw_en => cfg_sqw_en,
      cfg_rs => cfg_rs,
      rd_sec => rd_sec,
      rd_min => rd_min,
      rd_hour => rd_hour,
      rd_dow => rd_dow,
      rd_date => rd_date,
      rd_month => rd_month,
      rd_year => rd_year,
      sda => I2C_SDA,
      scl => I2C_SCL
    );
end architecture;