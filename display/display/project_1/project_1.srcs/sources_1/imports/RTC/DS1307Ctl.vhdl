----------------------------------------------------------------------------
-- Author:  Li Ling
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.TWIUtils.all; 

entity DS1307Ctl is
  generic (
    CLOCKFREQ_MHZ : natural := 100  
  );
  port (
    clk   : in  std_logic;
    srst  : in  std_logic; 

    -- Command interface
    op_start : in  std_logic;                    -- pulse high to start
    op_mode  : in  std_logic_vector(1 downto 0); -- "00" read time, "01" write time, "10" write ctrl(0x07)

    busy  : out std_logic;
    done  : out std_logic; 
    error : out std_logic;
    errtype_o : out error_type;

    -- Time inputs (binary)
    set_sec   : in unsigned(7 downto 0); -- 0..59
    set_min   : in unsigned(7 downto 0); -- 0..59
    set_hour  : in unsigned(7 downto 0); -- 0..23 (24-hour)
    set_dow   : in unsigned(7 downto 0); -- 1..7
    set_date  : in unsigned(7 downto 0); -- 1..31
    set_month : in unsigned(7 downto 0); -- 1..12
    set_year  : in unsigned(7 downto 0); -- 0..99

    -- Control register inputs (0x07)
    cfg_out    : in std_logic;                  
    cfg_sqw_en : in std_logic;                    
    cfg_rs     : in std_logic_vector(1 downto 0);  

    -- Read outputs (binary)
    rd_sec   : out unsigned(7 downto 0);
    rd_min   : out unsigned(7 downto 0);
    rd_hour  : out unsigned(7 downto 0);
    rd_dow   : out unsigned(7 downto 0);
    rd_date  : out unsigned(7 downto 0);
    rd_month : out unsigned(7 downto 0);
    rd_year  : out unsigned(7 downto 0);

    -- I2C bus
    sda : inout std_logic;
    scl : inout std_logic
  );
end entity;

architecture rtl of DS1307Ctl is

  -- DS1307 address (8-bit including R/W)
  constant DS1307_ADDR_W : std_logic_vector(7 downto 0) := x"D0";
  constant DS1307_ADDR_R : std_logic_vector(7 downto 0) := x"D1";

  constant REG_TIME_BASE : std_logic_vector(7 downto 0) := x"00";
  constant REG_CTRL      : std_logic_vector(7 downto 0) := x"07";

  -- TWICtl interface
  signal twi_msg   : std_logic := '0';
  signal twi_stb   : std_logic := '0';
  signal twi_a     : std_logic_vector(7 downto 0) := (others => '0');
  signal twi_di    : std_logic_vector(7 downto 0) := (others => '0');
  signal twi_do    : std_logic_vector(7 downto 0);
  signal twi_done  : std_logic;
  signal twi_err   : std_logic;
  signal twi_etype : error_type;

  -- ========= STB stretching =========
  -- For 100MHz + 100kHz I2C:
  --  - SCL period ~10us => 1000 cycles
  --  - half period ~5us => 500 cycles
  constant STB_STRETCH : natural := 500;

  signal stb_cnt   : natural range 0 to STB_STRETCH := 0;
  signal msg_latch : std_logic := '0';

  -- FSM requests a fire pulse
  signal stb_fire  : std_logic := '0';
  signal msg_req   : std_logic := '0';

  -- Bus free qualify 
  constant BUSFREE_CYCLES : natural := 500;
  signal bf_cnt    : natural range 0 to BUSFREE_CYCLES := 0;
  signal bus_free  : std_logic := '0';

  -- DS1307 FSM
  type state_t is (
    S_IDLE,
    S_WAIT_BUS,

    -- pointer write
    S_PTR_FIRE,
    S_PTR_WAIT,

    -- read flow
    S_R_RESTART_FIRE,
    S_R_RESTART_WAIT,
    S_R_CONT_FIRE,
    S_R_CONT_WAIT,

    -- write time flow
    S_W_DATA_FIRE,
    S_W_DATA_WAIT,

    -- write control flow
    S_C_DATA_FIRE,
    S_C_DATA_WAIT,

    S_DONE,
    S_ERR
  );

  signal st : state_t := S_IDLE;

  signal op_mode_r : std_logic_vector(1 downto 0) := (others => '0');
  signal idx       : integer range 0 to 6 := 0;

  -- Latched inputs
  signal l_sec, l_min, l_hour, l_dow, l_date, l_month, l_year : unsigned(7 downto 0) := (others => '0');
  signal l_out, l_sqw_en : std_logic := '0';
  signal l_rs : std_logic_vector(1 downto 0) := (others => '0');

  -- Read buffer
  type byte_arr is array (0 to 6) of std_logic_vector(7 downto 0);
  signal rbuf : byte_arr := (others => (others => '0'));

