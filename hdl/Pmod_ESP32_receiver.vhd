--! @title      Digilent Pmod ESP32 receiving module
--! @file       Pmod_ESP32_receiver.vhd
--! @author     Jeremy CHESLET
--! @date       7 July 2022
--! @version    0.1
--! @copyright
--! SPDX-FileCopyrightText: © 2022 Jeremy Cheslet <jcheslet@enseirb-matmeca.fr>
--! SPDX-License-Identifier: GPL-3.0-or-later
--! 
--! 
--! @brief 
--! * CLOCK_SPI = CLOCK_FREQUENCY / (2*CLOCK_SPI_DIVIDOR)
--! * **/!\ CLOCK DIVIDOR MUST BE SUPERIOR OR EQUAL TO 2**
--! 
--! @details
--! > **07 Jul 2022** : file creation (JC)
--! > **04 Oct 2022** : Updating SPI (JC)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Pmod_ESP32_receiver is
    generic(
        CLOCK_FREQUENCY   : integer := 100_000_000;
        CLOCK_SPI_DIVIDOR : integer range 2 to 9999 := 10; --! 10 ==> 5 MHz at 100 MHz /!\ MUST BE SUPERIOR OR EQUAL TO 2
        DATA_SIZE         : integer :=           8
    );
    port(	
        clk         : in  std_logic;
        reset       : in  std_logic;

        -- PMOD IOs
        SS          : in  std_logic;    --! SPI: chip select
        MOSI        : in  std_logic;    --! SPI: Master Output Slave Input  (PMOD ESP32 is the master)
        MISO        : out std_logic;    --! SPI: Master Input  Slave Output (FPGA is the slave)
        SCK         : in  std_logic;    --! SPI: Serial clock
        GPI2        : in  std_logic;    --! General purpose Input from ESP32
        EN          : out std_logic;    --! Enable ESP32 microcontroler
        MODE_SELECT : out std_logic;    --! Select ESP32 communication mode (UART = '0', SPI = '1')
        GPO32       : out std_logic;    --! General Purpose Output to ESP32
        
        -- Data management
        handshake   : in  std_logic := '1'; -- Enable SPI (can be ignored)
        data_in     : in  std_logic_vector(DATA_SIZE-1 downto 0) := (others => '0'); -- data to send to ESP32 (can be ignored)
        en_out      : out std_logic;                                                 -- impulse informing a new word has been received
        data_out    : out std_logic_vector(DATA_SIZE-1 downto 0);                    -- data received
        busy        : out std_logic
    );
end Pmod_ESP32_receiver;

architecture behavioral of Pmod_ESP32_receiver is

    signal handshake_i : std_logic; -- real handshake, set low when SS is low to trigger interruption on ESP32 side
    signal ss_i        : std_logic;

    signal spi_data_out : std_logic_vector(DATA_SIZE-1 downto 0);
    signal spi_en_out   : std_logic;
    signal spi_busy     : std_logic;

begin

    en_out <= spi_en_out;
    data_out <= spi_data_out;
    busy     <= '1' when spi_busy = '0' else '0';

    GPO32 <= handshake_i;

    Process(clk)
    begin
        if rising_edge(clk) then
            ss_i <= SS;
        end if;
    end process;

    -- Handshake management - needed to trigger ESP32 handshake ISR (for the semaphore)
    Process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                handshake_i <= '0';
            elsif ss_i = '0' then
                handshake_i <= '0';
            else
                handshake_i <= '1'; -- handshake;
            end if;
        end if;
    end process;

    -------------------------------------------------------------------------
    -- SPI
    -------------------------------------------------------------------------
    spi_recv_slave_inst : entity work.spi_recv_slave
    generic map (
        CLOCK_FREQUENCY   => CLOCK_FREQUENCY,
        CLOCK_SPI_DIVIDOR => CLOCK_SPI_DIVIDOR,
        DATA_SIZE         => DATA_SIZE
    )
    port map (
        clk   => clk,
        reset => reset,

        data_in  => data_in,
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
