DIM RES 8192
DIM PST 8192
DIM CODE 200
FOR PASS = 0 TO 3 STEP 3
P% = CODE
[OPT PASS
.TEST     PHP
          LDX #32
          LDY #0
.L1       TYA
          CLC
          SED
          ADC &74
          CLD
          STA (&70), Y
          PHP
          PLA
          STA (&72), Y
          INY
          BNE L1
          INC &71
          INC &73
          INC &74
          DEX
          BNE L1
          PLP
          RTS
]
NEXT
FOR BLOCK = 0 TO 7
   !&70 = RES
   !&72 = PST
   ?&74 = BLOCK * 32
   PRINT "BLOCK "; BLOCK
   CALL TEST
   OSCLI "SAVE RES" + STR$(BLOCK) + " " + STR$~RES + " +2000"
   OSCLI "SAVE PST" + STR$(BLOCK) + " " + STR$~PST + " +2000"
NEXT
