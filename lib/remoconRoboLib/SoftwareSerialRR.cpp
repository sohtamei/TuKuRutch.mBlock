/*
SoftwareSerial.cpp (formerly NewSoftSerial.cpp) - 
Multi-instance software serial library for Arduino/Wiring
-- Interrupt-driven receive and other improvements by ladyada
   (http://ladyada.net)
-- Tuning, circular buffer, derivation from class Print/Stream,
   multi-instance support, porting to 8MHz processors,
   various optimizations, PROGMEM delay tables, inverse logic and 
   direct port writing by Mikal Hart (http://www.arduiniana.org)
-- Pin change interrupt macros by Paul Stoffregen (http://www.pjrc.com)
-- 20MHz processor support by Garrett Mace (http://www.macetech.com)
-- ATmega1280/2560 support by Brett Hagman (http://www.roguerobotics.com/)

This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

The latest version of this library can always be found at
http://arduiniana.org.
*/

#include <Arduino.h>
#include "SoftwareSerialRR.h"
#include <util/delay_basic.h>

/* static */ 
inline void SoftwareSerialRR::tunedDelay(uint16_t delay) { 
  _delay_loop_2(delay);
}

SoftwareSerialRR::SoftwareSerialRR(uint8_t tx, long speed)
{
  digitalWrite(tx, HIGH);
  pinMode(tx, OUTPUT);
  _transmitBitMask = digitalPinToBitMask(tx);
  _transmitPortRegister = portOutputRegister(digitalPinToPort(tx));

  // Precalculate the various delays, in number of 4-cycle delays
  uint16_t bit_delay = (F_CPU / speed) / 4;

  // 12 (gcc 4.8.2) or 13 (gcc 4.3.2) cycles from start bit to first bit,
  // 15 (gcc 4.8.2) or 16 (gcc 4.3.2) cycles between bits,
  // 12 (gcc 4.8.2) or 14 (gcc 4.3.2) cycles from last bit to stop bit
  // These are all close enough to just use 15 cycles, since the inter-bit
  // timings are the most critical (deviations stack 8 times)
  _tx_delay = bit_delay - 15 / 4;
}

SoftwareSerialRR::~SoftwareSerialRR()
{
}

size_t SoftwareSerialRR::write(uint8_t b)
{
  if (_tx_delay == 0) {
    return 0;
  }

  // By declaring these as local variables, the compiler will put them
  // in registers _before_ disabling interrupts and entering the
  // critical timing sections below, which makes it a lot easier to
  // verify the cycle timings
  volatile uint8_t *reg = _transmitPortRegister;
  uint8_t oldSREG = SREG;

  cli();  // turn off interrupts for a clean txmit

  // Write the start bit
  *reg &= ~_transmitBitMask;

  tunedDelay(_tx_delay);

  // Write each of the 8 bits
  for (uint8_t i = 8; i > 0; --i)
  {
    if (b & 1) // choose bit
      *reg |= _transmitBitMask; // send 1
    else
      *reg &= ~_transmitBitMask; // send 0

    tunedDelay(_tx_delay);
    b >>= 1;
  }

  // restore pin to natural state
  *reg |= _transmitBitMask;

  SREG = oldSREG; // turn interrupts back on
  tunedDelay(_tx_delay);
  
  return 1;
}
