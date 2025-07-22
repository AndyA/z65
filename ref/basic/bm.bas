baseline = 12000
mHz = 3
start = TIME
FOR I% = 1 TO 1000000 : NEXT
elapsed = TIME - start
PRINT baseline / elapsed; " * 65C02"
PRINT baseline / elapsed * mHz; " mHz"
