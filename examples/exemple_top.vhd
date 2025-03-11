--! @title      Example top entity for WiFi or Bluetooth communication using Pmod ESP32
--! @file       exemple_top.vhd
--! @author     Jeremy CHESLET
--! @date       28 Sep 2022
--! @version    1.0
--! @copyright
--! SPDX-FileCopyrightText: © 2022 Jeremy Cheslet <jcheslet@enseirb-matmeca.fr>
--! SPDX-License-Identifier: GPL-3.0-or-later
--!
--! @brief
--! * Receive data from ESP32, process something with it, then send back data on next transfer with ESP32
--! * ESP32 is master
--! * CLOCK_SPI = CLOCK_FREQUENCY / (2*CLOCK_SPI_DIVIDOR)
--! * **/!\ CLOCK DIVIDOR MUST BE SUPERIOR OR EQUAL TO 2**
--!
--! @details
--! > **28 Sep 2022** : file creation (JC)
--! > **20 Oct 2022** : update ESP32 module & add IR sensors(JC)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity exemple_top is
    generic(
        CLOCK_FREQUENCY   : natural := 100_000_000;
        CLOCK_SPI_DIVIDOR : natural range 2 to 9999 := 8
    );
    port(
        clk          : in  std_logic;
        reset        : in  std_logic;

        -- Pmod ESP32 IOs
        SS           : in  std_logic;
        MOSI         : in  std_logic;
        MISO         : out std_logic;
        SCK          : in  std_logic;
        GPI2         : in  std_logic;
        EN           : out std_logic;
        MODE_SELECT  : out std_logic;
        GPO32        : out std_logic;

        -- Debugs
        leds         : out std_logic_vector(1 downto 0)
    );
end exemple_top;

architecture behavioral of exemple_top is
    -------------------------------------------------------------------------
    -- Pmod ESP32 receiver
    -------------------------------------------------------------------------
    constant ESP32_DATA_SIZE : natural := 8;
    signal esp_handshake   : std_logic := '1';
    signal esp_data_in     : std_logic_vector(ESP32_DATA_SIZE-1 downto 0);
    signal esp_data_out    : std_logic_vector(ESP32_DATA_SIZE-1 downto 0);
    signal esp_recv_en_out : std_logic;
    signal esp_busy        : std_logic;

    -------------------------------------------------------------------------
    -- Black box
    -------------------------------------------------------------------------
    constant BB_DATA_SIZE       : natural := ESP32_DATA_SIZE;
    constant BB_PROCESS_LATENCY : natural range 1 to 99 := 5;

    signal bb_en_in   : std_logic;
    signal bb_data_in : std_logic_vector(BB_DATA_SIZE-1 downto 0);

    signal bb_process_en  : std_logic_vector(BB_PROCESS_LATENCY-1 downto 0);
    signal bb_process_tmp : std_logic_vector(BB_DATA_SIZE-1 downto 0);

    signal bb_en_out   : std_logic;
    signal bb_data_out : std_logic_vector(BB_DATA_SIZE-1 downto 0);

    -------------------------------------------------------------------------
    -- debug signals
    -------------------------------------------------------------------------
    constant LED_PULSE_LENGTH : natural := CLOCK_FREQUENCY / 100; -- 1 ms
    signal esp_recv_en_extended     : std_logic;
    signal bb_process_over_extended : std_logic;

begin

-----------------------------------------------------------------------------------------
--
--  ███████ ███████ ██████  ██████  ██████      ██████  ███████  ██████ ██    ██
--  ██      ██      ██   ██      ██      ██     ██   ██ ██      ██      ██    ██
--  █████   ███████ ██████   █████   █████      ██████  █████   ██      ██    ██
--  ██           ██ ██           ██ ██          ██   ██ ██      ██       ██  ██
--  ███████ ███████ ██      ██████  ███████     ██   ██ ███████  ██████   ████
--
-----------------------------------------------------------------------------------------
    Pmod_ESP32_receiver_inst : entity work.Pmod_ESP32_receiver
    generic map (
        CLOCK_FREQUENCY   => CLOCK_FREQUENCY,
        CLOCK_SPI_DIVIDOR => CLOCK_SPI_DIVIDOR,
        DATA_SIZE         => ESP32_DATA_SIZE
    )
    port map (
        clk         => clk,
        reset       => reset,

        SS          => SS,
        MOSI        => MOSI,
        MISO        => MISO,
        SCK         => SCK,
        GPI2        => GPI2,
        EN          => EN,
        MODE_SELECT => MODE_SELECT,
        GPO32       => GPO32,

        handshake   => esp_handshake,
        data_in     => esp_data_in,
        en_out      => esp_recv_en_out,
        data_out    => esp_data_out,
        busy        => esp_busy
    );

    esp_handshake <= '1';

    Process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                bb_en_in   <= '0';
                bb_data_in <= (others => '0');
            else
                bb_en_in   <= esp_recv_en_out;
                bb_data_in <= esp_data_out;
            end if;
        end if;
    end process;

