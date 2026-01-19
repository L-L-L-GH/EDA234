----------------------------------------------------------------------------
-- Author:  Li Ling
----------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity lcd_controller is
    generic(
        SIMULATION_MODE : boolean := false
    );
    port(
        clk       : in  std_logic;
        rst_n     : in  std_logic;
        lcd_rs    : out std_logic;
        lcd_rw    : out std_logic;
        lcd_e     : out std_logic;
        lcd_data  : out std_logic_vector(3 downto 0);
        ram_raddr : out integer range 0 to 31;
        ram_rdata : in  std_logic_vector(7 downto 0);
        refresh_led : out std_logic
    );
end lcd_controller;

architecture Behavioral of lcd_controller is

    -- Timing constants
    constant C_US_REAL : integer := 200; -- Microsecond delay
    constant C_MS_REAL : integer := 100000; -- Millisecond delay
    constant C_CMD_WAIT_REAL : integer := 5000; -- Command wait time
    constant C_REFRESH_DELAY_REAL : integer := 5000000; -- Refresh delay

    constant C_US_SIM : integer := 1; -- Microsecond delay for simulation
    constant C_MS_SIM : integer := 10; -- Millisecond delay for simulation
    constant C_CMD_WAIT_SIM : integer := 5; -- Command wait time for simulation
    constant C_REFRESH_DELAY_SIM : integer := 1000; -- Refresh delay for simulation

    signal C_US, C_MS, C_CMD_WAIT, C_REFRESH_DELAY : integer;

    -- LCD commands
    constant CMD_FUNCTION_SET : std_logic_vector(7 downto 0) := x"28"; -- Function set
    constant CMD_DISPLAY_OFF  : std_logic_vector(7 downto 0) := x"08"; -- Display off
    constant CMD_CLEAR        : std_logic_vector(7 downto 0) := x"01"; -- Clear display
    constant CMD_ENTRY_MODE   : std_logic_vector(7 downto 0) := x"06"; -- Entry mode set
    constant CMD_DISPLAY_ON   : std_logic_vector(7 downto 0) := x"0C"; -- Display on
    constant CMD_SET_DDRAM0   : std_logic_vector(7 downto 0) := x"80"; -- Set DDRAM address line 0
    constant CMD_SET_DDRAM1   : std_logic_vector(7 downto 0) := x"C0"; -- Set DDRAM address line 1

    -- Write nibble FSM states
    type write_state_type is (W_IDLE, W_SETUP_HI, W_E_HI, W_E_LO, W_SETUP_LO, W_E2_HI, W_E2_LO, W_DONE);
    signal wstate : write_state_type := W_IDLE;

    signal rs_reg   : std_logic := '0';
    signal e_reg    : std_logic := '0';
    signal data_reg : std_logic_vector(3 downto 0) := (others => '0');

    signal current_byte : std_logic_vector(7 downto 0) := (others => '0');
    signal write_req    : std_logic := '0';
    signal write_done   : std_logic := '0';
    signal write_delay_cnt : integer := 0;

    -- Main FSM states
    type main_state_type is (
        S_POWER_DELAY, -- Initial power-on delay
        S_INIT_0, S_INIT_1_DELAY, S_INIT_1, S_INIT_2, S_INIT_3, -- Initialization sequence
        S_FUNCTION_SET, S_DISPLAY_OFF, S_CLEAR, S_CLEAR_LONG, -- LCD setup commands
        S_ENTRY_MODE, S_DISPLAY_ON, -- Entry mode and display on
        S_SET_ADDR_LINE1, -- Set address to line 1
        S_CHECK_POS, -- Check cursor position
        S_LINE_BREAK, -- Handle line break
        S_FETCH_CHAR, -- Fetch character from RAM
        S_WRITE_CHAR, -- Write character to LCD
        S_REFRESH_DELAY, -- Refresh delay
        S_WAIT_DONE, -- Wait for operation to complete
        S_POST_WAIT -- Post-operation wait
    );

    signal state      : main_state_type := S_POWER_DELAY;
    signal next_state : main_state_type := S_POWER_DELAY;

    signal main_delay_cnt : integer := 0;

    signal addr_ptr : integer range 0 to 32 := 0; -- Address pointer
    signal led_blink : std_logic := '0'; -- LED blink signal
    signal init_phase : std_logic := '1'; -- Initialization phase flag

    signal char_buf : std_logic_vector(7 downto 0) := x"20"; -- Character buffer

