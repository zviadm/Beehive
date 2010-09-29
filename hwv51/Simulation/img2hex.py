#!/usr/bin/env python
import sys

# read in image bytes
f = open(sys.argv[1])
bytes = f.read()
f.close()

print "@1000"
for i in xrange(0,len(bytes),4):
    word = ord(bytes[i]) + (ord(bytes[i+1]) << 8) + (ord(bytes[i+2]) << 16) + (ord(bytes[i+3]) << 24)
    print "%08x" % word