-----------------------------------------------------------------------------------------
--
--  ██████  ██       █████   ██████ ██   ██     ██████   ██████  ██   ██
--  ██   ██ ██      ██   ██ ██      ██  ██      ██   ██ ██    ██  ██ ██
--  ██████  ██      ███████ ██      █████       ██████  ██    ██   ███
--  ██   ██ ██      ██   ██ ██      ██  ██      ██   ██ ██    ██  ██ ██
--  ██████  ███████ ██   ██  ██████ ██   ██     ██████   ██████  ██   ██
--
-- User part
-----------------------------------------------------------------------------------------

    Process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                bb_process_en  <= (others => '0');
                bb_process_tmp <= (others => '0');
            else
                if BB_PROCESS_LATENCY = 1 then
                    bb_process_en(0) <= bb_en_in;
                else 
                    bb_process_en <= bb_process_en(bb_process_en'length-2 downto 0) & bb_en_in;
                end if;

                if bb_en_in = '1' then
                    bb_process_tmp <= bb_data_in;
                end if;
            end if;
        end if;
    end process;

    Process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                bb_en_out   <= '0';
                bb_data_out <= (others => '0');
            elsif bb_process_en(bb_process_en'left) = '1' then
                bb_en_out   <= '1';
                bb_data_out <= bb_process_tmp; 
            end if;
        end if;
    end process;


-----------------------------------------------------------------------------------------
--
--  ███████ ███████ ██████  ██████  ██████      ███████ ███████ ███    ██ ██████
--  ██      ██      ██   ██      ██      ██     ██      ██      ████   ██ ██   ██
--  █████   ███████ ██████   █████   █████      ███████ █████   ██ ██  ██ ██   ██
--  ██           ██ ██           ██ ██               ██ ██      ██  ██ ██ ██   ██
--  ███████ ███████ ██      ██████  ███████     ███████ ███████ ██   ████ ██████
--
-----------------------------------------------------------------------------------------

    Process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                esp_data_in <= (others => '0');
            elsif esp_recv_en_out = '1' then  -- reset data_in buffer after being sent (sent when new buffer is received)
                esp_data_in <= (others => '0');
            elsif bb_en_out = '1' then
                esp_data_in <= bb_data_out;
            end if;
        end if;
    end process;

-----------------------------------------------------------------------------------------
--
--  ██████  ███████ ██████  ██    ██  ██████
--  ██   ██ ██      ██   ██ ██    ██ ██
--  ██   ██ █████   ██████  ██    ██ ██   ███
--  ██   ██ ██      ██   ██ ██    ██ ██    ██
--  ██████  ███████ ██████   ██████   ██████
--
-----------------------------------------------------------------------------------------

    esp_recv_pulse_extender : entity work.pulse_extender
        generic map (
            EXTENTION_CCY => LED_PULSE_LENGTH
        )
        port map (
            clk   => clk,
            reset => reset,
            din   => esp_recv_en_out,
            dout  => esp_recv_en_extended
        );

    esp_send_pulse_extender : entity work.pulse_extender
        generic map (
            EXTENTION_CCY => LED_PULSE_LENGTH
        )
        port map (
            clk   => clk,
            reset => reset,
            din   => bb_en_out,
            dout  => bb_process_over_extended
        );

    leds(0) <= esp_recv_en_extended;
    leds(1) <= bb_process_over_extended;


end behavioral;