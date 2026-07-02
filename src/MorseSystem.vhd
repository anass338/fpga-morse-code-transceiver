library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity MorseSystem is
    Port ( 
        clk  : in STD_LOGIC;                      -- 100 MHz Clock
        btnC : in STD_LOGIC;                      -- MANUAL BUTTON (Decoder)
        btnU : in STD_LOGIC;                      -- TRIGGER BUTTON (Auto Encoder)
        sw   : in STD_LOGIC_VECTOR(4 downto 0);   -- SWITCHES (0-31 for A-Z)
        
        led  : out STD_LOGIC_VECTOR (15 downto 0);-- VISUALIZATION
        seg  : out STD_LOGIC_VECTOR (6 downto 0); -- SEGMENTS (gfedcba)
        an   : out STD_LOGIC_VECTOR (3 downto 0); -- ANODES
        
        RsTx : out STD_LOGIC;                     -- UART TX (To PC)
        ja   : out STD_LOGIC_VECTOR(0 downto 0)   -- AUDIO OUT
    );
end MorseSystem;

architecture Behavioral of MorseSystem is

    -- === TIME CONSTANTS (100 MHz) ===
    -- Adjust these values if you want to type faster or slower
    constant T_POINT_MAX : integer := 25000000; -- < 250ms = Dot (.)
    constant T_SILENCE   : integer := 40000000; -- > 400ms = End of letter
    constant T_BEEP_DOT  : integer := 10000000; -- 100ms base time for encoder
    
    -- === GLOBAL SIGNALS ===
    signal timer_appui   : integer := 0;
    signal timer_silence : integer := 0;
    
    -- Morse Buffer (Sentinel + 4 bits max for letters)
    -- "00001" is the initial state (1 is the sentinel bit)
    signal pattern       : std_logic_vector(4 downto 0) := "00001"; 
    
    -- Scrolling message (4 stored characters)
    type text_buffer_t is array (0 to 3) of std_logic_vector(7 downto 0); -- ASCII
    signal display_buffer : text_buffer_t := (others => X"20"); -- Default space
    
    -- Audio
    signal audio_enable  : std_logic := '0';
    signal audio_osc     : std_logic := '0';
    signal audio_cnt     : integer := 0;

    -- === ENCODER SIGNALS (Auto Mode) ===
    type state_type is (IDLE, PLAY, PAUSE, NEXT_BIT);
    signal enc_state   : state_type := IDLE;
    signal enc_pattern : std_logic_vector(4 downto 0);
    signal enc_len     : integer range 0 to 5;
    signal enc_idx     : integer range 0 to 5;
    signal enc_timer   : integer := 0;
    signal enc_target  : integer := 0;
    signal auto_sound  : std_logic := '0';

    -- === UART SIGNALS (Serial) ===
    signal uart_data    : std_logic_vector(7 downto 0) := (others => '0');
    signal uart_start   : std_logic := '0';
    signal uart_busy    : std_logic := '0';
    signal uart_timer   : integer := 0;
    signal uart_bit_idx : integer range 0 to 9 := 0;
    signal uart_tx_reg  : std_logic := '1';
    
    constant C_BAUD_RATE : integer := 10416; 

