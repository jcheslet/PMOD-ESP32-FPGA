--! @title      Digilent Pmod ESP32 sending module
--! @file       Pmod_ESP32_sender.vhd
--! @author     Jeremy CHESLET
--! @date       21 June 2022
--! @version    2.0
--! @copyright
--! SPDX-FileCopyrightText: © 2022 Jeremy Cheslet <jcheslet@enseirb-matmeca.fr>
--! SPDX-License-Identifier: GPL-3.0-or-later
--! 
--! 
--! @brief 
--! * CLOCK_SPI = CLOCK_FREQUENCY / (2*CLOCK_SPI_DIVIDOR)
--! * **/!\ CLOCK DIVIDOR MUST BE SUPERIOR OR EQUAL TO 2**
--! * **Todo**: make spi handshake work in reverse: make this module busy as long as handshake from ESP32 is not set, so we avoid the data_in_buf buffer.
--! 
--! @details
--! > **21 Jun 2022** : file creation (JC)
--! > **04 Oct 2022** : Updating SPI (JC)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Pmod_ESP32_sender is
    generic(
        CLOCK_FREQUENCY   : integer := 100_000_000;
        CLOCK_SPI_DIVIDOR : integer range 2 to 9999 := 10; --! 10 ==> 5 MHz at 100 MHz /!\ MUST BE SUPERIOR OR EQUAL TO 2
        DATA_SIZE         : integer :=           8
    );
    port(
        clk         : in  std_logic;
        reset       : in  std_logic;

        -- PMOD IOs
        SS          : out std_logic;
        MISO        : in  std_logic;
        MOSI        : out std_logic;
        SCK         : out std_logic;
        GPI2        : in  std_logic; -- input from ESP32
        EN          : out std_logic;
        MODE_SELECT : out std_logic; 
        GPO32       : out std_logic; -- output to ESP32

        -- Data management
        handshake   : in  std_logic; -- Enable SPI 
        data_in     : in  std_logic_vector(DATA_SIZE-1 downto 0); -- data to send to ESP32 
        en_out      : out std_logic;                              -- impulse informing a new word has been received (can be ignored)
        data_out    : out std_logic_vector(DATA_SIZE-1 downto 0); -- data received (can be ignored)
        busy        : out std_logic
    );
end Pmod_ESP32_sender;

architecture behavioral of Pmod_ESP32_sender is

    type t_send_fsm is (off,
                        wait_ESP32, -- wait handshake from Pmod ESP32
                        send_data,
                        HD_latency);-- wait enough for handshake to be de-assert on the ESP32 side (to not send another word if )
                        -- over);
    signal send_fsm : t_send_fsm;
    signal ESP32_handshake_i           : std_logic;
    signal ESP32_handshake_mem         : std_logic;
    signal ESP32_handshake_rising_edge : std_logic;
    signal ESP32_ready : std_logic;

    signal en_spi       : std_logic;
    signal data_in_buf  : std_logic_vector(DATA_SIZE-1 downto 0);
    signal spi_data_out : std_logic_vector(DATA_SIZE-1 downto 0);
    signal spi_en_out   : std_logic;
    signal spi_busy     : std_logic;

    constant ESP_HANDSHAKE_DEASSERT_LATENCY_CCY : integer := CLOCK_FREQUENCY / 100_000; -- 10 us (chosen from experiment, around 4us but sometimes 6 to 8us)
    signal esp_hd_latency_cnt : integer range 0 to ESP_HANDSHAKE_DEASSERT_LATENCY_CCY-1;
    signal esp_hd_latency_end : std_logic;

begin

    en_out   <= spi_en_out;
    data_out <= spi_data_out;
    busy     <= '1' when handshake = '1' or send_fsm /= off else '0';

    GPO32 <= '0'; -- no use of GPIO (FPGA out -> ESP32 in).

    Process(clk)
    begin
        if rising_edge(clk) then
            ESP32_handshake_i <= GPI2;
        end if;
    end process;

    Process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                ESP32_ready <= '1'; -- start ready ?
            elsif ESP32_handshake_rising_edge = '1' then
                ESP32_ready <= '1';
            elsif send_fsm = send_data then -- slightly change FSM if this method is implemented
                ESP32_ready <= '0';
            end if;
        end if;
    end process;

    Process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                ESP32_handshake_mem         <= '0';
                ESP32_handshake_rising_edge <= '0';
            elsif ESP32_handshake_i = '1' and ESP32_handshake_mem = '0' then
                ESP32_handshake_mem         <= '1';
                ESP32_handshake_rising_edge <= '1';
            elsif ESP32_handshake_i = '0' and ESP32_handshake_mem = '1' then
                ESP32_handshake_mem         <= '0';
                ESP32_handshake_rising_edge <= '0';
            else
                ESP32_ready <= '0';
            end if;
        end if;
    end process;


    -- module FSM
    Process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                send_fsm <= off;
            else
                case send_fsm is
                    when off        => if handshake = '1'                            then send_fsm <= wait_ESP32; end if;
                    when wait_ESP32 => if ESP32_handshake_i = '1' and spi_busy = '0' then send_fsm <= send_data;  end if;
                    when send_data  => if en_spi  = '0'           and spi_busy = '0' then send_fsm <= HD_latency; end if;
                    when HD_latency => if esp_hd_latency_end = '1'                   then send_fsm <= off;        end if;
                end case;
            end if;
        end if;
    end process;

    Process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                data_in_buf <= (others => '0');
            elsif send_fsm = off and handshake = '1' then
                data_in_buf <= data_in;
            end if;
        end if;
    end process;

    Process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                en_spi <= '0';
            elsif send_fsm = wait_ESP32 and ESP32_handshake_i = '1' and spi_busy = '0' then
                en_spi <= '1';
            else
                en_spi <= '0';
            end if;
        end if;
    end process;

    Process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                esp_hd_latency_cnt <= 0;
                esp_hd_latency_end <= '0';
            elsif send_fsm = HD_latency then
                if esp_hd_latency_cnt > ESP_HANDSHAKE_DEASSERT_LATENCY_CCY-2 then
                    esp_hd_latency_cnt <= 0;
                    esp_hd_latency_end <= '1';
                else
                    esp_hd_latency_cnt <= esp_hd_latency_cnt + 1;
                    esp_hd_latency_end <= '0';
                end if;
            else
                esp_hd_latency_cnt <= 0;
                esp_hd_latency_end <= '0';
            end if;
        end if;
    end process;


    -------------------------------------------------------------------------
    -- SPI
    -------------------------------------------------------------------------
    spi_send_master_inst : entity work.spi_send_master
    generic map (
        CLOCK_FREQUENCY   => CLOCK_FREQUENCY,
        CLOCK_SPI_DIVIDOR => CLOCK_SPI_DIVIDOR,
        DATA_SIZE         => DATA_SIZE,
        SS_FULL_CCY       => false
    )
    port map (
        clk     => clk,
        reset   => reset,

        en_in    => en_spi,
        data_in  => data_in_buf,
        data_out => spi_data_out,
        en_out   => spi_en_out,
        busy     => spi_busy,

        SS   => SS,
        MISO => MISO,
        MOSI => MOSI,
        SCK  => SCK
    );

    -------------------------------------------------------------------------
    -- ESP32 configuration
    -------------------------------------------------------------------------
    EN          <= '1'; -- Enable ESP32
    MODE_SELECT <= '1'; -- Force SPI ('1') | UART ('0')
    
end behavioral;	  
