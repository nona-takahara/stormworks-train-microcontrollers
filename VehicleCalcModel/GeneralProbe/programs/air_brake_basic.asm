; Air brake target-pressure controller (SPEC: AirBrake/SPEC.md, BYTECODE_SPEC.md).
; Inputs : N1 = target pressure [atm abs], N2 = brake cylinder pressure
; Outputs: N1 = inlet valve (0..1), N2 = exhaust valve (0..1)
.host 8
.pub tgt
.pub pbc
.pub err
.pub u          ; signed command: + inlet, - exhaust
.pub uin
.pub uex
.pub phase      ; segment number for the log (written by the host with MEM)
.var tmp
.var inb
.var zero

        PLD  tgt, N1
        PLD  pbc, N2
        SUB  err, tgt, pbc
        MUL  u, err, #2.0       ; gain: full open at 0.5 atm error
        CLP  u, #-1, #1
        ABS  tmp, err
        LT   inb, tmp, #0.01    ; inside the dead band
        CMOV u, zero, inb
        MAX  uin, u, zero
        SUB  tmp, zero, u
        MAX  uex, tmp, zero
        PST  N1, uin
        PST  N2, uex
        HALT