begin

    -- Select timing constants based on simulation mode
    C_US            <= C_US_SIM            when SIMULATION_MODE else C_US_REAL;
    C_MS            <= C_MS_SIM            when SIMULATION_MODE else C_MS_REAL;
    C_CMD_WAIT      <= C_CMD_WAIT_SIM      when SIMULATION_MODE else C_CMD_WAIT_REAL;
    C_REFRESH_DELAY <= C_REFRESH_DELAY_SIM when SIMULATION_MODE else C_REFRESH_DELAY_REAL;

    lcd_rs <= rs_reg;
    lcd_rw <= '0';
    lcd_e  <= e_reg;
    lcd_data <= data_reg;

    refresh_led <= led_blink;

    ram_raddr <= addr_ptr when (addr_ptr >= 0 and addr_ptr <= 31) else 0;

    --------------------------------------------------------------------
    -- Nibble write FSM 
    --------------------------------------------------------------------
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            wstate <= W_IDLE;
            write_done <= '0';
            e_reg <= '0';
            data_reg <= (others => '0');
            write_delay_cnt <= 0;
        elsif rising_edge(clk) then
            case wstate is
                when W_IDLE =>
                    write_done <= '0';
                    e_reg <= '0';
                    if write_req = '1' then
                        data_reg <= current_byte(7 downto 4);
                        write_delay_cnt <= 0;
                        wstate <= W_SETUP_HI;
                    end if;

                when W_SETUP_HI =>
                    if write_delay_cnt = C_US then
                        write_delay_cnt <= 0;
                        e_reg <= '1';
                        wstate <= W_E_HI;
                    else
                        write_delay_cnt <= write_delay_cnt + 1;
                    end if;

                when W_E_HI =>
                    if write_delay_cnt = C_US then
                        write_delay_cnt <= 0;
                        e_reg <= '0';
                        wstate <= W_E_LO;
                    else
                        write_delay_cnt <= write_delay_cnt + 1;
                    end if;

                when W_E_LO =>
                    if write_delay_cnt = C_US then
                        write_delay_cnt <= 0;
                        if init_phase = '1' then
                            wstate <= W_DONE;
                        else
                            data_reg <= current_byte(3 downto 0);
                            wstate <= W_SETUP_LO;
                        end if;
                    else
                        write_delay_cnt <= write_delay_cnt + 1;
                    end if;

                when W_SETUP_LO =>
                    if write_delay_cnt = C_US then
                        write_delay_cnt <= 0;
                        e_reg <= '1';
                        wstate <= W_E2_HI;
                    else
                        write_delay_cnt <= write_delay_cnt + 1;
                    end if;

                when W_E2_HI =>
                    if write_delay_cnt = C_US then
                        write_delay_cnt <= 0;
                        e_reg <= '0';
                        wstate <= W_E2_LO;
                    else
                        write_delay_cnt <= write_delay_cnt + 1;
                    end if;

                when W_E2_LO =>
                    if write_delay_cnt = C_US then
                        write_delay_cnt <= 0;
                        wstate <= W_DONE;
                    else
                        write_delay_cnt <= write_delay_cnt + 1;
                    end if;

                when W_DONE =>
                    write_done <= '1';
                    wstate <= W_IDLE;
            end case;
        end if;
    end process;

    --------------------------------------------------------------------
    -- Main FSM
    --------------------------------------------------------------------
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            state <= S_POWER_DELAY;
            next_state <= S_POWER_DELAY;
            main_delay_cnt <= 0;
            write_req <= '0';
            init_phase <= '1';
            addr_ptr <= 0;
            led_blink <= '0';
            rs_reg <= '0';
            current_byte <= (others => '0');
            char_buf <= x"20";
        elsif rising_edge(clk) then
            write_req <= '0'; -- Pulse control

            case state is
                when S_POWER_DELAY =>
                    if main_delay_cnt < 20*C_MS then
                        main_delay_cnt <= main_delay_cnt + 1;
                    else
                        main_delay_cnt <= 0;
                        state <= S_INIT_0;
                    end if;

                -- init
                when S_INIT_0 =>
                    init_phase <= '1';
                    current_byte <= x"30"; rs_reg <= '0'; write_req <= '1';
                    state <= S_WAIT_DONE; next_state <= S_INIT_1_DELAY;

                when S_INIT_1_DELAY =>
                    if main_delay_cnt < 5*C_MS then
                        main_delay_cnt <= main_delay_cnt + 1;
                    else
                        main_delay_cnt <= 0;
                        state <= S_INIT_1;
                    end if;

                when S_INIT_1 =>
                    current_byte <= x"30"; rs_reg <= '0'; write_req <= '1';
                    state <= S_WAIT_DONE; next_state <= S_INIT_2;

                when S_INIT_2 =>
                    current_byte <= x"30"; rs_reg <= '0'; write_req <= '1';
                    state <= S_WAIT_DONE; next_state <= S_INIT_3;

                when S_INIT_3 =>
                    current_byte <= x"20"; rs_reg <= '0'; write_req <= '1';
                    state <= S_WAIT_DONE; next_state <= S_FUNCTION_SET;

                when S_FUNCTION_SET =>
                    init_phase <= '0';
                    current_byte <= CMD_FUNCTION_SET; rs_reg <= '0'; write_req <= '1';
                    state <= S_WAIT_DONE; next_state <= S_DISPLAY_OFF;

                when S_DISPLAY_OFF =>
                    current_byte <= CMD_DISPLAY_OFF; rs_reg <= '0'; write_req <= '1';
                    state <= S_WAIT_DONE; next_state <= S_CLEAR;

                when S_CLEAR =>
                    current_byte <= CMD_CLEAR; rs_reg <= '0'; write_req <= '1';
                    state <= S_WAIT_DONE; next_state <= S_CLEAR_LONG;
                    main_delay_cnt <= 0;

                when S_CLEAR_LONG =>
                    if main_delay_cnt < 3*C_MS then
                        main_delay_cnt <= main_delay_cnt + 1;
                    else
                        main_delay_cnt <= 0;
                        state <= S_ENTRY_MODE;
                    end if;

                when S_ENTRY_MODE =>
                    current_byte <= CMD_ENTRY_MODE; rs_reg <= '0'; write_req <= '1';
                    state <= S_WAIT_DONE; next_state <= S_DISPLAY_ON;

                when S_DISPLAY_ON =>
                    current_byte <= CMD_DISPLAY_ON; rs_reg <= '0'; write_req <= '1';
                    state <= S_WAIT_DONE; next_state <= S_SET_ADDR_LINE1;

                -- refresh loop
                when S_SET_ADDR_LINE1 =>
                    led_blink <= not led_blink;
                    current_byte <= CMD_SET_DDRAM0; rs_reg <= '0'; write_req <= '1';
                    addr_ptr <= 0;
                    state <= S_WAIT_DONE; next_state <= S_CHECK_POS;

                when S_CHECK_POS =>
                    if addr_ptr = 16 then
                        state <= S_LINE_BREAK;
                    elsif addr_ptr = 32 then
                        state <= S_REFRESH_DELAY;
                    else
                        state <= S_FETCH_CHAR;
                    end if;

                when S_LINE_BREAK =>
                    current_byte <= CMD_SET_DDRAM1; rs_reg <= '0'; write_req <= '1';
                    state <= S_WAIT_DONE; next_state <= S_FETCH_CHAR;

                when S_FETCH_CHAR =>
                    -- Read data from RAM 
                    char_buf <= ram_rdata;
                    state <= S_WRITE_CHAR;

                when S_WRITE_CHAR =>
                    current_byte <= char_buf; rs_reg <= '1'; write_req <= '1';

                    if addr_ptr < 31 then
                        addr_ptr <= addr_ptr + 1;
                    else
                        addr_ptr <= 32;
                    end if;

                    state <= S_WAIT_DONE; next_state <= S_CHECK_POS;

                when S_REFRESH_DELAY =>
                    if main_delay_cnt < C_REFRESH_DELAY then
                        main_delay_cnt <= main_delay_cnt + 1;
                    else
                        main_delay_cnt <= 0;
                        state <= S_SET_ADDR_LINE1;
                    end if;

                -- common waits
                when S_WAIT_DONE =>
                    if write_done = '1' then
                        main_delay_cnt <= 0;
                        state <= S_POST_WAIT;
                    end if;

                when S_POST_WAIT =>
                    if main_delay_cnt < C_CMD_WAIT then
                        main_delay_cnt <= main_delay_cnt + 1;
                    else
                        main_delay_cnt <= 0;
                        state <= next_state;
                    end if;
            end case;
        end if;
    end process;
end Behavioral;