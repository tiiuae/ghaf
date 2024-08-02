# For pin names look at gpio_40pin_header.pn8
# some examples
# GPIO09  PBB.00  - gpiochip 1, offset 8/0x00
# GPIO08  PBB.01  - gpiochip 1, offset 9/0x09
# GPIO17  PP.04  - gpiochip 0, offset 96/0x60
# GPIO27  PN.01  - gpiochip 0, offset 85/0x55
# GPIO35  PH.00  - gpiochip 0, offset 43/0x2B

chipnum='\x00'      # tegra234-gpio
# chipnum='\x01'    # tegra234-gpio-aon
offset='\x55'       # PN.01/GPIO27 # line offset in hex

lvl0='\x00'
lvl1='\x01'
n_a='\x00'

# wait_time='0.0005'
wait_time='0'
chardev=$(ls /dev/gpio-[gh]*st)
echo -e "using ${chardev}\n"

function read_ret {
  echo "retval:"
  dd if=${chardev} bs=1 count=4 | hexdump -C
}

function res {
  signal='r'  # reserve line
  echo -n -e ${chipnum}${signal}${n_a}${offset} >> ${chardev}

  read_ret

  signal='o'  # set pin as output
  # this will also set a level
  echo -n -e ${chipnum}${signal}${lvl1}${offset} >> ${chardev}

  read_ret
}

function setlevel {
  signal='s'
  echo -n -e ${chipnum}${signal}${level}${offset} >> ${chardev}
  sleep ${wait_time}
}

function getlevel {
  signal='g'  # set pin as output
  echo -n -e ${chipnum}${signal}${level}${offset} >> ${chardev}
  sleep ${wait_time}

  read_ret
}

function freeline {
  signal='f'  # free line
  echo -n -e ${chipnum}${signal}${n_a}${offset} >> ${chardev}
}

chipnum='\x01';offset='\x08'; res
chipnum='\x00';offset='\x55'; res
chipnum='\x01';offset='\x09'; res
chipnum='\x00';offset='\x2B'; res

i=10;
signal='s'  # set level
while [ $i -gt 0 ]
  do let i=$i-1

    level='\x01'
    chipnum='\x01';offset='\x08'; setlevel
    chipnum='\x00';offset='\x55'; setlevel
    chipnum='\x01';offset='\x09'; setlevel
    chipnum='\x00';offset='\x2B'; setlevel

    level='\x00'
    chipnum='\x01';offset='\x08'; setlevel
    chipnum='\x00';offset='\x55'; setlevel
    chipnum='\x01';offset='\x09'; setlevel
    chipnum='\x00';offset='\x2B'; setlevel

  done

chipnum='\x01';offset='\x08'; freeline
chipnum='\x00';offset='\x55'; freeline
chipnum='\x01';offset='\x09'; freeline
chipnum='\x00';offset='\x2B'; freeline
