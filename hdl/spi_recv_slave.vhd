--! @title      SPI recevier (slave) with SCK lower than FPGA main clk
--! @file       spi_recv_slave.vhd
--! @author     Jeremy CHESLET
--! @date       05 Oct 2022
--! @version    1.0
--! @copyright
--! SPDX-FileCopyrightText: © 2022 Jeremy Cheslet <jcheslet@enseirb-matmeca.fr>
--! SPDX-License-Identifier: GPL-3.0-or-later
--! 
--! @brief 
--! * CLOCK_SPI = CLOCK_FREQUENCY / (2*CLOCK_SPI_DIVIDOR).
--! * **/!\ CLOCK_SPI_DIVIDOR MUST BE SUPERIOR OR EQUAL TO 2.**
--! * E.g.: a clock dividor of 10 will produce a 5 MHz SCK at 100 MHz.
--! * Module needs to be tested. There might be sync issue with a dividor of 2
--! * MISO is not buffered into FF before going into received shift register.
--! * **todo:** - Add generic to ignore receive or send data to save unused resources depending of the needs.
--!             - With a high enough dividor, it would be possible (better?) to directly put spi inputs in main clock domain.
--! 
--! 
--!	{ signal: [
--!		{ name: "clk",              wave: 'P..|..|..' },
--!		{ name: "data_in",          wave: 'x9x|..|..', data: ['S data 0']},
--!		{ name: "data_out",         wave: 'x..|5.|..', data: ['Master data 0']},
--!		{ name: "en_out",           wave: '0..|10|..' },
--!		{ name: "busy",             wave: '01.|..|0.', node: '.a.....b.' },
--!		{ name: "latency data_out", wave: '01.|.0|..', data: [], node: '.c...d...'}
--!	],
--!	edge: [
--! 	'a<->b (data_size * 2 * clock_dividor) + clock_dividor ccy',
--! 	'c<->d (data_size-1) * (2 * clock_dividor) + clock_dividor + 3 ccy',
--!	],
--! head:{
--! 	text:'SPI receiver (slave) module usage',
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
--! > **05 Oct 2022** : file creation (JC)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_recv_slave is
    generic(
        CLOCK_FREQUENCY     : integer                 := 100_000_000; --! main clock frequency
        CLOCK_SPI_DIVIDOR   : integer range 2 to 9999 :=          10; --! SCK clock dividor /!\ MUST BE SUPERIOR OR EQUAL TO 2
        DATA_SIZE           : integer                 :=           8  --! must be superior or equal to 3 to work correctly
    );
    port(
        clk     : in  std_logic;
        reset   : in  std_logic;

        data_in  : in  std_logic_vector(DATA_SIZE-1 downto 0);
        data_out : out std_logic_vector(DATA_SIZE-1 downto 0);
        en_out   : out std_logic;
        busy     : out std_logic;

        SS       : in  std_logic;
        MISO     : out std_logic;
        MOSI     : in  std_logic;
        SCK      : in  std_logic
    );
end spi_recv_slave;

architecture behavioral of spi_recv_slave is

    constant CLOCK_SPI_FREQUENCY         : integer := CLOCK_FREQUENCY / (2 * CLOCK_SPI_DIVIDOR); --! frequency of the SCK    
    constant FULL_CLOCK_SPI_CCY          : integer := CLOCK_FREQUENCY / CLOCK_SPI_FREQUENCY;     --! period of the SCK in CCY (clock cycles)
    constant QUARTER_CLOCK_SPI_CCY       : integer := FULL_CLOCK_SPI_CCY / 4;                    --! quarter of the period (in CCY)
    constant HALF_CLOCK_SPI_CCY          : integer := FULL_CLOCK_SPI_CCY / 2;                    --! half of the period (in CCY)
    constant THREE_QUARTER_CLOCK_SPI_CCY : integer := 3 * FULL_CLOCK_SPI_CCY / 4;                --! three-quarter of the period (in CCY)

    -- signal clk_spi_cnt : integer range -CLOCK_SPI_FREQUENCY to CLOCK_FREQUENCY+CLOCK_SPI_FREQUENCY-1;
    signal clk_spi_cnt : integer range 0 to FULL_CLOCK_SPI_CCY-1;
    
    signal ss_i    : std_logic;
    signal sending : std_logic; --! fsm / flag to indicate a transaction
    signal wait_ss : std_logic; --! wait ss_i to be set to stop the sending part

    -- SCK clock domain signals
    signal bit_cnt  : integer range 0 to DATA_SIZE-1 := DATA_SIZE-1;
    signal recv_reg_sr : std_logic_vector(DATA_SIZE-1 downto 0);
    signal fully_recv  : std_logic; --! set when the last been is received (will reset when a new transaction start)
    
    -- sending data signals
    signal send_reg_sr : std_logic_vector(DATA_SIZE-1 downto 0);
    signal miso_i      : std_logic;

    -- main clk domain receiving signals (shift register...)
    signal recv_reg_1   : std_logic_vector(DATA_SIZE-1 downto 0); --! serial clock domain
    signal recv_reg_2   : std_logic_vector(DATA_SIZE-1 downto 0); --! main clock domain
    signal recv_reg_3   : std_logic_vector(DATA_SIZE-1 downto 0); --! for synchornisation purpose with impulse
    signal en_out_reg_1 : std_logic; --! serial clock domain
    signal en_out_reg_2 : std_logic; --! main clock domain

    signal en_out_impl     : std_logic; --! impulse in main clock domain
    signal en_out_impl_mem : std_logic; --! impulse memory 

begin

    busy <= '1' when ss_i = '0' else '0';

    Process(clk)
    begin
        if rising_edge(clk) then
            ss_i <= SS;
        end if;
    end process;

    data_out <= recv_reg_3;
    Process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                recv_reg_1 <= (others => '0');
                recv_reg_2 <= (others => '0');
                recv_reg_3 <= (others => '0');
                
                en_out_reg_1 <= '0';
                en_out_reg_2 <= '0';
            else
                recv_reg_1 <= recv_reg_sr;
                recv_reg_2 <= recv_reg_1;
                recv_reg_3 <= recv_reg_2;

                en_out_reg_1 <= fully_recv;
                en_out_reg_2 <= en_out_reg_1;
            end if;
        end if;
    end process;

    -- sort of hot fix, must be tested
    en_out <= en_out_impl;
    Process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                en_out_impl     <= '0';
                en_out_impl_mem <= '0';
            elsif en_out_impl_mem = '0' and en_out_reg_2 = '1' then
                en_out_impl     <= '1';
                en_out_impl_mem <= '1';
            elsif en_out_impl_mem = '1' and en_out_reg_2 = '0' then
                en_out_impl     <= '0';
                en_out_impl_mem <= '0';
            else
                en_out_impl     <= '0';
            end if;
        end if;
    end process;

    -- Here we manage the received data
    Process(SCK, reset)
    begin
        if reset = '1' then
            recv_reg_sr <= (others => '0');
            fully_recv  <= '0';
            bit_cnt     <= DATA_SIZE-1;
        elsif rising_edge(SCK) then
            recv_reg_sr <= recv_reg_sr(recv_reg_sr'length-2 downto 0) & MOSI;
            if bit_cnt = 0 then
                fully_recv <= '1';
                bit_cnt    <= DATA_SIZE-1;
            else
                fully_recv <= '0';
                bit_cnt    <= bit_cnt - 1;
            end if;
        end if;
    end process;

    
    MISO <= miso_i;
    
    SPI_send_data_handler : Process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                sending     <= '0';
                wait_ss     <= '0';
                clk_spi_cnt <= FULL_CLOCK_SPI_CCY-2;
                send_reg_sr <= (others => '0');
                miso_i      <= '0';
            else
                -- Waiting start of communication from master... --------------
                if sending = '0' then
                    if ss_i = '0' then
                        sending     <= '1';
                        wait_ss     <= '0';
                        clk_spi_cnt <= FULL_CLOCK_SPI_CCY-2;
                        miso_i      <= data_in(data_in'length-1);
                        send_reg_sr <= data_in;
                    else
                        sending <= '0';
                        wait_ss <= '0';
                        miso_i  <= '0';
                    end if;
                elsif wait_ss = '1' then
                    miso_i <= '0';
                    if ss_i = '1' then
                        sending <= '0';
                        wait_ss <= '0';
                    end if;
                -- Transfer finished ------------------------------------------
                elsif en_out_impl = '1' then
                    wait_ss <= '1';
                -- Transfering data -------------------------------------------
                else
                    if clk_spi_cnt = 0 then
                        clk_spi_cnt <= FULL_CLOCK_SPI_CCY-2;
                    elsif clk_spi_cnt = THREE_QUARTER_CLOCK_SPI_CCY then
                        clk_spi_cnt <= clk_spi_cnt - 1;
                        send_reg_sr <= send_reg_sr(send_reg_sr'length-2 downto 0) & '0';
                        miso_i      <= send_reg_sr(send_reg_sr'length-1); -- ??
                    else
                        clk_spi_cnt <= clk_spi_cnt - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;


end behavioral;