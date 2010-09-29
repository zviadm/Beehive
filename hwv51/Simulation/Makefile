all: simulate

simulate: Mastercode.hex Slavecode.hex
	python img2hex.py hello.img > main.hex

Mastercode.hex: Master.s
	mono ../Basm/Basm.exe -code1 -data4 Master.s
	python mem2hex.py Mastercode.mem >Mastercode.hex
	python mem2hex.py Masterdata.mem >Masterdata.hex
	@rm -f Mastercode.mem Masterdata.mem

Slavecode.hex: Slave.s
	mono ../Basm/Basm.exe -code1 -data4 Slave.s
	python mem2hex.py Slavecode.mem >Slavecode.hex
	python mem2hex.py Slavedata.mem >Slavedata.hex
	@rm -f Slavecode.mem Slavedata.mem

clean::
	@rm -f *.mem *.hex *.lst
