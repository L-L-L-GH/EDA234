----------------------------------------------------------------------------
-- Author:  Li Ling
----------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity lcd_text_ram is
    port (
        clk      : in  std_logic;
        waddr    : in  integer range 0 to 31; -- Write address
        wdata    : in  std_logic_vector(7 downto 0); -- Write data
        raddr    : in  integer range 0 to 31; -- Read address
        rdata    : out std_logic_vector(7 downto 0) -- Read data
    );
end lcd_text_ram;

architecture Behavioral of lcd_text_ram is
    -- RAM type definition: 32 words of 8-bit data
    type ram_type is array(0 to 31) of std_logic_vector(7 downto 0);
    signal ram : ram_type := (
        0 => x"48", 1 => x"45", 2 => x"4C", 3 => x"4C", 4 => x"4F", 5 => x"20", -- "HELLO "
        6 => x"57", 7 => x"4F", 8 => x"52", 9 => x"4C",10 => x"44",11 => x"21", -- "WORLD!"
        others => x"20" -- Fill the rest with spaces
    );
    signal rdata_reg : std_logic_vector(7 downto 0) := x"20"; -- Register for read data
begin
    process(clk)
    begin
        if rising_edge(clk) then
            -- Write operation
            ram(waddr) <= wdata;

            -- Synchronous read
            rdata_reg <= ram(raddr);
        end if;
    end process;

    -- Output read data
    rdata <= rdata_reg;
end Behavioral;

