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
        
        -- Interface with DS18S20 Driver
        i_temp_data   : in  std_logic_vector(15 downto 0); -- Raw temp from sensor
        i_temp_done   : in  std_logic;                     -- Pulse when temp is ready
        
        -- Interface with UART TX
        i_uart_done   : in  std_logic;                     -- UART done signal
        o_uart_data   : out std_logic_vector(7 downto 0);  -- Byte to send
        o_uart_start  : out std_logic                      -- Start transmission pulse
    );
end Temp_to_ASCII;

architecture Behavioral of Temp_to_ASCII is

    -- Conversion and Control Signals
    type state_t is (
        IDLE,           -- Wait for Temperature conversion
        PROCESS_TEMP,   -- Convert binary to decimals
        SEND_SIGN,      -- Send '+' or '-'
        SEND_HUNDREDS,  -- Send Hundreds digit (if non-zero)
        SEND_TENS,      -- Send Tens digit
        SEND_ONES,      -- Send Ones digit
        SEND_DOT,       -- Send '.'
        SEND_DECIMAL,   -- Send decimal part (0 or 5)
        SEND_UNIT,      -- Send 'C'
        SEND_CR,        -- Send Carriage Return
        SEND_LF,        -- Send Line Feed
        WAIT_TX_DONE    -- Wait for UART to finish a byte
    );
    signal current_state : state_t := IDLE;
    signal next_state    : state_t := IDLE; -- Used for return after WAIT_TX_DONE

    -- Output registers
    signal r_uart_data   : std_logic_vector(7 downto 0) := (others => '0');
    signal r_uart_start  : std_logic := '0';

    -- Data Storage for Conversion
    signal int_part        : integer range 0 to 255;
    signal is_negative     : boolean;
    signal fract_part_is_5 : boolean;
    
    signal digit_hundreds  : integer range 0 to 9;
    signal digit_tens      : integer range 0 to 9;
    signal digit_ones      : integer range 0 to 9;

begin

    -- Output assignment
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
            
            -- Default assignment
            r_uart_start <= '0'; 

            case current_state is
                
                -- Wait for DS18S20 to finish a reading
                when IDLE =>
                    if i_temp_done = '1' then
                        current_state <= PROCESS_TEMP;
                    else
                        current_state <= IDLE;
                    end if;

                -- Logic to parse the 16-bit DS18S20 Data
                -- DS18S20 Format: S S S S S S S S | I I I I I I I F
                -- (Sign extended, 7 bits integer, 1 bit fraction)
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

                    -- Extract Integer part (shift right by 1)
                    int_part <= temp_val_int / 2;
                    
                    -- Extract Fraction part (check bit 0)
                    -- If bit 0 is 1, it means .5, otherwise .0
                    if (temp_val_int mod 2) /= 0 then
                        fract_part_is_5 <= true;
                    else
                        fract_part_is_5 <= false;
                    end if;

                    current_state <= SEND_SIGN;

                -- 1. Send Sign (+ or -)
                when SEND_SIGN =>
                    if is_negative then
                        r_uart_data <= x"2D"; -- '-'
                    else
                        r_uart_data <= x"2B"; -- '+'
                    end if;
                    r_uart_start <= '1';
                    
                    -- Prepare digits for next steps while sending
                    digit_hundreds <= int_part / 100;
                    digit_tens     <= (int_part / 10) mod 10;
                    digit_ones     <= int_part mod 10;
                    
                    next_state <= SEND_HUNDREDS;
                    current_state <= WAIT_TX_DONE;

                -- 2. Send Hundreds (Only if > 0 to avoid "025")
                when SEND_HUNDREDS =>
                    if digit_hundreds > 0 then
                        r_uart_data <= std_logic_vector(to_unsigned(digit_hundreds + 48, 8)); -- ASCII '0' is 48
                        r_uart_start <= '1';
                        next_state <= SEND_TENS;
                        current_state <= WAIT_TX_DONE;
                    else
                        current_state <= SEND_TENS;
                    end if;

                -- 3. Send Tens
                when SEND_TENS =>
                    r_uart_data <= std_logic_vector(to_unsigned(digit_tens + 48, 8));
                    r_uart_start <= '1';
                    next_state <= SEND_ONES;
                    current_state <= WAIT_TX_DONE;

                -- 4. Send Ones
                when SEND_ONES =>
                    r_uart_data <= std_logic_vector(to_unsigned(digit_ones + 48, 8));
                    r_uart_start <= '1';
                    next_state <= SEND_DOT;
                    current_state <= WAIT_TX_DONE;

                -- 5. Send Dot '.'
                when SEND_DOT =>
                    r_uart_data <= x"2E"; -- '.'
                    r_uart_start <= '1';
                    next_state <= SEND_DECIMAL;
                    current_state <= WAIT_TX_DONE;

                -- 6. Send Decimal Part
                when SEND_DECIMAL =>
                    if fract_part_is_5 then
                        r_uart_data <= x"35"; -- '5'
                    else
                        r_uart_data <= x"30"; -- '0'
                    end if;
                    r_uart_start <= '1';
                    next_state <= SEND_UNIT;
                    current_state <= WAIT_TX_DONE;

                -- 7. Send 'C' (Celsius)
                when SEND_UNIT =>
                    r_uart_data <= x"43"; -- 'C'
                    r_uart_start <= '1';
                    next_state <= SEND_CR;
                    current_state <= WAIT_TX_DONE;
                
                -- 8. Send CR (Carriage Return)
                when SEND_CR =>
                    r_uart_data <= x"0D"; -- CR
                    r_uart_start <= '1';
                    next_state <= SEND_LF;
                    current_state <= WAIT_TX_DONE;

                -- 9. Send LF (Line Feed) -> New Line
                when SEND_LF =>
                    r_uart_data <= x"0A"; -- LF
                    r_uart_start <= '1';
                    next_state <= IDLE; -- Go back to IDLE to wait for next temp reading
                    current_state <= WAIT_TX_DONE;

                -- Generic State to wait for UART TX to finish sending current byte
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