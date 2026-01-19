--author : Hanyin Gu
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity keyboard_scanner is
    Port (
        clk         : in  STD_LOGIC; 
        row         : in  STD_LOGIC_VECTOR(3 downto 0); 
        col         : out STD_LOGIC_VECTOR(3 downto 0); 
        key_val     : out integer range 0 to 15;        
        key_pressed : out STD_LOGIC                    
    );
end keyboard_scanner;

architecture Behavioral of keyboard_scanner is
    signal clk_cnt : unsigned(16 downto 0) := (others => '0'); 
    signal scan_idx : integer range 0 to 3 := 0;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            clk_cnt <= clk_cnt + 1;
 
            if clk_cnt = 0 then
                case scan_idx is
                    when 0 => col <= "1110"; 
                    when 1 => col <= "1101"; 
                    when 2 => col <= "1011"; 
                    when 3 => col <= "0111"; 
                end case;
                
 
                if scan_idx = 3 then
                    scan_idx <= 0;
                else
                    scan_idx <= scan_idx + 1;
                end if;
            end if;

  
            if clk_cnt = 50000 then 
                if row /= "1111" then
                    key_pressed <= '1';
                    
                    case scan_idx is
                        when 1 => 
                            if    row = "1110" then key_val <= 1;
                            elsif row = "1101" then key_val <= 5;
                            elsif row = "1011" then key_val <= 9;
                            elsif row = "0111" then key_val <= 13;
                            end if;
                        when 2 => 
                            if    row = "1110" then key_val <= 2;
                            elsif row = "1101" then key_val <= 6;
                            elsif row = "1011" then key_val <= 10;
                            elsif row = "0111" then key_val <= 14;
                            end if;
                        when 3 => 
                            if    row = "1110" then key_val <= 3;
                            elsif row = "1101" then key_val <= 7;
                            elsif row = "1011" then key_val <= 11;
                            elsif row = "0111" then key_val <= 15;
                            end if;
                        when 0 => 
                            if    row = "1110" then key_val <= 4;  -- A
                            elsif row = "1101" then key_val <= 8;  --  B
                            elsif row = "1011" then key_val <= 12; --  C
                            elsif row = "0111" then key_val <= 0;  --  D 
                            end if;
                    end case;
                else
                    key_pressed <= '0';
                end if;
            end if;
        end if;
    end process;
end Behavioral;