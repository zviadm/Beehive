#!/usr/bin/env python
import sys

f = open(sys.argv[1])

for line in f:
    if line[0] == '@': print line[:-1]
    else: print "%s" % (line[1:-1],)   # include parity bits

f.close()
