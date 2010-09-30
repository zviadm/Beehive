// ------------------------------------------------------------
// Standard as definitions

zero = $0    // fixed zero
r1 = $1      // function return value
r2 = $2      // not callee save
r3 = $3      // not callee save, function argument 1
r4 = $4      // not callee save, function argument 2
r5 = $5      // not callee save, function argument 3
r6 = $6      // not callee save, function argument 4
r7 = $7      // not callee save, function argument 5
r8 = $8      // not callee save, function argument 6
r9 = $9      // callee save
r10 = $10    // callee save
r11 = $11    // callee save
r12 = $12    // callee save
r13 = $13    // callee save
r14 = $14    // callee save
r15 = $15    // callee save
r16 = $16    // callee save
r17 = $17    // callee save
r18 = $18    // callee save
r19 = $19    // callee save
r20 = $20    // callee save
r21 = $21    // callee save
r22 = $22    // callee save
fp = $23     // callee save, frame pointer
t1 = $24     // not callee save, temporary 1, not avail for reg alloc
t2 = $25     // not callee save, temporary 2, not avail for reg alloc
t3 = $26     // not callee save, temporary 3, not avail for reg alloc
p1 = $27     // not callee save, platform 1, not avail for reg alloc
sp = $28     // callee save, stack pointer
vb = $29     // not callee save, rw & rb only, not avail for reg alloc

    .assume   zero,0

// ------------------------------------------------------------
