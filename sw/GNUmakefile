CRL_VER	:= null

Q	:= @
O	:= o

CC	:= $(Q)Bgcc1
AS	:= $(Q)Bas
LD	:= $(Q)Bld
IMG	:= $(Q)Bimg
CPP	:= $(Q)cpp
PERL	:= $(Q)perl

CWARNS	:= -Wformat=2 -Wmissing-noreturn -Wwrite-strings -Wshadow \
	-Wno-unused-parameter -Wmissing-format-attribute -fno-builtin \
	-Wswitch-default -Wextra -Wmissing-prototypes \
	-Wmissing-declarations -Werror

INCLUDES	:= -Iinclude -I.
COMFLAGS	:= -fms-extensions -quiet -fno-builtin -msavertn -O2
CFLAGS		:= $(CWARNS) -std=c99 $(COMFLAGS) $(INCLUDES)
ASFLAGS		:= -datarota=2 $(INCLUDES)
LDFLAGS		:= -codebase=1000 -datafloat libc/base.o

include shared/Makefrag

LIBS	:= lib/longjump.S \
	lib/print.c \
	lib/msg.c \
	lib/meters.c \
	lib/barrier.c

LIBOBJS	:= $(LIBS)
LIBOBJS	:= $(patsubst %.S, $(O)/%.o, $(LIBOBJS))
LIBOBJS	:= $(patsubst %.c, $(O)/%.o, $(LIBOBJS))

OBJDIRS	:= $(O) $(O)/lib $(O)/shared $(O)/test $(O)/test/tsp

BINS	:= $(O)/hello.img  \
	$(O)/meterstest.img    \
	$(O)/bcasttest.img     \
	$(O)/barriertest.img   \
	$(O)/coherencytest.img \
	$(O)/bcastsim.img      \
	$(O)/seqtsp.img        \
	$(O)/partsp.img

all: xxlibc $(OBJDIRS) $(BINS)

xxlibc:
	cd libc; make

sim: $(O)/$(I).img
	cd ../hwv51/Simulation; make simulate IMG=../../sw/$(O)/$(I).img

$(O)/%.img: $(O)/%.out
	@echo "IMG       $@"
	$(IMG) $<

$(O)/%.out: $(O)/%.o $(SHAREDOBJS) $(LIBOBJS)
	@echo "LD       $@"
	$(LD) $(LDFLAGS) -map $@.map -o $@ $^ -Llibc -lc -lgcc

$(O)/%.out: $(O)/test/%.o $(SHAREDOBJS) $(LIBOBJS)
	@echo "LD       $@"
	$(LD) $(LDFLAGS) -map $@.map -o $@ $^ -Llibc -lc -lgcc

$(O)/%.out: $(O)/test/tsp/%.o $(SHAREDOBJS) $(LIBOBJS)
	@echo "LD       $@"
	$(LD) $(LDFLAGS) -map $@.map -o $@ $^ -Llibc -lc -lgcc

$(O)/%.o: $(O)/%.s
	@echo "AS       $@"
	$(AS) $(ASFLAGS) -lst $<.lst -o $@ -x $<

$(O)/%.s: %.S
	@echo "CPP      $@"
	$(CPP) -M -MT $@ -MF $@.d $<
	$(CPP) -o $@ $<

$(O)/%.o: %.s
	@echo "AS       $@"
	$(AS) $(ASFLAGS) -lst $(O)/$<.lst -o $@ -x $<

$(O)/%.s: %.c
	@echo "CC       $@"
	$(CC) $(CFLAGS) -o $@ -MT $@ -MD $@.d $<

.PRECIOUS: $(O)/%.o $(O)/%.out $(O)/%.s $(O)/%.d \
	   $(O)/shared/%.o $(O)/shared/%.s

copy: $(O)/$(I).img
	$(Q)$(COPY) $< $(TFTP)

clean:
	$(Q)rm -rf $(O)
	$(Q)cd libc; make clean
	$(Q)cd ../hwv51/Simulation/; make clean

$(OBJDIRS): 
	$(Q)mkdir -p $@

# This magic automatically generates makefile dependencies
# for header files included from C source files we compile,
# and keeps those dependencies up-to-date every time we recompile.
# See 'mergedep.pl' for more information.
$(O)/.deps: $(foreach dir, $(OBJDIRS), $(wildcard $(dir)/*.d))
	@mkdir -p $(@D)
	$(Q)$(PERL) mergedep.pl $@ $^

-include $(O)/.deps

