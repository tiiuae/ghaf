  # For pin names look at gpio_40pin_header.png
  # some examples
  # GPIO09  PBB.00  - gpiochip 1, offset 8/0x08
  # GPIO08  PBB.01  - gpiochip 1, offset 9/0x09
  # GPIO17  PP.04  - gpiochip 0, offset 96/0x60
  # GPIO27  PN.01  - gpiochip 0, offset 85/0x55
  # GPIO35  PH.00  - gpiochip 0, offset 43/0x2B

  # chipnum='\x00'      # tegra234-gpio
  # chipnum='\x01'    # tegra234-gpio-aon
  lvl0='\x00'
  lvl1='\x01'
  n_a='\x00'
  offset='\x55'       # example: PN.01/GPIO27 has line offset hex '\x55'
  pad='\x00\x00\x00\x00'
  # chardev='/dev/gpio-host'
  chardev='/dev/gpio-guest'

  function res {
    signal='r'  # reserve line
    echo -n -e ${signal}${chipnum}${n_a}${offset}${pad} >> ${chardev}

    signal='o'  # set pin as output
    # this will also set a level
    echo -n -e ${signal}${chipnum}${lvl1}${offset}${pad} >> ${chardev}
  }

  function setlevel {
    echo -n -e ${signal}${chipnum}${level}${offset}${pad} >> ${chardev}
    sleep 0.0050
  }

  function free {
    signal='f'  # free line
    echo -n -e ${signal}${chipnum}${n_a}${offset}${pad} >> ${chardev}
  }

while true
do
  sleep 10
  echo -n '.'

  chipnum='\x01';offset='\x08'; res
  chipnum='\x01';offset='\x09'; res
  chipnum='\x00';offset='\x2B'; res
  chipnum='\x00';offset='\x55'; res

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

  chipnum='\x01';offset='\x02'; free 
  chipnum='\x01';offset='\x08'; free
  chipnum='\x00';offset='\x2B'; free
  chipnum='\x00';offset='\x55'; free

done
