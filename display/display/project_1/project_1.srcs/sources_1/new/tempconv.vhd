----------------------------------------------------------------------------
-- Author:  Ruxuan Wen
--        Input (1 LSB = 1/16 C) -> Output (1 LSB = 0.1 C) : Output = (Input * 10) / 16
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity TempConversion is
    Port ( 
        CLK_I       : in  STD_LOGIC;                    
        RAW_TEMP_I  : in  STD_LOGIC_VECTOR (12 downto 0); 
        TEMP_X10_O  : out INTEGER range -8192 to 8191 
    );
end TempConversion;

architecture Behavioral of TempConversion is
    
    signal raw_signed : signed(12 downto 0);
    signal calc_temp  : signed(16 downto 0); 
begin

    process(CLK_I)
    begin
        if rising_edge(CLK_I) then
            raw_signed <= signed(RAW_TEMP_I);
            calc_temp <= resize(raw_signed * 10, 17);
            TEMP_X10_O <= to_integer(calc_temp(16 downto 4));
        end if;
    end process;

end Behavioral;