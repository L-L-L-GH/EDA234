-- =============================================================
-- FIXED DS18S20 1-Wire Master
-- =============================================================
----------------------------------------------------------------------------
-- Author:  Ruxuan Wen
----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ds18s20_onewire is
    port(
        clk      : in  std_logic;        
        rst_n    : in  std_logic;
        dq_in    : in  std_logic;
        dq_out   : out std_logic;
        dq_oe    : out std_logic;
        temp_raw : out std_logic_vector(15 downto 0);
        done     : out std_logic
    );
end entity;

architecture rtl of ds18s20_onewire is

    constant CLK_FREQ : integer := 100_000_000;
    constant T_US     : integer := CLK_FREQ / 1_000_000; 
    constant T_RESET  : integer := 480 * T_US; 
    constant T_WAIT   : integer := 480 * T_US; 
    
    constant T_SLOT   : integer := 70 * T_US;  -- Total Slot duration 
    constant T_LOW0   : integer := 60 * T_US;  -- Drive Low for '0'
    constant T_LOW1   : integer := 6  * T_US;  -- Drive Low for '1' or Read Start
    constant T_SAMPLE : integer := 15 * T_US;  -- Sample time for Read
    
    constant T_CONV   : integer := 750_000 * T_US; 

    type state_t is (
        IDLE,
        RESET_1, WAIT_PRESENCE_1,
        WRITE_SKIP_ROM_1,
        WRITE_CONVERT_T,
        WAIT_CONVERSION,
        RESET_2, WAIT_PRESENCE_2,
        WRITE_SKIP_ROM_2,
        WRITE_READ_SCRATCHPAD,
        READ_TEMP_LSB,
        READ_TEMP_MSB,
        FINISH
    );
    signal state    : state_t := IDLE;
    signal cnt      : integer := 0;
    signal bit_cnt  : integer range 0 to 7 := 0;
    signal shiftreg : std_logic_vector(7 downto 0) := (others => '0');

    signal temp_lsb : std_logic_vector(7 downto 0) := (others => '0');
    signal temp_msb : std_logic_vector(7 downto 0) := (others => '0');

