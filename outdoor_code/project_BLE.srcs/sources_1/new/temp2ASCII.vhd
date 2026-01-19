----------------------------------------------------------------------------------
-- Module Name: Temp_to_ASCII
-- Editor: Ruxuan Wen
-- Description: 
-- 1. Receives 16-bit signed raw temperature from DS18S20.
-- 2. Converts it to ASCII string (e.g., "+25.5 C").
-- 3. Controls the UART interface to send the string.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity Temp_to_ASCII is
    port (
        clk           : in  std_logic;
        rst_n         : in  std_logic;
        i_temp_data   : in  std_logic_vector(15 downto 0); 
        i_temp_done   : in  std_logic;                     
        i_uart_done   : in  std_logic;                    
        o_uart_data   : out std_logic_vector(7 downto 0);  
        o_uart_start  : out std_logic                     
    );
end Temp_to_ASCII;

architecture Behavioral of Temp_to_ASCII is

   
    type state_t is (
        IDLE,           
        PROCESS_TEMP,   
        SEND_SIGN,      -- Send '+' or '-'
        SEND_HUNDREDS,  
        SEND_TENS,      
        SEND_ONES,      
        SEND_DOT,       
        SEND_DECIMAL,   
        SEND_UNIT,      
        SEND_CR,        
        SEND_LF,        
        WAIT_TX_DONE    
    );
    signal current_state : state_t := IDLE;
    signal next_state    : state_t := IDLE; 
    signal r_uart_data   : std_logic_vector(7 downto 0) := (others => '0');
    signal r_uart_start  : std_logic := '0';
    signal int_part        : integer range 0 to 255;
    signal is_negative     : boolean;
    signal fract_part_is_5 : boolean;
    
    signal digit_hundreds  : integer range 0 to 9;
    signal digit_tens      : integer range 0 to 9;
    signal digit_ones      : integer range 0 to 9;

begin
    o_uart_data  <= r_uart_data;
    o_uart_start <= r_uart_start;

    process(clk, rst_n)
        variable temp_signed : signed(15 downto 0);
        variable temp_val_int: integer;
    begin
        if rst_n = '0' then
            current_state <= IDLE;
            r_uart_start  <= '0';
            r_uart_data   <= (others => '0');
        elsif rising_edge(clk) then
            r_uart_start <= '0'; 

            case current_state is
                
                -- Wait for DS18S20 to finish a reading
                when IDLE =>
                    if i_temp_done = '1' then
                        current_state <= PROCESS_TEMP;
                    else
                        current_state <= IDLE;
                    end if;


                when PROCESS_TEMP =>
                    temp_signed := signed(i_temp_data);
                    -- Check Sign
                    if temp_signed(15) = '1' then
                        is_negative <= true;
                        temp_val_int := to_integer(abs(temp_signed));
                    else
                        is_negative <= false;
                        temp_val_int := to_integer(temp_signed);
                    end if;
                     -- Extract Integer part
                    int_part <= temp_val_int / 2; 
                    -- Extract Fraction part (check bit 0)
                    -- If bit 0 is 1, it means .5, otherwise .0
                    if (temp_val_int mod 2) /= 0 then
                        fract_part_is_5 <= true;
                    else
                        fract_part_is_5 <= false;
                    end if;

                    current_state <= SEND_SIGN;

                when SEND_SIGN =>
                    if is_negative then
                        r_uart_data <= x"2D"; -- '-'
                    else
                        r_uart_data <= x"2B"; -- '+'
                    end if;
                    r_uart_start <= '1';
                    
                    digit_hundreds <= int_part / 100;
                    digit_tens     <= (int_part / 10) mod 10;
                    digit_ones     <= int_part mod 10;
                    
                    next_state <= SEND_HUNDREDS;
                    current_state <= WAIT_TX_DONE;

                when SEND_HUNDREDS =>
                    if digit_hundreds > 0 then
                        r_uart_data <= std_logic_vector(to_unsigned(digit_hundreds + 48, 8)); -- ASCII '0' is 48
                        r_uart_start <= '1';
                        next_state <= SEND_TENS;
                        current_state <= WAIT_TX_DONE;
                    else
                        current_state <= SEND_TENS;
                    end if;

                when SEND_TENS =>
                    r_uart_data <= std_logic_vector(to_unsigned(digit_tens + 48, 8));
                    r_uart_start <= '1';
                    next_state <= SEND_ONES;
                    current_state <= WAIT_TX_DONE;

                when SEND_ONES =>
                    r_uart_data <= std_logic_vector(to_unsigned(digit_ones + 48, 8));
                    r_uart_start <= '1';
                    next_state <= SEND_DOT;
                    current_state <= WAIT_TX_DONE;

                when SEND_DOT =>
                    r_uart_data <= x"2E"; -- '.'
                    r_uart_start <= '1';
                    next_state <= SEND_DECIMAL;
                    current_state <= WAIT_TX_DONE;

                when SEND_DECIMAL =>
                    if fract_part_is_5 then
                        r_uart_data <= x"35"; -- '5'
                    else
                        r_uart_data <= x"30"; -- '0'
                    end if;
                    r_uart_start <= '1';
                    next_state <= SEND_UNIT;
                    current_state <= WAIT_TX_DONE;

                when SEND_UNIT =>
                    r_uart_data <= x"43"; -- 'C'
                    r_uart_start <= '1';
                    next_state <= SEND_CR;
                    current_state <= WAIT_TX_DONE;
                
                when SEND_CR =>
                    r_uart_data <= x"0D"; -- CR
                    r_uart_start <= '1';
                    next_state <= SEND_LF;
                    current_state <= WAIT_TX_DONE;

                when SEND_LF =>
                    r_uart_data <= x"0A"; -- LF
                    r_uart_start <= '1';
                    next_state <= IDLE; 
                    current_state <= WAIT_TX_DONE;

                when WAIT_TX_DONE =>
                    if i_uart_done = '1' then
                        current_state <= next_state;
                    end if;

                when others =>
                    current_state <= IDLE;

            end case;
        end if;
    end process;

end Behavioral;