begin

  -- TWICtl instance
  u_twi: entity work.TWICtl
    generic map (
      CLOCKFREQ => CLOCKFREQ_MHZ,
      ATTEMPT_SLAVE_UNBLOCK => false
    )
    port map (
      MSG_I => twi_msg,
      STB_I => twi_stb,
      A_I   => twi_a,
      D_I   => twi_di,
      D_O   => twi_do,
      DONE_O => twi_done,
      ERR_O  => twi_err,
      ERRTYPE_O => twi_etype,
      CLK  => clk,
      SRST => srst,
      SDA  => sda,
      SCL  => scl
    );

  --------------------------------------------------------------------------
  -- Bus-free detector
  --------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if srst = '1' then
        bf_cnt   <= 0;
        bus_free <= '0';
      else
        if (sda = '1' and scl = '1') then
          if bf_cnt < BUSFREE_CYCLES then
            bf_cnt <= bf_cnt + 1;
          end if;
        else
          bf_cnt <= 0;
        end if;

        if bf_cnt >= BUSFREE_CYCLES then
          bus_free <= '1';
        else
          bus_free <= '0';
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------------
  -- STB stretching process 
  --------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if srst = '1' then
        stb_cnt   <= 0;
        msg_latch <= '0';
        twi_stb   <= '0';
        twi_msg   <= '0';
      else
        -- Load on fire 
        if (stb_fire = '1') and (stb_cnt = 0) then
          stb_cnt   <= STB_STRETCH;
          msg_latch <= msg_req;
        elsif stb_cnt > 0 then
          stb_cnt <= stb_cnt - 1;
        end if;

        -- Drive TWICtl inputs while stretched
        if stb_cnt > 0 then
          twi_stb <= '1';
          twi_msg <= msg_latch;
        else
          twi_stb <= '0';
          twi_msg <= '0';
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------------
  -- Main FSM
  --------------------------------------------------------------------------
  process(clk)
    -- local variables for BCD encoding/decoding
    variable v_int  : integer;
    variable tens   : integer;
    variable ones   : integer;
    variable b      : std_logic_vector(7 downto 0);

    -- decode helpers
    variable dtens  : integer;
    variable dones  : integer;
    variable dv     : integer;

    -- selected binary value per idx for write-time
    variable sel_u  : unsigned(7 downto 0);
  begin
    if rising_edge(clk) then
      if srst = '1' then
        st <= S_IDLE;
        op_mode_r <= (others => '0');
        idx <= 0;

        busy <= '0';
        done <= '0';
        error <= '0';
        errtype_o <= errNAck;

        rd_sec   <= (others => '0');
        rd_min   <= (others => '0');
        rd_hour  <= (others => '0');
        rd_dow   <= (others => '0');
        rd_date  <= (others => '0');
        rd_month <= (others => '0');
        rd_year  <= (others => '0');

        twi_a  <= (others => '0');
        twi_di <= (others => '0');

        stb_fire <= '0';
        msg_req  <= '0';

      else
        done <= '0';     
        stb_fire <= '0';  
        msg_req  <= '0';  

        case st is
          when S_IDLE =>
            busy <= '0';
            error <= '0';

            if op_start = '1' then
              op_mode_r <= op_mode;

              l_sec   <= set_sec;
              l_min   <= set_min;
              l_hour  <= set_hour;
              l_dow   <= set_dow;
              l_date  <= set_date;
              l_month <= set_month;
              l_year  <= set_year;

              l_out    <= cfg_out;
              l_sqw_en <= cfg_sqw_en;
              l_rs     <= cfg_rs;

              idx <= 0;
              busy <= '1';
              st <= S_WAIT_BUS;
            end if;

          when S_WAIT_BUS =>
            if (bus_free = '1') and (twi_stb = '0') then
              st <= S_PTR_FIRE;
            end if;

          -- ---- write pointer ----
          when S_PTR_FIRE =>
            twi_a <= DS1307_ADDR_W;
            if op_mode_r = "10" then
              twi_di <= REG_CTRL;
            else
              twi_di <= REG_TIME_BASE;
            end if;

            msg_req  <= '0';
            stb_fire <= '1';
            st <= S_PTR_WAIT;

          when S_PTR_WAIT =>
            if twi_done = '1' then
              if twi_err = '1' then
                error <= '1';
                errtype_o <= twi_etype;
                st <= S_ERR;
              else
                if op_mode_r = "00" then
                  st <= S_R_RESTART_FIRE;  -- repeated-start read
                elsif op_mode_r = "01" then
                  idx <= 0;
                  st <= S_W_DATA_FIRE;
                else
                  st <= S_C_DATA_FIRE;
                end if;
              end if;
            end if;

          -- ---- READ TIME ----
          when S_R_RESTART_FIRE =>
            twi_a <= DS1307_ADDR_R;
            twi_di <= (others => '0'); -- ignored
            msg_req  <= '1';           -- repeated start
            stb_fire <= '1';
            st <= S_R_RESTART_WAIT;

          when S_R_RESTART_WAIT =>
            if twi_done = '1' then
              if twi_err = '1' then
                error <= '1';
                errtype_o <= twi_etype;
                st <= S_ERR;
              else
                rbuf(0) <= twi_do;
                idx <= 0;
                st <= S_R_CONT_FIRE;
              end if;
            end if;

          when S_R_CONT_FIRE =>
            twi_a <= DS1307_ADDR_R;
            twi_di <= (others => '0');
            msg_req  <= '0';
            stb_fire <= '1';
            st <= S_R_CONT_WAIT;

          when S_R_CONT_WAIT =>
            if twi_done = '1' then
              if twi_err = '1' then
                error <= '1';
                errtype_o <= twi_etype;
                st <= S_ERR;
              else
                rbuf(idx+1) <= twi_do;
                idx <= idx + 1;

                if (idx + 1) < 6 then
                  st <= S_R_CONT_FIRE;
                else
                  st <= S_DONE;
                end if;
              end if;
            end if;

          -- ---- WRITE TIME (7 bytes) ----
          when S_W_DATA_FIRE =>
            -- choose which value to write based on idx
            -- idx 0..6 => sec, min, hour, dow, date, month, year
            if idx = 0 then
              sel_u := l_sec;
              -- BCD encode
              v_int := to_integer(sel_u);
              if v_int < 0 then v_int := 0; end if;
              if v_int > 59 then v_int := 59; end if;
              
              
    case v_int is 

    when  0 => b := x"00"; when  1 => b := x"01"; when  2 => b := x"02"; when  3 => b := x"03"; when  4 => b := x"04"; 

    when  5 => b := x"05"; when  6 => b := x"06"; when  7 => b := x"07"; when  8 => b := x"08"; when  9 => b := x"09"; 

    when 10 => b := x"10"; when 11 => b := x"11"; when 12 => b := x"12"; when 13 => b := x"13"; when 14 => b := x"14"; 

    when 15 => b := x"15"; when 16 => b := x"16"; when 17 => b := x"17"; when 18 => b := x"18"; when 19 => b := x"19"; 

    when 20 => b := x"20"; when 21 => b := x"21"; when 22 => b := x"22"; when 23 => b := x"23"; when 24 => b := x"24"; 

    when 25 => b := x"25"; when 26 => b := x"26"; when 27 => b := x"27"; when 28 => b := x"28"; when 29 => b := x"29"; 

    when 30 => b := x"30"; when 31 => b := x"31"; when 32 => b := x"32"; when 33 => b := x"33"; when 34 => b := x"34"; 

    when 35 => b := x"35"; when 36 => b := x"36"; when 37 => b := x"37"; when 38 => b := x"38"; when 39 => b := x"39"; 

    when 40 => b := x"40"; when 41 => b := x"41"; when 42 => b := x"42"; when 43 => b := x"43"; when 44 => b := x"44"; 

    when 45 => b := x"45"; when 46 => b := x"46"; when 47 => b := x"47"; when 48 => b := x"48"; when 49 => b := x"49"; 

    when 50 => b := x"50"; when 51 => b := x"51"; when 52 => b := x"52"; when 53 => b := x"53"; when 54 => b := x"54"; 

    when 55 => b := x"55"; when 56 => b := x"56"; when 57 => b := x"57"; when 58 => b := x"58"; when 59 => b := x"59"; 

    when others => b := x"59"; 

  end case; 
              
          
              b(7) := '0'; -- CH=0


