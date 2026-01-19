----------------------------------------------------------------------------
-- Author:  Ruxuan Wen
--        Input (1 LSB = 1/16 C) -> Output (1 LSB = 0.1 C) : Output = (Input * 10) / 16
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity TempConversion is
    Port ( 
        CLK_I       : in  STD_LOGIC;                    -- System Clock
        RAW_TEMP_I  : in  STD_LOGIC_VECTOR (12 downto 0); -- 13-bit raw data from TempSensorCtl
        -- Modification: Changed output type to INTEGER, range covers the maximum temperature range corresponding to 13-bit signed numbers
        TEMP_X10_O  : out INTEGER range -8192 to 8191 
    );
end TempConversion;

architecture Behavioral of TempConversion is
    -- Signals for calculation
    signal raw_signed : signed(12 downto 0);
    signal calc_temp  : signed(16 downto 0); -- Result needs more bits
begin

    process(CLK_I)
    begin
        if rising_edge(CLK_I) then
            -- 1. Convert input to signed
            raw_signed <= signed(RAW_TEMP_I);
            
            -- 2. Multiply by 10
            calc_temp <= resize(raw_signed * 10, 17);
            
            -- 3. Divide by 16 and Convert to INTEGER
            --    Divide by 16 is essentially taking bits 16 downto 4.
            --    We use to_integer() to convert the signed vector to a VHDL integer.
            TEMP_X10_O <= to_integer(calc_temp(16 downto 4));
        end if;
    end process;

end Behavioral;