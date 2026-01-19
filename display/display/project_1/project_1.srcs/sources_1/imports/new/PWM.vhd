library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pwm_driver is
    Port (
        clk     : in  STD_LOGIC;
        data_in : in  STD_LOGIC_VECTOR(7 downto 0);
        pwm_out : out STD_LOGIC
    );
end pwm_driver;

architecture Behavioral of pwm_driver is
    signal counter : unsigned(7 downto 0) := (others => '0');
begin
    process(clk)
    begin
        if rising_edge(clk) then
            counter <= counter + 1;
            if counter < unsigned(data_in) then
                pwm_out <= '1';
            else
                pwm_out <= '0';
            end if;
        end if;
    end process;
end Behavioral;