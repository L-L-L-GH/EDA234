----------------------------------------------------------------------------
-- Author:  Li Ling
----------------------------------------------------------------------------

library ieee; 
use ieee.std_logic_1164.all; 
use ieee.numeric_std.all; 

entity lcd_subsystem is 
  port( 
    clk         : in  std_logic; 
    srst        : in  std_logic; 
    lcd_rst_n   : in  std_logic; 
    disp_mode    : in std_logic_vector(1 downto 0); -- 00 DATE, 01 TIME, 10 TEMP 
    mode_change  : in std_logic; 
    read_done_p  : in std_logic; 
    rd_sec   : in unsigned(7 downto 0); 
    rd_min   : in unsigned(7 downto 0); 
    rd_hour  : in unsigned(7 downto 0); 
    rd_date  : in unsigned(7 downto 0); 
    rd_month : in unsigned(7 downto 0); 
    rd_year  : in unsigned(7 downto 0); 
    temp_x10 : in integer; 
    lcd_rs   : out std_logic; 
    lcd_rw   : out std_logic; 
    lcd_e    : out std_logic; 
    lcd_data : out std_logic_vector(3 downto 0); 
    refresh_led : out std_logic 
  ); 
end entity; 

architecture rtl of lcd_subsystem is 
  --------------------------------------------------------------------------- 
  -- LCD components
  --------------------------------------------------------------------------- 
  component lcd_controller is 
    generic(SIMULATION_MODE : boolean := false); 
    port( 
      clk         : in  std_logic; 
      rst_n       : in  std_logic; 
      lcd_rs      : out std_logic; 
      lcd_rw      : out std_logic; 
      lcd_e       : out std_logic; 
      lcd_data    : out std_logic_vector(3 downto 0); 
      ram_raddr   : out integer range 0 to 31; 
      ram_rdata   : in  std_logic_vector(7 downto 0); 
      refresh_led : out std_logic 
    ); 
  end component; 

  component lcd_text_ram is 
    port( 
      clk   : in  std_logic; 
      waddr : in  integer range 0 to 31; 
      wdata : in  std_logic_vector(7 downto 0); 
      raddr : in  integer range 0 to 31; 
      rdata : out std_logic_vector(7 downto 0) 
    ); 
  end component; 

  signal ram_waddr  : integer range 0 to 31 := 31; 
  signal ram_wdata  : std_logic_vector(7 downto 0) := x"20"; 
  signal ram_raddr  : integer range 0 to 31 := 0; 
  signal ram_rdata  : std_logic_vector(7 downto 0) := x"20"; 

  --------------------------------------------------------------------------- 
  -- LCD auto-write state machine 
  --------------------------------------------------------------------------- 

  -- Modify state definitions
  type lcdw_state_t is (LW_IDLE, LW_CALC_INIT, LW_CALC_100, LW_CALC_10, LW_WRITE_0_15, LW_FILL_16_31);
  signal lw_state : lcdw_state_t := LW_IDLE;
  -- Temporary registers used for calculations
  signal t_run : integer range 0 to 8191 := 0;
  signal lw_idx   : integer range 0 to 31 := 0;

  -- snapshot for stable write
  signal cap_year  : unsigned(7 downto 0) := (others => '0'); 
  signal cap_month : unsigned(7 downto 0) := (others => '0'); 
  signal cap_date  : unsigned(7 downto 0) := (others => '0'); 
  signal cap_hour  : unsigned(7 downto 0) := (others => '0'); 
  signal cap_min   : unsigned(7 downto 0) := (others => '0'); 
  signal cap_sec   : unsigned(7 downto 0) := (others => '0'); 
  signal cap_mode  : std_logic_vector(1 downto 0) := "00";
  signal lcd_update_req : std_logic := '0';
  -- New signals: store split temperature digits (0-9)
  signal val_t_ten  : integer range 0 to 9 := 0;
  signal val_t_unit : integer range 0 to 9 := 0;
  signal val_t_frac : integer range 0 to 9 := 0;
  -- latch input temperature to prevent changes during calculation
  signal cap_temp   : integer := 0;

