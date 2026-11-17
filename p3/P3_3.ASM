ORG 0000H
OUTBIG EQU 8002H   ; LED位选/键盘列扫描端口
OUTSEG EQU 8004H   ; LED段码输出端口
KEYIN  EQU 8001H   ; 键盘行码读入口
DAC    EQU 9000H   ; DAC0832端口
 
AJMP READY         ; 跳转到初始化

ORG 000BH          ; 定时器T0中断入口
AJMP TIME          ; 中断服务程序

; --- 初始化程序 ---
READY:
	MOV SP,#60H    ; 设置堆栈
	
	; --- LED缓冲区初始化 ---
	MOV 20H,#06H
	MOV 21H,#3FH
	MOV 22H,#3FH
	MOV 23H,#5BH
	MOV 24H,#3FH
	MOV 25H,#7FH
	
	MOV 26H,#28H   ; 默认期望转速: 40 (十六进制28H), 防止刚启动为0
	MOV 27H,#00H   ; 中断计数
	MOV 28H,#00H   ; 键盘输入暂存
	MOV 29H,#80H   ; DAC初始值设为中间值，避免直接全速或停转

	; --- 定时器设置 ---
	MOV TMOD,#51H  ; T1计数，T0定时
	MOV TL0,#0B0H
	MOV TH0,#3CH   ; 50ms
	MOV TL1,#00H
	MOV TH1,#00H

	SETB ET0
	SETB EA
	SETB TR0
	SETB TR1

MAIN:
	LCALL DACHANGE     ; 更新DAC
	LCALL DISPLAY      ; 刷新显示
	LCALL TEST         ; 查键
	JZ MAIN

	LCALL SEARCH       ; 获取键值
	
	; --- 键盘处理 ---
	MOV 20H,21H	       
	MOV B,28H	       
	MOV 28H,A	       
	
	MOV DPTR,#LEDTAB
	MOVC A,@A+DPTR
	MOV 21H,A	       

    ; 计算期望值
	MOV A,B            
    MOV B,#10H         
    MUL AB             
    ADD A,28H          
	MOV 26H,A	       ; 更新期望转速

	LCALL DACHANGE
	SJMP MAIN

; --- DAC 输出 ---
DACHANGE:
	MOV DPTR,#DAC
	MOV A,29H
	MOVX @DPTR,A
	RET

; --- 显示 ---
DISPLAY:
	MOV R0,#20H
	MOV R1,#6
	MOV R2,#00100000B
DISP_LOOP:
	MOV DPTR,#OUTSEG
	MOV A,#0
	MOVX @DPTR,A
	MOV A,@R0
	MOVX @DPTR,A

	MOV DPTR,#OUTBIG
	MOV A,R2
	MOVX @DPTR,A
	RR A
	MOV R2,A

	LCALL DELAY
	INC R0
	DJNZ R1,DISP_LOOP
	RET

DELAY:
	MOV R7,#02H
D1: MOV R6,#0FFH
D2: DJNZ R6,D2
	DJNZ R7,D1
	RET

; --- 键盘扫描 ---
TEST:
	MOV DPTR,#OUTBIG
	MOV A,#00H
	MOVX @DPTR,A
	MOV DPTR,#KEYIN
	MOVX A,@DPTR
	CPL A
	ANL A,#0FH
	RET

SEARCH:
	MOV R1,#00100000B
	MOV R2,#06H
	MOV R5,#00H
	MOV R4,#03H
LSEARCH:
	MOV A,R1
	CPL A
	MOV DPTR,#OUTBIG
	MOVX @DPTR,A
	CPL A
	RR A
	MOV R1,A
	MOV DPTR,#KEYIN
	MOVX A,@DPTR
	CPL A
	ANL A,#0FH
	JNZ HSEARCH
	INC R5
	DJNZ R2,LSEARCH
HSEARCH:
	MOV R7,#04H
HLOOP:
	RRC A
	JC GET_KEY
	DEC R4
	DJNZ R7,HLOOP
GET_KEY:
	MOV A,R4
	MOV B,#6H
	MUL AB
	ADD A,R5
	MOV DPTR,#KEYTAB
	MOVC A,@A+DPTR
	MOV 35H,A          ; 临时存键值
KEY_WAIT:
	MOV DPTR,#OUTBIG
	CLR A
	MOVX @DPTR,A
	LCALL DELAY
	LCALL TEST
	JNZ KEY_WAIT
	MOV A,35H
	RET

