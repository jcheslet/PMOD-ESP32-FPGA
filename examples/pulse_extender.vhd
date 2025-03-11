--! @title      Simplest pulse extender (input can be any length, i.e. 1 ccy to +inf ccys)
--! @file       pulse_extender.vhd
--! @author     Jeremy CHESLET
--! @date       15 Sep 2022
--! @version    1.0
--! @copyright
--! SPDX-FileCopyrightText: © 2022 Jeremy Cheslet <jcheslet@enseirb-matmeca.fr>
--! SPDX-License-Identifier: GPL-3.0-or-later
--! 
--! @brief
--! * Extend input pulse din (of any length) by EXTENTION_CCY
--! * No clock cycle delay (output dout is combinatory)
--! 
--! @details
--! > **15 Sep 2022** : file creation (JC)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pulse_extender is
    generic(
        EXTENTION_CCY : natural := 100_000_000;
        RESET_HIGH    : boolean := true
    );
    port(
        clk   : in  std_logic;
        reset : in  std_logic;
        
        din   : in  std_logic;
        dout  : out std_logic -- combinatory
    );
end pulse_extender;

architecture behavioral of pulse_extender is

    signal cnt : natural range 0 to EXTENTION_CCY-1;

begin

    dout <= '1' when cnt > 0 or din = '1' else '0';

    Process(clk)
    begin
        if rising_edge(clk) then
            if ((reset = '1' and RESET_HIGH) or (reset = '0' and not(RESET_HIGH))) then
                cnt  <= 0;
            elsif din = '1' then
                cnt <= EXTENTION_CCY-1;
            elsif cnt > 0 then
                cnt <= cnt - 1;
            end if;
        end if;
    end process;

end behavioral;