begin 
  --------------------------------------------------------------------------- 
  -- LCD RAM + controller instances 
  --------------------------------------------------------------------------- 
  inst_ram: lcd_text_ram 
    port map( 
      clk   => clk, 
      waddr => ram_waddr, 
      wdata => ram_wdata, 
      raddr => ram_raddr, 
      rdata => ram_rdata 
    ); 

  inst_controller: lcd_controller 
    generic map( SIMULATION_MODE => false ) 
    port map( 
      clk   => clk, 
      rst_n => lcd_rst_n, 
      lcd_rs => lcd_rs, 
      lcd_rw => lcd_rw, 
      lcd_e  => lcd_e, 
      lcd_data => lcd_data, 
      refresh_led => refresh_led, 
      ram_raddr => ram_raddr, 
      ram_rdata => ram_rdata 
    ); 

  --------------------------------------------------------------------------- 
  -- LCD update request
  --------------------------------------------------------------------------- 

  process(clk) 
  begin 
    if rising_edge(clk) then 
      if srst='1' then 
        lcd_update_req <= '0'; 

      else 
        lcd_update_req <= '0'; 
        if (read_done_p = '1') or (mode_change = '1') then 
          lcd_update_req <= '1'; 
        end if; 
      end if; 
    end if; 
  end process; 

  --------------------------------------------------------------------------- 
  -- LCD writer 
  -- mode "00": "DATE 20YY-MM-DD " 
  -- mode "01": "TIME HH:MM:SS  " 
  -- mode "10": "TEMP XX.XC     " 
  --------------------------------------------------------------------------- 

  process(clk)
    variable yi, moi, dai, hhi, mii, ssi : integer;
    variable d : integer;
  begin
    if rising_edge(clk) then
      if srst = '1' then
        lw_state <= LW_IDLE;
        lw_idx   <= 0;
        
        -- Reset capture signals
        cap_year  <= (others => '0');
        cap_month <= (others => '0');
        cap_date  <= (others => '0');
        cap_hour  <= (others => '0');
        cap_min   <= (others => '0');
        cap_sec   <= (others => '0');
        cap_mode  <= "00";
        cap_temp  <= 0;
        
        -- Reset calc registers
        val_t_ten  <= 0;
        val_t_unit <= 0;
        val_t_frac <= 0;
        t_run      <= 0;

        ram_waddr <= 31;
        ram_wdata <= x"20";

      else
        -- Default: park write
        if lw_state = LW_IDLE then
          ram_waddr <= 31;
          ram_wdata <= x"20";
        end if;

        -- State Machine
        case lw_state is
        
          when LW_IDLE =>
            if lcd_update_req = '1' then
              cap_year  <= rd_year;
              cap_month <= rd_month;
              cap_date  <= rd_date;
              cap_hour  <= rd_hour;
              cap_min   <= rd_min;
              cap_sec   <= rd_sec;
              cap_mode  <= disp_mode;
              cap_temp  <= temp_x10;
              
                -- Enter initialization state before starting calculations
                  lw_state <= LW_CALC_INIT;
            end if;

            -- [Step 1] Initialize calculator
            when LW_CALC_INIT =>
             -- Put absolute value into t_run
             if cap_temp < 0 then
               t_run <= 0; 
             else
               t_run <= cap_temp;
             end if;
             -- Clear result counters
             val_t_ten  <= 0; -- This represents the temperature 'tens' digit 
             val_t_unit <= 0; -- Temperature 'units' digit 
             val_t_frac <= 0; -- Temperature fractional digit

             lw_state <= LW_CALC_100;

            -- [Step 2] Calculate tens (value 100 because fixed-point x10)
            -- Subtract 100 repeatedly until remainder < 100
          when LW_CALC_100 =>
             if t_run >= 100 then
                 t_run      <= t_run - 100;   
                 val_t_ten  <= val_t_ten + 1;
                 lw_state   <= LW_CALC_100; 
             else
                 lw_state   <= LW_CALC_10;
             end if;

            -- [Step 3] Calculate units (value 10)
            -- Subtract 10 repeatedly
          when LW_CALC_10 =>
             if t_run >= 10 then
                 t_run      <= t_run - 10;
                 val_t_unit <= val_t_unit + 1;
                 lw_state   <= LW_CALC_10;
             else
               -- Remaining t_run is the fractional digit (less than 10)
                 val_t_frac <= t_run;
                 lw_state   <= LW_WRITE_0_15;
                 lw_idx     <= 0;
             end if;

          -- [Step 4] Start writing to display
          when LW_WRITE_0_15 =>
            ram_waddr <= lw_idx;
            
            -- Convert time variables
            yi  := to_integer(cap_year);
            moi := to_integer(cap_month);
            dai := to_integer(cap_date);
            hhi := to_integer(cap_hour);
            mii := to_integer(cap_min);
            ssi := to_integer(cap_sec);

            if cap_mode = "00" then
              -- DATE mode 
              case lw_idx is
                 when 0 => ram_wdata <= x"44"; 
                 when 1 => ram_wdata <= x"41"; 
                 when 2 => ram_wdata <= x"54"; 
                 when 3 => ram_wdata <= x"45"; 
                 when 4 => ram_wdata <= x"20"; 
                 when 5 => ram_wdata <= x"32"; 
                 when 6 => ram_wdata <= x"30"; 
                 when 7 => 
                   d := (yi / 10) mod 10;
                   if d=0 then ram_wdata<=x"30"; elsif d=1 then ram_wdata<=x"31"; elsif d=2 then ram_wdata<=x"32"; elsif d=3 then ram_wdata<=x"33"; elsif d=4 then ram_wdata<=x"34"; elsif d=5 then ram_wdata<=x"35"; elsif d=6 then ram_wdata<=x"36"; elsif d=7 then ram_wdata<=x"37"; elsif d=8 then ram_wdata<=x"38"; else ram_wdata<=x"39"; end if;
                 when 8 => 
                   d := yi mod 10;
                   if d=0 then ram_wdata<=x"30"; elsif d=1 then ram_wdata<=x"31"; elsif d=2 then ram_wdata<=x"32"; elsif d=3 then ram_wdata<=x"33"; elsif d=4 then ram_wdata<=x"34"; elsif d=5 then ram_wdata<=x"35"; elsif d=6 then ram_wdata<=x"36"; elsif d=7 then ram_wdata<=x"37"; elsif d=8 then ram_wdata<=x"38"; else ram_wdata<=x"39"; end if;
                 when 9 => ram_wdata <= x"2D";
                 when 10 => 
                   d := (moi / 10) mod 10;
                   if d=0 then ram_wdata<=x"30"; elsif d=1 then ram_wdata<=x"31"; elsif d=2 then ram_wdata<=x"32"; elsif d=3 then ram_wdata<=x"33"; elsif d=4 then ram_wdata<=x"34"; elsif d=5 then ram_wdata<=x"35"; elsif d=6 then ram_wdata<=x"36"; elsif d=7 then ram_wdata<=x"37"; elsif d=8 then ram_wdata<=x"38"; else ram_wdata<=x"39"; end if;
                 when 11 => 
                   d := moi mod 10;
                   if d=0 then ram_wdata<=x"30"; elsif d=1 then ram_wdata<=x"31"; elsif d=2 then ram_wdata<=x"32"; elsif d=3 then ram_wdata<=x"33"; elsif d=4 then ram_wdata<=x"34"; elsif d=5 then ram_wdata<=x"35"; elsif d=6 then ram_wdata<=x"36"; elsif d=7 then ram_wdata<=x"37"; elsif d=8 then ram_wdata<=x"38"; else ram_wdata<=x"39"; end if;
                 when 12 => ram_wdata <= x"2D";
                 when 13 => 
                   d := (dai / 10) mod 10;
                   if d=0 then ram_wdata<=x"30"; elsif d=1 then ram_wdata<=x"31"; elsif d=2 then ram_wdata<=x"32"; elsif d=3 then ram_wdata<=x"33"; elsif d=4 then ram_wdata<=x"34"; elsif d=5 then ram_wdata<=x"35"; elsif d=6 then ram_wdata<=x"36"; elsif d=7 then ram_wdata<=x"37"; elsif d=8 then ram_wdata<=x"38"; else ram_wdata<=x"39"; end if;
                 when 14 => 
                   d := dai mod 10;
                   if d=0 then ram_wdata<=x"30"; elsif d=1 then ram_wdata<=x"31"; elsif d=2 then ram_wdata<=x"32"; elsif d=3 then ram_wdata<=x"33"; elsif d=4 then ram_wdata<=x"34"; elsif d=5 then ram_wdata<=x"35"; elsif d=6 then ram_wdata<=x"36"; elsif d=7 then ram_wdata<=x"37"; elsif d=8 then ram_wdata<=x"38"; else ram_wdata<=x"39"; end if;
                 when others => ram_wdata <= x"20";
              end case;

            elsif cap_mode = "01" then
              -- TIME mode
              case lw_idx is
                when 0 => ram_wdata <= x"54"; 
                when 1 => ram_wdata <= x"49"; 
                when 2 => ram_wdata <= x"4D"; 
                when 3 => ram_wdata <= x"45"; 
                when 4 => ram_wdata <= x"20"; 
                when 5 => 
                  d := (hhi / 10) mod 10;
                  if d=0 then ram_wdata<=x"30"; elsif d=1 then ram_wdata<=x"31"; elsif d=2 then ram_wdata<=x"32"; elsif d=3 then ram_wdata<=x"33"; elsif d=4 then ram_wdata<=x"34"; elsif d=5 then ram_wdata<=x"35"; elsif d=6 then ram_wdata<=x"36"; elsif d=7 then ram_wdata<=x"37"; elsif d=8 then ram_wdata<=x"38"; else ram_wdata<=x"39"; end if;
                when 6 => 
                  d := hhi mod 10;
                  if d=0 then ram_wdata<=x"30"; elsif d=1 then ram_wdata<=x"31"; elsif d=2 then ram_wdata<=x"32"; elsif d=3 then ram_wdata<=x"33"; elsif d=4 then ram_wdata<=x"34"; elsif d=5 then ram_wdata<=x"35"; elsif d=6 then ram_wdata<=x"36"; elsif d=7 then ram_wdata<=x"37"; elsif d=8 then ram_wdata<=x"38"; else ram_wdata<=x"39"; end if;
                when 7 => ram_wdata <= x"3A";
                when 8 => 
                  d := (mii / 10) mod 10;
                  if d=0 then ram_wdata<=x"30"; elsif d=1 then ram_wdata<=x"31"; elsif d=2 then ram_wdata<=x"32"; elsif d=3 then ram_wdata<=x"33"; elsif d=4 then ram_wdata<=x"34"; elsif d=5 then ram_wdata<=x"35"; elsif d=6 then ram_wdata<=x"36"; elsif d=7 then ram_wdata<=x"37"; elsif d=8 then ram_wdata<=x"38"; else ram_wdata<=x"39"; end if;
                when 9 => 
                  d := mii mod 10;
                  if d=0 then ram_wdata<=x"30"; elsif d=1 then ram_wdata<=x"31"; elsif d=2 then ram_wdata<=x"32"; elsif d=3 then ram_wdata<=x"33"; elsif d=4 then ram_wdata<=x"34"; elsif d=5 then ram_wdata<=x"35"; elsif d=6 then ram_wdata<=x"36"; elsif d=7 then ram_wdata<=x"37"; elsif d=8 then ram_wdata<=x"38"; else ram_wdata<=x"39"; end if;
                when 10 => ram_wdata <= x"3A";
                when 11 => 
                  d := (ssi / 10) mod 10;
                  if d=0 then ram_wdata<=x"30"; elsif d=1 then ram_wdata<=x"31"; elsif d=2 then ram_wdata<=x"32"; elsif d=3 then ram_wdata<=x"33"; elsif d=4 then ram_wdata<=x"34"; elsif d=5 then ram_wdata<=x"35"; elsif d=6 then ram_wdata<=x"36"; elsif d=7 then ram_wdata<=x"37"; elsif d=8 then ram_wdata<=x"38"; else ram_wdata<=x"39"; end if;
                when 12 => 
                  d := ssi mod 10;
                  if d=0 then ram_wdata<=x"30"; elsif d=1 then ram_wdata<=x"31"; elsif d=2 then ram_wdata<=x"32"; elsif d=3 then ram_wdata<=x"33"; elsif d=4 then ram_wdata<=x"34"; elsif d=5 then ram_wdata<=x"35"; elsif d=6 then ram_wdata<=x"36"; elsif d=7 then ram_wdata<=x"37"; elsif d=8 then ram_wdata<=x"38"; else ram_wdata<=x"39"; end if;
                when others => ram_wdata <= x"20";
              end case;

            else
              -- TEMP mode
              case lw_idx is
                when 0  => ram_wdata <= x"54"; -- T
                when 1  => ram_wdata <= x"45"; -- E
                when 2  => ram_wdata <= x"4D"; -- M
                when 3  => ram_wdata <= x"50"; -- P
                when 4  => ram_wdata <= x"20"; 

                when 5  => -- Tens
                  d := val_t_ten; -- Tens digit
                  if d=0 then ram_wdata<=x"30"; elsif d=1 then ram_wdata<=x"31"; elsif d=2 then ram_wdata<=x"32";
                  elsif d=3 then ram_wdata<=x"33"; elsif d=4 then ram_wdata<=x"34"; elsif d=5 then ram_wdata<=x"35";
                  elsif d=6 then ram_wdata<=x"36"; elsif d=7 then ram_wdata<=x"37"; elsif d=8 then ram_wdata<=x"38"; else ram_wdata<=x"39"; end if;

                when 6  => -- Ons
                  d := val_t_unit; -- Units digit
                  if d=0 then ram_wdata<=x"30"; elsif d=1 then ram_wdata<=x"31"; elsif d=2 then ram_wdata<=x"32";
                  elsif d=3 then ram_wdata<=x"33"; elsif d=4 then ram_wdata<=x"34"; elsif d=5 then ram_wdata<=x"35";
                  elsif d=6 then ram_wdata<=x"36"; elsif d=7 then ram_wdata<=x"37"; elsif d=8 then ram_wdata<=x"38"; else ram_wdata<=x"39"; end if;

                when 7  => ram_wdata <= x"2E"; -- '.'

                when 8  => --points
                  d := val_t_frac; -- Fractional digit
                  if d=0 then ram_wdata<=x"30"; elsif d=1 then ram_wdata<=x"31"; elsif d=2 then ram_wdata<=x"32";
                  elsif d=3 then ram_wdata<=x"33"; elsif d=4 then ram_wdata<=x"34"; elsif d=5 then ram_wdata<=x"35";
                  elsif d=6 then ram_wdata<=x"36"; elsif d=7 then ram_wdata<=x"37"; elsif d=8 then ram_wdata<=x"38"; else ram_wdata<=x"39"; end if;

                when 9  => ram_wdata <= x"43"; -- 'C'
                when others => ram_wdata <= x"20";
              end case;
            end if;

            if lw_idx = 15 then
              lw_state <= LW_FILL_16_31;
              lw_idx   <= 16;
            else
              lw_idx <= lw_idx + 1;
            end if;

          when LW_FILL_16_31 =>
             ram_waddr <= lw_idx;
             ram_wdata <= x"20";
             if lw_idx = 31 then
               lw_state <= LW_IDLE;
               lw_idx   <= 0;
             else
               lw_idx <= lw_idx + 1;
             end if;

          when others =>
            lw_state <= LW_IDLE;
        end case;
      end if;
    end if;
  end process;
  
end architecture; 