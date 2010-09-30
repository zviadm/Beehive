all: base libc.a libbee.a
build: base libc.a libbee.a

.SUFFIXES:
%.o: %.as
	Bas -datarota=2 -lst $*.lst -I../include $<

%.o: %.s
	Bas -x -datarota=2 -lst $*.lst -I../include $<

%.s: %.c
	Bgcc1 -quiet ${BGCCFLAGS} -g -fno-builtin -std=c99 -O2 -dp -I../include $<

%.s: %.i
	Bgcc1 -quiet ${BGCCFLAGS} -g -fno-builtin -std=c99 -O2 -dp -I../include $<

%.img: %.out
	Bimg $<

BASEOBJS=base.o basehs.o basemc.o

.PHONY: base
base: $(BASEOBJS)

LIBBEEOBJS_S= \
	bee_core_i.o \
	bee_core_n.o \
	bee_core_eth.o \
	bee_dcache_flush_all.o \
	bee_dcache_empty_all.o \
	bee_dcache_command_internal.o \
	bee_msg_send_w.o \
	bee_msg_poll_w.o \
	bee_lock_cacq.o \
	bee_lock_rel.o

LIBBEEOBJS_C= \
	bee_dcache_flush_rgn.o \
	bee_dcache_empty_rgn.o

${LIBBEEOBJS_S:.o=.s} \
${LIBBEEOBJS_C:.o=.c} \
: beegen.perl
	perl beegen.perl

LIBBEEOBJS= ${LIBBEEOBJS_S} ${LIBBEEOBJS_C}




LIBCOBJS=\
	putchar.o \
	puts.o \
	getchar.o \
	availc.o \
	doprnt.o \
	printf.o \
	sprintf.o \
	\
	abort.o \
	malloc.o \
	malloc1.o \
	rand.o \
	\
	bzero.o \
	bcopy.o \
	\
	memchr.o \
	memcmp.o \
	memmove.o \
	memcpy.o \
	memset.o \
	\
	strlen.o \
	strcpy.o \
	strncpy.o \
	strstr.o \
	\
	ffo.o


libc.a: ${LIBCOBJS} ${LIBBEEOBJS}
	rm -fr libc.a
	Bar crv libc.a ${LIBCOBJS} ${LIBBEEOBJS}


libbee.a: ${LIBBEEOBJS}
	rm -fr libbee.a
	Bar crv libbee.a ${LIBBEEOBJS}


clean:
	for v in $(BASEOBJS); do mv "$$v" "$$v.save"; done
	rm -fr *.s *.o *.lst *~ check.txt
	rm -fr ${LIBBEEOBJS_S:.o=.s}
	rm -fr ${LIBBEEOBJS_C:.o=.c}
	for v in $(BASEOBJS); do mv "$$v.save" "$$v"; done

scratch: clean

check: scratch build
	echo PASSED >check.txt
