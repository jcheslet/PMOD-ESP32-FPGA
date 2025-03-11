--! @title      SPI send (master) with SCK lower than FPGA main clk
--! @file       spi_send_master.vhd
--! @author     Jeremy CHESLET
--! @date       04 Oct 2022
--! @version    1.0
--! @copyright
--! SPDX-FileCopyrightText: © 2022 Jeremy Cheslet <jcheslet@enseirb-matmeca.fr>
--! SPDX-License-Identifier: GPL-3.0-or-later
--! 
--! @brief 
--! * CLOCK_SPI = CLOCK_FREQUENCY / (2*CLOCK_SPI_DIVIDOR).
--! * **/!\ CLOCK_SPI_DIVIDOR MUST BE SUPERIOR OR EQUAL TO 2.**
--! * E.g.: a clock dividor of 10 will produce a 5 MHz SCK at 100 MHz.
--! * MISO is not buffered into FF before going into received shift register.
--! * **todo:** - Add generic to ignore receive or send data to save unused
--!               resources depending of the needs.
--! 
--! 
--!	{ signal: [
--!		{ name: "clk",              wave: 'P..|..|..' },
--!		{ name: "en_in",            wave: '010|..|..' },
--!		{ name: "data_in",          wave: 'x9x|..|..', data: ['M data 0']},
--!		{ name: "data_out",         wave: 'x..|5.|..', data: ['slave data 0']},
--!		{ name: "en_out",           wave: '0..|10|..' },
--!		{ name: "busy",             wave: '01.|..|0.', node: '.a.....b.' },
--!		{ name: "latency data_out", wave: '01.|.0|..', data: [], node: '.c...d...'}
--!	],
--!	edge: [
--! 	'a<->b (data_size * 2 * clock_dividor) + clock_dividor + 1 ccy',
--! 	'c<->d (data_size-1) * (2 * clock_dividor) + clock_dividor + 2 ccy',
--!	],
--! head:{
--! 	text:'SPI send (master) module usage',
--! 	tick:0,	
--! },
--! foot:{
--! 	text:'ccy : clock cycles',
--! 	tick:0,	
--! },
--!		config: { hscale: 2 }
--!	}
--!
--!
--! @details
--! > **04 Oct 2022** : file creation (JC)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_send_master is
    generic(
        CLOCK_FREQUENCY     : integer                 := 100_000_000; --! main clock frequency
        CLOCK_SPI_DIVIDOR   : integer range 2 to 9999 :=          10; --! SCK clock dividor /!\ MUST BE SUPERIOR OR EQUAL TO 2
        DATA_SIZE           : integer                 :=           8; --! size of the word to send/receive
        SS_FULL_CCY         : boolean                 := false        --! wait an extra half period of SCK before de-assert SS
    );
    port(	
        clk      : in  std_logic; --! main clock
        reset    : in  std_logic; --! reset high

        en_in    : in  std_logic;                              --! enable SPI line to send data_in
        data_in  : in  std_logic_vector(DATA_SIZE-1 downto 0); --! data to send
        data_out : out std_logic_vector(DATA_SIZE-1 downto 0); --! receive data
        en_out   : out std_logic;                              --! impulsion to validate received data
        busy     : out std_logic;                              --! inform about the avaibility of the SPI line

        SS       : out std_logic; --! Slave Select
        MISO     : in  std_logic; --! Master Input Slave Output
        MOSI     : out std_logic; --! Master Output Slave Input
        SCK      : out std_logic  --! Serial Clock
    );
end spi_send_master;