; ==============================================
;  关键修正部分：T0 中断服务 (闭环控制算法)
; ==============================================
TIME:
	PUSH PSW
	PUSH ACC
	PUSH B
	PUSH DPL
	PUSH DPH

	MOV R0,27H
	INC R0
	MOV 27H,R0
	CJNE R0,#14H,GOTO_END ; 20次中断=1秒

	; --- 1秒采样到达 ---
	MOV 27H,#00H
	CLR TR0
	CLR TR1

	MOV 30H,TL1        ; 实测低位
	MOV 31H,TH1        ; 实测高位

	; --- 更新转速显示 ---
	; 显示低位
	MOV A,30H
	MOV B,#0FH
	DIV AB
	MOV DPTR,#LEDTAB
	MOVC A,@A+DPTR
	MOV 24H,A
	MOV A,B
	MOVC A,@A+DPTR
	MOV 25H,A
	; 显示高位
	MOV A,31H
	MOV B,#0FH
	DIV AB
	MOV DPTR,#LEDTAB
	MOVC A,@A+DPTR
	MOV 22H,A
	MOV A,B
	MOVC A,@A+DPTR
	MOV 23H,A

	; --- PID控制核心 (带死区和边界保护) ---
	
	; 1. 检查高位 (防止飞车)
	MOV A,31H
	JNZ FORCE_SLOW     ; 如果高位不为0 (转速>255)，绝对太快了，强制减速

	; 2. 比较低位 (实测 vs 期望)
	MOV A,30H          ; A = 实测值
	CLR C
	SUBB A,26H         ; A = 实测 - 期望
	
	JZ KEEP_SPEED      ; 如果完全相等，保持不动
	JC CHECK_FAST      ; 如果有借位 (C=1)，说明 实测 < 期望 (太慢)，去加速
	
	; 3. 处理太快 (实测 > 期望) -> 需要减速 (增加DAC)
	; A 中现在存的是误差值 (Diff)
	; 这里加入死区：如果误差只有1，就不动，避免震荡
	CJNE A,#01H,DO_SLOW ; 如果误差不是1，执行减速
	SJMP KEEP_SPEED     ; 如果误差是1 (比如期望40，实际41)，认为合格，不动

DO_SLOW:
FORCE_SLOW:
	MOV A,29H
	CJNE A,#0FFH,INC_DAC ; **保护**：只有DAC不是FF时才加
	SJMP RESUME_TIMER    ; 已经是FF(最慢)，不能再加了
INC_DAC:
	INC 29H              ; DAC+1 (电压降低，变慢)
	SJMP RESUME_TIMER

	; 4. 处理太慢 (实测 < 期望) -> 需要加速 (减小DAC)
CHECK_FAST:
	; 计算反向误差: 期望 - 实测
	MOV A,26H
	CLR C
	SUBB A,30H         ; A = 误差
	
	; 死区检测
	CJNE A,#01H,DO_FAST
	SJMP KEEP_SPEED    ; 误差为1 (比如期望40，实际39)，不动

DO_FAST:
	MOV A,29H
	JZ RESUME_TIMER    ; **保护**：如果DAC是0(最快)，不能再减了，防止溢出变FF
	DEC 29H            ; DAC-1 (电压升高，变快)
	SJMP RESUME_TIMER

KEEP_SPEED:
	NOP                ; 保持当前DAC值不变

RESUME_TIMER:
	; 重置定时器
	MOV TL0,#0B0H
	MOV TH0,#3CH
	MOV TL1,#00H
	MOV TH1,#00H
	SETB TR0
	SETB TR1

GOTO_END:
	POP DPH
	POP DPL
	POP B
	POP ACC
	POP PSW
	RETI

; --- 数据表 ---
LEDTAB:
	DB 3FH, 06H, 5BH, 4FH, 66H, 6DH, 7DH, 07H
	DB 7FH, 6FH, 77H, 7CH, 39H, 5EH, 79H, 71H

KEYTAB:
	DB 07H, 08H, 09H, 0AH, 10H, 0FFH
	DB 04H, 05H, 06H, 0BH, 11H, 14H
	DB 01H, 02H, 03H, 0CH, 12H, 15H
	DB 00H, 0FH, 0EH, 0DH, 13H, 16H

END