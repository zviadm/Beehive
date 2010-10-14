BEECTL = beectl.csail.mit.edu:

MEM = Basm/Mastercode.mem Basm/Masterdata.mem Basm/Slavecode.mem Basm/Slavedata.mem \
      Basm/RISCtestcode.mem Basm/RISCtestdata.mem Basm/CopyDCcode.mem

nCores = $(shell grep "parameter nCores = " < RISCsrc/RISCtop.v | sed 's/.*nCores = \([0-9]*\).*/\1/')

all: risc$(nCores).bit

risc3.bit: RISC/RISCtop.bit $(MEM)
	data2mem -bm mem/memX3a_bd.bmm -bt RISC/RISCtop.bit \
	 -bd Basm/RISCtestcode.mem tag ram3 \
	 -bd Basm/RISCtestdata.mem tag ram4 \
	 -o b risc1.bit
	data2mem -bm mem/memX3a_bd.bmm -bt risc1.bit \
	 -bd Basm/CopyDCcode.mem tag ram5 \
	 -o b risc2.bit
	data2mem -bm mem/memX3a_bd.bmm -bt risc2.bit \
	 -bd Basm/Masterdata.mem tag ram7 \
	 -bd Basm/Mastercode.mem tag ram8 \
	 -bd Basm/Slavedata.mem tag ram9 ram11 \
	 -bd Basm/Slavecode.mem tag ram10 ram12 \
	 -o b risc3.bit
	rm risc1.bit risc2.bit
	mv risc3.bit Bits/
	scp Bits/risc3.bit $(BEECTL)

risc5.bit: RISC/RISCtop.bit $(MEM)
	data2mem -bm mem/memX5a_bd.bmm -bt RISC/RISCtop.bit \
	 -bd Basm/RISCtestcode.mem tag ram3 \
	 -bd Basm/RISCtestdata.mem tag ram4 \
	 -o b risc1.bit
	data2mem -bm mem/memX5a_bd.bmm -bt risc1.bit \
	 -bd Basm/CopyDCcode.mem tag ram5 \
	 -o b risc2.bit
	data2mem -bm mem/memX5a_bd.bmm -bt risc2.bit \
	 -bd Basm/Masterdata.mem tag ram7 \
	 -bd Basm/Mastercode.mem tag ram8 \
	 -bd Basm/Slavedata.mem tag ram9 ram11 ram13 ram15 \
	 -bd Basm/Slavecode.mem tag ram10 ram12 ram14 ram16 \
	 -o b risc.bit
	rm risc1.bit risc2.bit
	mv risc5.bit Bits/
	scp Bits/risc5.bit $(BEECTL)

risc13.bit: RISC/RISCtop.bit $(MEM)
	data2mem -bm mem/memX13a_bd.bmm -bt RISC/RISCtop.bit \
	 -bd Basm/RISCtestcode.mem tag ram3 \
	 -bd Basm/RISCtestdata.mem tag ram4 \
	 -o b risc1.bit
	data2mem -bm mem/memX13a_bd.bmm -bt risc1.bit \
	 -bd Basm/CopyDCcode.mem tag ram5 \
	 -o b risc2.bit
	data2mem -bm mem/memX13a_bd.bmm -bt risc2.bit \
	 -bd Basm/Masterdata.mem tag ram7 \
	 -bd Basm/Mastercode.mem tag ram8 \
	 -bd Basm/Slavedata.mem tag  ram9 ram11 ram13 ram15 ram17 ram19 ram21 ram23 ram25 ram27 ram29 ram31 \
	 -bd Basm/Slavecode.mem tag ram10 ram12 ram14 ram16 ram18 ram20 ram22 ram24 ram26 ram28 ram30 ram32 \
	 -o b risc13.bit
	rm risc1.bit risc2.bit
	mv risc13.bit Bits/
	scp Bits/risc13.bit $(BEECTL)

Basm/Mastercode.mem Basm/Masterdata.mem: Basm/Master.s
	mono Basm/Basm.exe -code1 -data4 Basm/Master.s

Basm/Slavecode.mem Basm/Slavedata.mem: Basm/Slave.s
	mono Basm/Basm.exe -code1 -data4 Basm/Slave.s

Basm/RISCtestcode.mem Basm/RISCtestdata.mem: Basm/RISCtest.s
	mono Basm/Basmv1.exe -code1 -data1 Basm/RISCtest.s

Basm/CopyDCcode.mem: Basm/CopyDC.s
	mono Basm/Basmv1.exe -code1 -data1 Basm/CopyDC.s

clean:
	@rm Basm/*.mem Basm/*.lst 