elsif idx = 1 then 

  -- minute: ROM lookup (0..59) -> BCD 

  v_int := to_integer(l_min); 

  if v_int < 0 then v_int := 0; end if; 

  if v_int > 59 then v_int := 59; end if; 

  

  case v_int is 

    when  0 => b := x"00"; when  1 => b := x"01"; when  2 => b := x"02"; when  3 => b := x"03"; when  4 => b := x"04"; 

    when  5 => b := x"05"; when  6 => b := x"06"; when  7 => b := x"07"; when  8 => b := x"08"; when  9 => b := x"09"; 

    when 10 => b := x"10"; when 11 => b := x"11"; when 12 => b := x"12"; when 13 => b := x"13"; when 14 => b := x"14"; 

    when 15 => b := x"15"; when 16 => b := x"16"; when 17 => b := x"17"; when 18 => b := x"18"; when 19 => b := x"19"; 

    when 20 => b := x"20"; when 21 => b := x"21"; when 22 => b := x"22"; when 23 => b := x"23"; when 24 => b := x"24"; 

    when 25 => b := x"25"; when 26 => b := x"26"; when 27 => b := x"27"; when 28 => b := x"28"; when 29 => b := x"29"; 

    when 30 => b := x"30"; when 31 => b := x"31"; when 32 => b := x"32"; when 33 => b := x"33"; when 34 => b := x"34"; 

    when 35 => b := x"35"; when 36 => b := x"36"; when 37 => b := x"37"; when 38 => b := x"38"; when 39 => b := x"39"; 

    when 40 => b := x"40"; when 41 => b := x"41"; when 42 => b := x"42"; when 43 => b := x"43"; when 44 => b := x"44"; 

    when 45 => b := x"45"; when 46 => b := x"46"; when 47 => b := x"47"; when 48 => b := x"48"; when 49 => b := x"49"; 

    when 50 => b := x"50"; when 51 => b := x"51"; when 52 => b := x"52"; when 53 => b := x"53"; when 54 => b := x"54"; 

    when 55 => b := x"55"; when 56 => b := x"56"; when 57 => b := x"57"; when 58 => b := x"58"; when 59 => b := x"59"; 

    when others => b := x"59"; 

  end case; 


