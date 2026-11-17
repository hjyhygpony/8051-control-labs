        ORG 0 
        MOV A, #0 
        MOV P1, #0 
Loop:  INC P1 
       CALL Delay 
       SJMP LOOP 
Delay: MOV R2,#3 
       MOV R1, #0 
       MOV R2, #0 
DLP: DJNZ R0, DLP 
      DJNZ R1, DLP 
      DJNZ R2, DLP 
      RET 
END