architecture behavioral of spi_send_master is


    constant CLOCK_SPI_FREQUENCY         : integer := CLOCK_FREQUENCY / (2 * CLOCK_SPI_DIVIDOR); --! frequency of the SCK
    constant FULL_CLOCK_SPI_CCY          : integer := CLOCK_FREQUENCY / CLOCK_SPI_FREQUENCY;     --! period of the SCK in CCY (clock cycles)
    constant QUARTER_CLOCK_SPI_CCY       : integer := FULL_CLOCK_SPI_CCY / 4;                    --! quarter of the period (in CCY)
    constant HALF_CLOCK_SPI_CCY          : integer := FULL_CLOCK_SPI_CCY / 2;                    --! half of the period (in CCY)
    constant THREE_QUARTER_CLOCK_SPI_CCY : integer := 3 * FULL_CLOCK_SPI_CCY / 4;                --! three-quarter of the period (in CCY)
    -- signal clk_spi_cnt : integer range -CLOCK_SPI_FREQUENCY to CLOCK_FREQUENCY+CLOCK_FREQUENCY_SPI;

    signal clk_spi_cnt : integer range 0 to FULL_CLOCK_SPI_CCY-1; --! decremental counter which determine all the timing
    signal sck_i       : std_logic;                               --! value: 1 -> 1/2: '0', 1/2 -> 0: '1'
    
    signal sending : std_logic; --! state of the module
    signal over    : std_logic; --! impulsion to tell user that a full word has been received
    signal ss_i    : std_logic; --! Slave Select line

    signal bit_cnt : integer range 0 to DATA_SIZE; --! counter used to determine when to de-assert SS

    signal send_reg_sr : std_logic_vector(DATA_SIZE-1 downto 0); --! shift register to send data onto MOSI line
    signal mosi_i      : std_logic;                              --! (wire) SPI master output line
    signal recv_reg_sr : std_logic_vector(DATA_SIZE-1 downto 0); --! shift register to receive data from MISO line

begin

    busy <= '1' when en_in = '1' or sending = '1' else '0'; 

    SS   <= ss_i;
    MOSI <= mosi_i;
    SCK  <= sck_i;

    SPI_handler : Process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                sending     <= '0';
                over        <= '0';
                ss_i        <= '1';
                clk_spi_cnt <= FULL_CLOCK_SPI_CCY-1;
                sck_i       <= '0';
                bit_cnt     <= DATA_SIZE;
                send_reg_sr <= (others => '0');
                mosi_i      <= '0';
                recv_reg_sr <= (others => '0');
            else
                -- Waiting enable from user...
                if sending = '0' then
                    if en_in = '1' then
                        sending     <= '1';
                        ss_i        <= '0';
                        over        <= '0';
                        clk_spi_cnt <= FULL_CLOCK_SPI_CCY-1;
                        sck_i       <= '0';
                        bit_cnt     <= DATA_SIZE;
                        send_reg_sr <= data_in;
                    else
                        sending <= '0';
                        over    <= '0';
                        ss_i    <= '1';
                        sck_i   <= '0';
                    end if;

                -- Last part: all data transfered, wait half spi period before de-assert SS
                elsif bit_cnt = 0 then
                    over <= '0';
                    if (clk_spi_cnt = HALF_CLOCK_SPI_CCY and not(SS_FULL_CCY)) or (clk_spi_cnt = 0 and SS_FULL_CCY) then
                        sending <= '0';
                        ss_i    <= '1';
                    else
                        clk_spi_cnt <= clk_spi_cnt - 1;
                    end if;

                -- Transfering data
                else
                    if clk_spi_cnt = 0 then
                        over        <= '0';
                        sck_i       <= '0';
                        bit_cnt     <= bit_cnt - 1;
                        clk_spi_cnt <= FULL_CLOCK_SPI_CCY-1;

                    elsif clk_spi_cnt = HALF_CLOCK_SPI_CCY then
                        if bit_cnt = 1 then
                            over <= '1';
                        else
                            over <= '0';
                        end if;
                        clk_spi_cnt <= clk_spi_cnt - 1;
                        sck_i       <= '1';
                        recv_reg_sr <= recv_reg_sr(recv_reg_sr'length-2 downto 0) & MISO;

                    elsif clk_spi_cnt = THREE_QUARTER_CLOCK_SPI_CCY then
                        over        <= '0';
                        clk_spi_cnt <= clk_spi_cnt - 1;
                        send_reg_sr <= send_reg_sr(send_reg_sr'length-2 downto 0) & '0';
                        mosi_i      <= send_reg_sr(send_reg_sr'length-1);
                    else
                        over        <= '0';
                        clk_spi_cnt <= clk_spi_cnt - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    Received_data_handler : Process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                data_out <= (others => '0');
                en_out   <= '0';
            elsif over = '1' then
                data_out <= recv_reg_sr;
                en_out   <= '1';
            else
                en_out   <= '0';
            end if;
        end if;
    end process;
    
end behavioral;	  