begin

    -- =========================================================================
    -- 1. SOUND MANAGEMENT (Mixer)
    -- =========================================================================
    audio_enable <= btnC or auto_sound;
    
    process(clk)
    begin
        if rising_edge(clk) then
            if audio_enable = '1' then
                -- 1kHz square wave generation
                if audio_cnt < 50000 then 
                    audio_cnt <= audio_cnt + 1;
                else
                    audio_cnt <= 0;
                    audio_osc <= not audio_osc;
                end if;
            else
                audio_osc <= '0';
                audio_cnt <= 0;
            end if;
        end if;
    end process;
    
    ja(0) <= audio_osc;

    -- =========================================================================
    -- 2. MORSE DECODER (Logic Shift Register)
    -- =========================================================================
    process(clk)
        variable char_ascii : std_logic_vector(7 downto 0);
        variable valid_char : boolean := false;
        variable prev_btn   : std_logic := '0';
    begin
        if rising_edge(clk) then
            -- Debug Visualization (Current pattern on right LEDs)
            if btnC = '0' then
                led(4 downto 0) <= pattern;
                led(15 downto 5) <= (others => '0');
            else
                -- Hold time gauge visualization
                if timer_appui < T_POINT_MAX then
                    led <= "0000000000001111"; -- Short (Dot)
                else
                    led <= "1111111111111111"; -- Long (Dash)
                end if;
            end if;

            uart_start <= '0'; 

            if btnC = '1' then
                timer_appui <= timer_appui + 1;
                timer_silence <= 0;
            else
                -- Button release detection
                if prev_btn = '1' then 
                    if timer_appui < T_POINT_MAX then
                        -- Add a DOT (0) -> Shift Left
                        pattern <= pattern(3 downto 0) & '0';
                    else
                        -- Add a DASH (1) -> Shift Left
                        pattern <= pattern(3 downto 0) & '1';
                    end if;
                    timer_appui <= 0;
                end if;

                -- Silence management (Letter validation)
                if timer_silence < T_SILENCE then
                    timer_silence <= timer_silence + 1;
                elsif timer_silence = T_SILENCE then
                    -- END OF LETTER : Decoding
                    valid_char := true;
                    
                    -- LOGIC : The leftmost '1' is the start sentinel.
                    -- Example A (.-) : Start(1) -> 10 (.) -> 101 (-) = "00101"
                    case pattern is
                        when "00101" => char_ascii := X"41"; -- A (.-)
                        when "11000" => char_ascii := X"42"; -- B (-...)
                        when "11010" => char_ascii := X"43"; -- C (-.-.)
                        when "01100" => char_ascii := X"44"; -- D (-..)
                        when "00010" => char_ascii := X"45"; -- E (.)
                        when "10010" => char_ascii := X"46"; -- F (..-.)
                        when "01110" => char_ascii := X"47"; -- G (--.)
                        when "10000" => char_ascii := X"48"; -- H (....)
                        when "00100" => char_ascii := X"49"; -- I (..)
                        when "10111" => char_ascii := X"4A"; -- J (.---)
                        when "01101" => char_ascii := X"4B"; -- K (-.-)
                        when "10100" => char_ascii := X"4C"; -- L (.-..)
                        when "00111" => char_ascii := X"4D"; -- M (--)
                        when "00110" => char_ascii := X"4E"; -- N (-.)
                        when "01111" => char_ascii := X"4F"; -- O (---)
                        when "10110" => char_ascii := X"50"; -- P (.--.)
                        when "11101" => char_ascii := X"51"; -- Q (--.-)
                        when "01010" => char_ascii := X"52"; -- R (.-.)
                        when "01000" => char_ascii := X"53"; -- S (...)
                        when "00011" => char_ascii := X"54"; -- T (-)
                        when "01001" => char_ascii := X"55"; -- U (..-)
                        when "10001" => char_ascii := X"56"; -- V (...-)
                        when "01011" => char_ascii := X"57"; -- W (.--)
                        when "11001" => char_ascii := X"58"; -- X (-..-)
                        when "11011" => char_ascii := X"59"; -- Y (-.--)
                        when "11100" => char_ascii := X"5A"; -- Z (--..)
                        when "00001" => valid_char := false; -- Empty (noise)
                        when others  => char_ascii := X"3F"; -- ?
                    end case;

                    if valid_char then
                        -- Shift Display Buffer
                        display_buffer(3) <= display_buffer(2);
                        display_buffer(2) <= display_buffer(1);
                        display_buffer(1) <= display_buffer(0);
                        display_buffer(0) <= char_ascii;
                        
                        -- UART Send
                        uart_data <= char_ascii;
                        uart_start <= '1';
                    end if;
                    
                    pattern <= "00001"; -- Reset Pattern with sentinel bit
                end if;
            end if;
            prev_btn := btnC;
        end if;
    end process;

    -- =========================================================================
    -- 3. AUTOMATIC ENCODER (Complete A-Z Table)
    -- =========================================================================
    process(clk)
        variable sw_val : integer;
    begin
        if rising_edge(clk) then
            sw_val := to_integer(unsigned(sw)); -- 0 to 31
            
            case enc_state is
                when IDLE =>
                    auto_sound <= '0';
                    if btnU = '1' then
                        enc_idx <= 0;
                        enc_timer <= 0;
                        
                        -- Encoder pattern definition
                        -- 0 = Dot, 1 = Dash
                        -- Reading order is enc_len-1 downto 0
                        case sw_val is
                            when 0 =>  enc_pattern <= "00001"; enc_len <= 2; -- A (.-) -> Bits: 0,1
                            when 1 =>  enc_pattern <= "01000"; enc_len <= 4; -- B (-...) -> Bits: 1,0,0,0
                            when 2 =>  enc_pattern <= "01010"; enc_len <= 4; -- C (-.-.)
                            when 3 =>  enc_pattern <= "00100"; enc_len <= 3; -- D (-..)
                            when 4 =>  enc_pattern <= "00000"; enc_len <= 1; -- E (.)
                            when 5 =>  enc_pattern <= "00010"; enc_len <= 4; -- F (..-.)
                            when 6 =>  enc_pattern <= "00110"; enc_len <= 3; -- G (--.)
                            when 7 =>  enc_pattern <= "00000"; enc_len <= 4; -- H (....)
                            when 8 =>  enc_pattern <= "00000"; enc_len <= 2; -- I (..)
                            when 9 =>  enc_pattern <= "00111"; enc_len <= 4; -- J (.---)
                            when 10 => enc_pattern <= "00101"; enc_len <= 3; -- K (-.-)
                            when 11 => enc_pattern <= "00010"; enc_len <= 4; -- L (.-..)
                            when 12 => enc_pattern <= "00011"; enc_len <= 2; -- M (--)
                            when 13 => enc_pattern <= "00010"; enc_len <= 2; -- N (-.)
                            when 14 => enc_pattern <= "00111"; enc_len <= 3; -- O (---)
                            when 15 => enc_pattern <= "00110"; enc_len <= 4; -- P (.--.)
                            when 16 => enc_pattern <= "01101"; enc_len <= 4; -- Q (--.-)
                            when 17 => enc_pattern <= "00010"; enc_len <= 3; -- R (.-.)
                            when 18 => enc_pattern <= "00000"; enc_len <= 3; -- S (...)
                            when 19 => enc_pattern <= "00001"; enc_len <= 1; -- T (-)
                            when 20 => enc_pattern <= "00001"; enc_len <= 3; -- U (..-)
                            when 21 => enc_pattern <= "00001"; enc_len <= 4; -- V (...-)
                            when 22 => enc_pattern <= "00011"; enc_len <= 3; -- W (.--)
                            when 23 => enc_pattern <= "01001"; enc_len <= 4; -- X (-..-)
                            when 24 => enc_pattern <= "01011"; enc_len <= 4; -- Y (-.--)
                            when 25 => enc_pattern <= "00011"; enc_len <= 4; -- Z (--..)
                            when others => enc_len <= 0; -- No sound
                        end case;
                        
                        if enc_len > 0 then enc_state <= PLAY; end if;
                    end if;
                    
                when PLAY =>
                    auto_sound <= '1';
                    -- Read bit corresponding to current index
                    -- If we want to play ".-" (A, len=2):
                    -- idx 0: we want the dot (bit '0').
                    -- Let's simplify: we read from left to right on the bits defined above
                    if enc_pattern(enc_len - 1 - enc_idx) = '1' then
                        enc_target <= 3 * T_BEEP_DOT; -- Dash
                    else
                        enc_target <= T_BEEP_DOT;     -- Dot
                    end if;
                    
                    if enc_timer < enc_target then
                        enc_timer <= enc_timer + 1;
                    else
                        enc_timer <= 0;
                        auto_sound <= '0';
                        enc_state <= PAUSE;
                    end if;

                when PAUSE =>
                    auto_sound <= '0';
                    if enc_timer < T_BEEP_DOT then -- Inter-symbol silence
                        enc_timer <= enc_timer + 1;
                    else
                        enc_timer <= 0;
                        enc_idx <= enc_idx + 1;
                        enc_state <= NEXT_BIT;
                    end if;
                    
                when NEXT_BIT =>
                    if enc_idx < enc_len then
                        enc_state <= PLAY;
                    else
                        enc_state <= IDLE;
                    end if;
            end case;
        end if;
    end process;

    -- =========================================================================
    -- 4. UART TRANSMITTER
    -- =========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if uart_busy = '0' then
                uart_tx_reg <= '1';
                if uart_start = '1' then
                    uart_busy <= '1';
                    uart_bit_idx <= 0;
                    uart_timer <= 0;
                    uart_tx_reg <= '0'; -- Start
                end if;
            else
                if uart_timer < C_BAUD_RATE then
                    uart_timer <= uart_timer + 1;
                else
                    uart_timer <= 0;
                    uart_bit_idx <= uart_bit_idx + 1;
                    if uart_bit_idx = 0 then
                        uart_tx_reg <= uart_data(0);
                    elsif uart_bit_idx < 8 then
                        uart_tx_reg <= uart_data(uart_bit_idx);
                    elsif uart_bit_idx = 8 then
                        uart_tx_reg <= '1'; -- Stop
                    else
                        uart_busy <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    RsTx <= uart_tx_reg;

    -- =========================================================================
    -- 5. 7-SEGMENT DISPLAY
    -- =========================================================================
    process(clk)
        variable refresh_counter : integer range 0 to 200000 := 0;
        variable active_digit    : integer range 0 to 3 := 0;
        variable char_to_show    : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            refresh_counter := refresh_counter + 1;
            if refresh_counter = 0 then
                active_digit := active_digit + 1;
                if active_digit = 4 then active_digit := 0; end if;
                
                case active_digit is
                    when 0 => an <= "1110"; char_to_show := display_buffer(0);
                    when 1 => an <= "1101"; char_to_show := display_buffer(1);
                    when 2 => an <= "1011"; char_to_show := display_buffer(2);
                    when 3 => an <= "0111"; char_to_show := display_buffer(3);
                    when others => an <= "1111";
                end case;
                
                -- ASCII to Segments conversion (Active LOW : 0=ON)
                -- Segments mapping : "g f e d c b a"
                case char_to_show is
                    when X"41" => seg <= "0001000"; -- A
                    when X"42" => seg <= "0000011"; -- B (b)
                    when X"43" => seg <= "1000110"; -- C
                    when X"44" => seg <= "0100001"; -- D (d)
                    when X"45" => seg <= "0000110"; -- E
                    when X"46" => seg <= "0001110"; -- F
                    when X"47" => seg <= "0010000"; -- G (Looks like 9/g) or "1000010"
                    when X"48" => seg <= "0001001"; -- H
                    when X"49" => seg <= "1001111"; -- I
                    when X"4A" => seg <= "1100001"; -- J
                    when X"4B" => seg <= "1000111"; -- K (Use 'H' or specialized K) -> using 'H'-like
                    when X"4C" => seg <= "1000111"; -- L
                    when X"4D" => seg <= "0101010"; -- M (m - looks like n separated) -> Use "1010100" (n) or "0001000"(A)
                                                    -- let's use a double arch look: "0101010"
                    when X"4E" => seg <= "1001000"; -- N (n)
                    when X"4F" => seg <= "1000000"; -- O
                    when X"50" => seg <= "0001100"; -- P
                    when X"51" => seg <= "0011000"; -- Q (q)
                    when X"52" => seg <= "1001110"; -- R (r)
                    when X"53" => seg <= "0010010"; -- S (5)
                    when X"54" => seg <= "0000111"; -- T (t)
                    when X"55" => seg <= "1000001"; -- U
                    when X"56" => seg <= "1100011"; -- V (u) - no V, using U
                    when X"57" => seg <= "1010101"; -- W - no W
                    when X"58" => seg <= "0110111"; -- X - (H)
                    when X"59" => seg <= "0010001"; -- Y
                    when X"5A" => seg <= "0010010"; -- Z (2/S)
                    when X"20" => seg <= "1111111"; -- Space (Black)
                    when others => seg <= "0111110"; -- ?
                end case;
            end if;
        end if;
    end process;

end Behavioral;