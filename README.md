# olimexino-stm32-logger
Simple SD-Card serial data logger for the cheap olimexino stm32 with maple ide (EOL: http://docs.leaflabs.com/static.leaflabs.com/pub/leaflabs/maple-ide/index.html)

pin 8 as serial in (serial out not used)

files are written in the root directory as SERIAL00.LOG SERIAL01.LOG

if you remove the SD-Card data will be buffered and written if you insert a formatted SD-Card, no reboot required.

Blinking codes:

Yellow: data coming in on serial. Blinks with every \n

Green: write data to SD-card, toggles with every block write


Buffersize is 512 Bytes, if you disconnect the SD-card you will always loose < 512 bytes. TODO: A button is needed to flush the buffer and close
the file.


USB serial at 115200 shows problems and stats.