begin

    dq_out <= '0'; -- Always drive 0 when enabled (Open Drain simulation)

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                state   <= IDLE;
                dq_oe   <= '0';
                cnt     <= 0;
                bit_cnt <= 0;
                done    <= '0';
            else
                case state is

                    when IDLE =>
                        done  <= '0';
                        cnt   <= 0;
                        state <= RESET_1;


                    when RESET_1 =>
                        dq_oe <= '1'; -- Pull Low
                        if cnt = T_RESET then
                            dq_oe <= '0'; -- Release
                            cnt   <= 0;
                            state <= WAIT_PRESENCE_1;
                        else
                            cnt <= cnt + 1;
                        end if;


                    when WAIT_PRESENCE_1 =>
                        if cnt = T_WAIT then
                            cnt      <= 0;
                            bit_cnt  <= 0;
                            shiftreg <= x"CC"; -- Skip ROM
                            state    <= WRITE_SKIP_ROM_1;
                        else
                            cnt <= cnt + 1;
                        end if;

                   
                    when WRITE_SKIP_ROM_1 =>
                       
                        if shiftreg(bit_cnt) = '1' then
                            if cnt < T_LOW1 then dq_oe <= '1'; else dq_oe <= '0'; end if;
                        else 
                            if cnt < T_LOW0 then dq_oe <= '1'; else dq_oe <= '0'; end if;
                        end if;

                        if cnt = T_SLOT then
                            cnt <= 0;
                            if bit_cnt = 7 then
                                bit_cnt  <= 0;
                                shiftreg <= x"44"; -- Convert T
                                state    <= WRITE_CONVERT_T;
                            else
                                shiftreg <= shiftreg; -- keep val
                                bit_cnt <= bit_cnt + 1;
                            end if;
                        else
                            cnt <= cnt + 1;
                        end if;

                    
                    when WRITE_CONVERT_T =>
                        if shiftreg(bit_cnt) = '1' then
                            if cnt < T_LOW1 then dq_oe <= '1'; else dq_oe <= '0'; end if;
                        else
                            if cnt < T_LOW0 then dq_oe <= '1'; else dq_oe <= '0'; end if;
                        end if;

                        if cnt = T_SLOT then
                            cnt <= 0;
                            if bit_cnt = 7 then
                                bit_cnt <= 0;
                                state   <= WAIT_CONVERSION;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;
                        else
                            cnt <= cnt + 1;
                        end if;

                    
                    when WAIT_CONVERSION =>
                        if cnt = T_CONV then
                            cnt   <= 0;
                            state <= RESET_2;
                        else
                            cnt <= cnt + 1;
                        end if;

                   
                    when RESET_2 =>
                        dq_oe <= '1';
                        if cnt = T_RESET then
                            dq_oe <= '0';
                            cnt   <= 0;
                            state <= WAIT_PRESENCE_2;
                        else
                            cnt <= cnt + 1;
                        end if;

                    when WAIT_PRESENCE_2 =>
                        if cnt = T_WAIT then
                            cnt   <= 0;
                            bit_cnt  <= 0;
                            shiftreg <= x"CC"; -- Skip ROM
                            state <= WRITE_SKIP_ROM_2;
                        else
                            cnt <= cnt + 1;
                        end if;

                   
                    when WRITE_SKIP_ROM_2 =>
                        if shiftreg(bit_cnt) = '1' then
                            if cnt < T_LOW1 then dq_oe <= '1'; else dq_oe <= '0'; end if;
                        else
                            if cnt < T_LOW0 then dq_oe <= '1'; else dq_oe <= '0'; end if;
                        end if;

                        if cnt = T_SLOT then
                            cnt <= 0;
                            if bit_cnt = 7 then
                                bit_cnt  <= 0;
                                shiftreg <= x"BE"; -- Read Scratchpad
                                state    <= WRITE_READ_SCRATCHPAD;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;
                        else
                            cnt <= cnt + 1;
                        end if;

                    
                    when WRITE_READ_SCRATCHPAD =>
                        if shiftreg(bit_cnt) = '1' then
                            if cnt < T_LOW1 then dq_oe <= '1'; else dq_oe <= '0'; end if;
                        else
                            if cnt < T_LOW0 then dq_oe <= '1'; else dq_oe <= '0'; end if;
                        end if;

                        if cnt = T_SLOT then
                            cnt <= 0;
                            if bit_cnt = 7 then
                                bit_cnt <= 0;
                                state   <= READ_TEMP_LSB;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;
                        else
                            cnt <= cnt + 1;
                        end if;

                    
                    when READ_TEMP_LSB =>
                        -- Initiate Read Slot: Drive low briefly then release
                        if cnt < T_LOW1 then 
                            dq_oe <= '1'; 
                        else 
                            dq_oe <= '0'; 
                        end if;

                        
                        if cnt = T_SAMPLE then
                            shiftreg(bit_cnt) <= dq_in;
                        end if;

                        if cnt = T_SLOT then
                            cnt <= 0;
                            if bit_cnt = 7 then
                                temp_lsb <= shiftreg;
                                bit_cnt  <= 0;
                                state    <= READ_TEMP_MSB;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;
                        else
                            cnt <= cnt + 1;
                        end if;

                    
                    when READ_TEMP_MSB =>
                        if cnt < T_LOW1 then 
                            dq_oe <= '1'; 
                        else 
                            dq_oe <= '0'; 
                        end if;

                        if cnt = T_SAMPLE then
                            shiftreg(bit_cnt) <= dq_in;
                        end if;

                        if cnt = T_SLOT then
                            cnt <= 0;
                            if bit_cnt = 7 then
                                temp_msb <= shiftreg;
                                bit_cnt <= 0; 
                                state    <= FINISH;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;
                        else
                            cnt <= cnt + 1;
                        end if;

                    when FINISH =>
                        temp_raw <= temp_msb & temp_lsb;
                        done     <= '1';
                        state    <= IDLE; 

                    when others =>
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;
end rtl;