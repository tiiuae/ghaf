# this script does a smoketest of gpiod functions on output pins

# GPIO09  PBB.00  - gpiochip 1, offset 8/0x00
# GPIO08  PBB.01  - gpiochip 1, offset 9/0x09
# GPIO17  PP.04  - gpiochip 0, offset 96/0x60
# GPIO27  PN.01  - gpiochip 0, offset 85/0x55
# GPIO35  PH.00  - gpiochip 0, offset 43/0x2B

# > gpioset -h
#Options:
#  -h, --help:		display this message and exit
#  -v, --version:	display the version and exit
#  -l, --active-low:	set the line active state to low
#  -m, --mode=[exit|wait|time|signal] (defaults to 'exit'):
#		tell the program what to do after setting values
#  -s, --sec=SEC:	specify the number of seconds to wait (only valid for --mode=time)
#  -u, --usec=USEC:	specify the number of microseconds to wait (only valid for --mode=time)
#  -b, --background:	after setting values: detach from the controlling terminal
#
#Modes:
#  exit:		set values and exit immediately
#  wait:		set values and wait for user to press ENTER
#  time:		set values and sleep for a specified amount of time
#  signal:	set values and wait for SIGINT or SIGTERM
# makes a smoketest on gpio functions on output pins


function setgroup {
gpioset 1 8=$1
gpioset 0 85=$1
gpioset 1 9=$1
gpioset 0 43=$1
}

for i in $(seq 0 10)
do
setgroup 1
setgroup 0
done

## commands below works in host (depends on gpiod version)
#  gpioset -c0 -t10 8=0
#  gpioset -c0 -t10 85=0
#  gpioset -c0 -t10 9=0
#  gpioset -c0 -t10 43=0
