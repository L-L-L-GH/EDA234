library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity keyboard_scanner is
    Port (
        clk         : in  STD_LOGIC; -- 100MHz
        row         : in  STD_LOGIC_VECTOR(3 downto 0); -- 接键盘行
        col         : out STD_LOGIC_VECTOR(3 downto 0); -- 接键盘列
        key_val     : out integer range 0 to 15;        -- 键值
        key_pressed : out STD_LOGIC                     -- 标志位
    );
end keyboard_scanner;

architecture Behavioral of keyboard_scanner is
    -- 计数器：2^17 约等于 1.3ms 循环一次
    signal clk_cnt : unsigned(16 downto 0) := (others => '0'); 
    signal scan_idx : integer range 0 to 3 := 0;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            clk_cnt <= clk_cnt + 1;
            
            -- 【第一步】在计数器归零时：切换列（Column）
            if clk_cnt = 0 then
                case scan_idx is
                    when 0 => col <= "1110"; -- 扫描第1列
                    when 1 => col <= "1101"; -- 扫描第2列
                    when 2 => col <= "1011"; -- 扫描第3列
                    when 3 => col <= "0111"; -- 扫描第4列
                end case;
                
                -- 准备下一次扫描的索引
                if scan_idx = 3 then
                    scan_idx <= 0;
                else
                    scan_idx <= scan_idx + 1;
                end if;
            end if;

            -- 【第二步】关键改进：在计数器走到一半时读取行（Row）
            -- 此时列信号已经稳定传输到了键盘并返回
            if clk_cnt = 50000 then 
                -- 只有当行不全为1时（说明有键按下，因为是低电平有效）
                if row /= "1111" then
                    key_pressed <= '1';
                    
                    -- 根据当前的列（注意：这里用的 scan_idx 是已经+1后的，所以要回推一下）
                    -- 或者更简单的：我们直接判断当前输出的 col 状态对应的 scan_idx
                    -- 上面 scan_idx 已经变了，所以这里我们用"上一个状态"来算，或者简单处理如下：
                    
                    -- 修正逻辑：因为 scan_idx 在 clk_cnt=0 时已经改变了
                    -- 当 scan_idx=1 时，其实正在扫描的是 第0列(之前的scan_idx)
                    -- 为了逻辑简单，我们可以根据当前的 scan_idx 推算：
                    
                    case scan_idx is
                        when 1 => -- 当前是1，说明刚刚扫描完的是 0 (第1列)
                            if    row = "1110" then key_val <= 1;
                            elsif row = "1101" then key_val <= 5;
                            elsif row = "1011" then key_val <= 9;
                            elsif row = "0111" then key_val <= 13;
                            end if;
                        when 2 => -- 刚刚扫描完的是 1 (第2列)
                            if    row = "1110" then key_val <= 2;
                            elsif row = "1101" then key_val <= 6;
                            elsif row = "1011" then key_val <= 10;
                            elsif row = "0111" then key_val <= 14;
                            end if;
                        when 3 => -- 刚刚扫描完的是 2 (第3列)
                            if    row = "1110" then key_val <= 3;
                            elsif row = "1101" then key_val <= 7;
                            elsif row = "1011" then key_val <= 11;
                            elsif row = "0111" then key_val <= 15;
                            end if;
                        when 0 => -- 刚刚扫描完的是 3 (第4列)
                            if    row = "1110" then key_val <= 4;  -- 这里通常是 A
                            elsif row = "1101" then key_val <= 8;  -- 这里通常是 B
                            elsif row = "1011" then key_val <= 12; -- 这里通常是 C
                            elsif row = "0111" then key_val <= 0;  -- 键盘上通常是 0 或 D (视键盘而定)
                            end if;
                    end case;
                else
                    key_pressed <= '0';
                end if;
            end if;
        end if;
    end process;
end Behavioral;