elsif idx = 2 then 

  -- hour: ROM lookup (0..23) -> BCD, force 24-hour mode bits=0 

  v_int := to_integer(l_hour); 

  if v_int < 0 then v_int := 0; end if; 

  if v_int > 23 then v_int := 23; end if; 

  case v_int is 

    when  0 => b := x"00"; when  1 => b := x"01"; when  2 => b := x"02"; when  3 => b := x"03"; when  4 => b := x"04"; 

    when  5 => b := x"05"; when  6 => b := x"06"; when  7 => b := x"07"; when  8 => b := x"08"; when  9 => b := x"09"; 

    when 10 => b := x"10"; when 11 => b := x"11"; when 12 => b := x"12"; when 13 => b := x"13"; when 14 => b := x"14"; 

    when 15 => b := x"15"; when 16 => b := x"16"; when 17 => b := x"17"; when 18 => b := x"18"; when 19 => b := x"19"; 

    when 20 => b := x"20"; when 21 => b := x"21"; when 22 => b := x"22"; when 23 => b := x"23"; 

    when others => b := x"23"; 

  end case;   

  b(6) := '0'; -- 24-hour 

  b(7) := '0'; 
  
            elsif idx = 3 then
              -- DOW not BCD, only use bits2..0
              b := (others => '0');
              b(2 downto 0) := std_logic_vector(l_dow(2 downto 0));
            elsif idx = 4 then
              sel_u := l_date;
              v_int := to_integer(sel_u);
              if v_int < 1 then v_int := 1; end if;
              if v_int > 31 then v_int := 31; end if;
              
  case v_int is 

    when  0 => b := x"00"; when  1 => b := x"01"; when  2 => b := x"02"; when  3 => b := x"03"; when  4 => b := x"04"; 

    when  5 => b := x"05"; when  6 => b := x"06"; when  7 => b := x"07"; when  8 => b := x"08"; when  9 => b := x"09"; 

    when 10 => b := x"10"; when 11 => b := x"11"; when 12 => b := x"12"; when 13 => b := x"13"; when 14 => b := x"14"; 

    when 15 => b := x"15"; when 16 => b := x"16"; when 17 => b := x"17"; when 18 => b := x"18"; when 19 => b := x"19"; 

    when 20 => b := x"20"; when 21 => b := x"21"; when 22 => b := x"22"; when 23 => b := x"23"; when 24 => b := x"24"; 

    when 25 => b := x"25"; when 26 => b := x"26"; when 27 => b := x"27"; when 28 => b := x"28"; when 29 => b := x"29"; 

    when 30 => b := x"30"; when 31 => b := x"31"; 

    when others => b := x"31"; 

  end case;               
              
              

            elsif idx = 5 then
              sel_u := l_month;
              v_int := to_integer(sel_u);
              if v_int < 1 then v_int := 1; end if;
              if v_int > 12 then v_int := 12; end if;
              
                case v_int is 

    when  0 => b := x"00"; when  1 => b := x"01"; when  2 => b := x"02"; when  3 => b := x"03"; when  4 => b := x"04"; 

    when  5 => b := x"05"; when  6 => b := x"06"; when  7 => b := x"07"; when  8 => b := x"08"; when  9 => b := x"09"; 

    when 10 => b := x"10"; when 11 => b := x"11"; when 12 => b := x"12"; 

    when others => b := x"12"; 

  end case;    
              

            else
              sel_u := l_year;
              v_int := to_integer(sel_u);
              if v_int < 0 then v_int := 0; end if;
              if v_int > 99 then v_int := 99; end if;

  case v_int is 

 when  0 => b := x"00"; when  1 => b := x"01"; when  2 => b := x"02"; when  3 => b := x"03"; when  4 => b := x"04"; 

  when  5 => b := x"05"; when  6 => b := x"06"; when  7 => b := x"07"; when  8 => b := x"08"; when  9 => b := x"09"; 

  when 10 => b := x"10"; when 11 => b := x"11"; when 12 => b := x"12"; when 13 => b := x"13"; when 14 => b := x"14"; 

  when 15 => b := x"15"; when 16 => b := x"16"; when 17 => b := x"17"; when 18 => b := x"18"; when 19 => b := x"19"; 

  when 20 => b := x"20"; when 21 => b := x"21"; when 22 => b := x"22"; when 23 => b := x"23"; when 24 => b := x"24"; 

  when 25 => b := x"25"; when 26 => b := x"26"; when 27 => b := x"27"; when 28 => b := x"28"; when 29 => b := x"29"; 

  when 30 => b := x"30"; when 31 => b := x"31"; when 32 => b := x"32"; when 33 => b := x"33"; when 34 => b := x"34"; 

  when 35 => b := x"35"; when 36 => b := x"36"; when 37 => b := x"37"; when 38 => b := x"38"; when 39 => b := x"39"; 

  when 40 => b := x"40"; when 41 => b := x"41"; when 42 => b := x"42"; when 43 => b := x"43"; when 44 => b := x"44"; 

  when 45 => b := x"45"; when 46 => b := x"46"; when 47 => b := x"47"; when 48 => b := x"48"; when 49 => b := x"49"; 

  when 50 => b := x"50"; when 51 => b := x"51"; when 52 => b := x"52"; when 53 => b := x"53"; when 54 => b := x"54"; 

  when 55 => b := x"55"; when 56 => b := x"56"; when 57 => b := x"57"; when 58 => b := x"58"; when 59 => b := x"59"; 

  when 60 => b := x"60"; when 61 => b := x"61"; when 62 => b := x"62"; when 63 => b := x"63"; when 64 => b := x"64"; 

  when 65 => b := x"65"; when 66 => b := x"66"; when 67 => b := x"67"; when 68 => b := x"68"; when 69 => b := x"69"; 

  when 70 => b := x"70"; when 71 => b := x"71"; when 72 => b := x"72"; when 73 => b := x"73"; when 74 => b := x"74"; 

  when 75 => b := x"75"; when 76 => b := x"76"; when 77 => b := x"77"; when 78 => b := x"78"; when 79 => b := x"79"; 

  when 80 => b := x"80"; when 81 => b := x"81"; when 82 => b := x"82"; when 83 => b := x"83"; when 84 => b := x"84"; 

  when 85 => b := x"85"; when 86 => b := x"86"; when 87 => b := x"87"; when 88 => b := x"88"; when 89 => b := x"89"; 

  when 90 => b := x"90"; when 91 => b := x"91"; when 92 => b := x"92"; when 93 => b := x"93"; when 94 => b := x"94"; 

  when 95 => b := x"95"; when 96 => b := x"96"; when 97 => b := x"97"; when 98 => b := x"98"; when 99 => b := x"99"; 

  when others => b := x"99"; 

  end case;    

            end if;

            twi_a  <= DS1307_ADDR_W;
            twi_di <= b;

            msg_req  <= '0';
            stb_fire <= '1';
            st <= S_W_DATA_WAIT;

          when S_W_DATA_WAIT =>
            if twi_done = '1' then
              if twi_err = '1' then
                error <= '1';
                errtype_o <= twi_etype;
                st <= S_ERR;
              else
                if idx < 6 then
                  idx <= idx + 1;
                  st <= S_W_DATA_FIRE;
                else
                  st <= S_DONE;
                end if;
              end if;
            end if;

          -- ---- WRITE CTRL (1 byte) ----
          when S_C_DATA_FIRE =>
            b := (others => '0');
            b(7) := l_out;
            b(4) := l_sqw_en;
            b(1 downto 0) := l_rs;

            twi_a  <= DS1307_ADDR_W;
            twi_di <= b;

            msg_req  <= '0';
            stb_fire <= '1';
            st <= S_C_DATA_WAIT;

          when S_C_DATA_WAIT =>
            if twi_done = '1' then
              if twi_err = '1' then
                error <= '1';
                errtype_o <= twi_etype;
                st <= S_ERR;
              else
                st <= S_DONE;
              end if;
            end if;

          -- ---- DONE: decode read buffer ----
          when S_DONE =>
            if op_mode_r = "00" then
              -- seconds: mask CH bit7
              b := '0' & rbuf(0)(6 downto 0);
              dtens := to_integer(unsigned(b(7 downto 4)));
              dones := to_integer(unsigned(b(3 downto 0)));
              dv := dtens*10 + dones;
              if dv < 0 then dv := 0; end if;
              if dv > 59 then dv := 59; end if;
              rd_sec <= to_unsigned(dv, 8);

              -- minutes
              b := rbuf(1);
              dtens := to_integer(unsigned(b(7 downto 4)));
              dones := to_integer(unsigned(b(3 downto 0)));
              dv := dtens*10 + dones;
              if dv < 0 then dv := 0; end if;
              if dv > 59 then dv := 59; end if;
              rd_min <= to_unsigned(dv, 8);

              -- hours 
              b := "00" & rbuf(2)(5 downto 0);
              dtens := to_integer(unsigned(b(7 downto 4)));
              dones := to_integer(unsigned(b(3 downto 0)));
              dv := dtens*10 + dones;
              if dv < 0 then dv := 0; end if;
              if dv > 23 then dv := 23; end if;
              rd_hour <= to_unsigned(dv, 8);

              -- dow bits2..0
              rd_dow <= (others => '0');
              rd_dow(2 downto 0) <= unsigned(rbuf(3)(2 downto 0));

              -- date
              b := rbuf(4);
              dtens := to_integer(unsigned(b(7 downto 4)));
              dones := to_integer(unsigned(b(3 downto 0)));
              dv := dtens*10 + dones;
              if dv < 1 then dv := 1; end if;
              if dv > 31 then dv := 31; end if;
              rd_date <= to_unsigned(dv, 8);

              -- month
              b := rbuf(5);
              dtens := to_integer(unsigned(b(7 downto 4)));
              dones := to_integer(unsigned(b(3 downto 0)));
              dv := dtens*10 + dones;
              if dv < 1 then dv := 1; end if;
              if dv > 12 then dv := 12; end if;
              rd_month <= to_unsigned(dv, 8);

              -- year
              b := rbuf(6);
              dtens := to_integer(unsigned(b(7 downto 4)));
              dones := to_integer(unsigned(b(3 downto 0)));
              dv := dtens*10 + dones;
              if dv < 0 then dv := 0; end if;
              if dv > 99 then dv := 99; end if;
              rd_year <= to_unsigned(dv, 8);
            end if;

            busy <= '0';
            done <= '1';
            st <= S_IDLE;

          when S_ERR =>
            busy <= '0';
            done <= '1';
            st <= S_IDLE;

          when others =>
            st <= S_IDLE;
        end case;
      end if;
    end if;
  end process;

end architecture;