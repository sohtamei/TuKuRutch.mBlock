avrdude -Cavrdude.conf -v -patmega328p -cstk500v1 -PCOM10 -b19200 -e -Ulock:w:0x3F:m -Uefuse:w:0xFD:m -Uhfuse:w:0xDE:m -Ulfuse:w:0xFF:m 
avrdude -Cavrdude.conf -v -patmega328p -cstk500v1 -PCOM10 -b19200 -Uflash:w:remoconRobo.ino.with_bootloader.standard.hex:i -Ulock:w:0x0F:m 
