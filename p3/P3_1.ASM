ORG 0000H
OUTBIG EQU 8002H   ; LED位选/键盘列扫描端口 (CS0)
OUTSEG EQU 8004H   ; LED段码输出端口 (CS0)
KEYIN  EQU 8001H   ; 键盘行码读入口 (CS0)
DAC EQU 9000H      ; DAC0832数字量输入端口 (CS1片选)

AJMP READY         ; 无条件跳转到初始化程序

ORG 000BH          ; 定时器T0中断入口
AJMP TIME          ; 中断服务程序：每秒进行一次转速采样和闭环控制

; T1计数 (连接霍尔脉冲), T0定时 (用于1秒采样周期)
READY:
	MOV SP,#60H    ; 设置堆栈指针

	; --- LED 显示缓冲区初始化 (100208) ---
	MOV 20H,#06H   ; L5: 1
	MOV 21H,#3FH   ; L4: 0
	MOV 22H,#3FH   ; L3: 0
	MOV 23H,#5BH   ; L2: 2
	MOV 24H,#3FH   ; L1: 0
	MOV 25H,#7FH   ; L0: 8 
	
	MOV 26H,#00H   ; 存储期望转速值 (R.P.M.)，键盘输入后更新
	MOV 27H,#00H   ; 用于记录T0中断次数 (累计20次达到1秒采样周期)
	MOV 28H,#00H   ; 暂存上一次输入的键值 (期望值高位)
	MOV 29H,#20H   ; DAC初始数字量。此值越大，DAC输出越小，转速越慢

	; --- 定时器/计数器设置 ---
	MOV TMOD,#51H  ; 01010001B: T1方式1(计数器)，T0方式1(定时器)
	MOV TL0,#0B0H
	MOV TH0,#3CH   ; T0定时常数(15536)，每50ms中断一次 (晶振12MHz)
	MOV TL1,#00H
	MOV TH1,#00H   ; T1计数器初值清零
	
	SETB ET0       ; 允许T0中断
	SETB EA        ; 允许总中断
	SETB TR0       ; 启动T0计时
	SETB TR1       ; 启动T1计数 (开始接收霍尔脉冲)

MAIN:
	LCALL DACHANGE     ; 输出当前控制量到DAC，实时控制电机转速
	LCALL DISPLAY      ; 刷新LED显示 (期望值和实际转速)
	LCALL TEST         ; 检测是否有键盘输入
	JZ MAIN            ; 无按键, 继续循环

	LCALL SEARCH       ; 有键值输入, 获取键值(0-FH)到A
	
	; --- 键盘输入处理 (两位十六进制数输入，左移显示) ---
	MOV 20H,21H	       ; 旧输入值段码左移一位到20H

	MOV B,28H	       ; B = 上一个输入的键值 (作为期望值的高位)
	MOV 28H,A	       ; 28H = 当前输入的键值 (作为期望值的低位)

	; 将新键值转换为段码并显示
	MOV DPTR,#LEDTAB
	MOVC A,@A+DPTR	   
	MOV 21H,A	       ; 将新键值的段码放入左数第二位LED显示
	
    ; 计算最终期望转速值 (26H = 上一个键值 * 16 + 当前键值)
	MOV A,B            ; A = 上一个键值
    MOV B,#10H         ; B = 16 (作为乘数)
    MUL AB             ; A = A * B (即 上一个键值 * 16). 结果低位在A.
    ADD A,28H          ; A = A + 28H (加上新键值)
	MOV 26H,A	       ; 期望转速值存入26H (闭环控制的目标值)

	LCALL DACHANGE     ; 确保 DAC 在键盘操作后立即响应
	SJMP MAIN

; --- DAC 输出子程序 (DAC0832) ---
DACHANGE:
	MOV DPTR,#DAC
	MOV A,29H          ; 29H存有当前控制数字量
	MOVX @DPTR,A       ; 写入DAC0832 (9000H)
	RET

; --- LED 动态显示子程序 ---
DISPLAY:
	MOV R0,#20H        ; 缓冲区起始地址
	MOV R1,#6          ; 共6个LED
	MOV R2,#00100000B  ; 位选信号初值 (从左边开始)

LOOP:	
	MOV DPTR,#OUTSEG
	MOV A,#0
	MOVX @DPTR,A       ; 清段码（防止重影）
	MOV A,@R0          ; 取出当前位的段码
	MOVX @DPTR,A       ; 输出段码

	MOV DPTR,#OUTBIG
	MOV A,R2
	MOVX @DPTR,A       ; 输出位选通信号
	RR A               ; 位选信号右移
	MOV R2,A
	
	LCALL DELAY        ; 延时
	INC R0
	DJNZ R1,LOOP       ; 循环6次
	RET

; --- 延时子程序 ---
DELAY:
	MOV R7,#02H
DEL1:	
	MOV R6,#0ffH
DEL2:	
	DJNZ R6,DEL2
	DJNZ R7,DEL1
	RET

; --- 键盘检测 (非阻塞式) ---
TEST:
	MOV DPTR,#OUTBIG
	MOV A,#00H
	MOVX @DPTR,A       ; 关闭所有列扫描
	MOV DPTR,#KEYIN
	MOVX A,@DPTR       ; 读取行状态
	CPL A              ; 求反 (有键按下->1)
	ANL A,#0FH         ; 只取行码
	RET

; --- 获取按下的键信息 (4x6 矩阵键盘扫描) ---
SEARCH:
	MOV R1,#00100000B  ; 初始列选信号
	MOV R2,#06H        ; 循环6列
	MOV R5,#00H        ; 记录当前所在列号
	MOV R4,#03H        ; 初始行号 (用于计算键值)
	
; ---- 找出有效列和行 ----
LSEARCH:
	MOV A,R1
	CPL A              ; 键盘列扫描低有效 (输出0选通)
	MOV DPTR,#OUTBIG
	MOVX @DPTR,A       ; 输出列扫描信号
	
	CPL A
	RR A	           ; 为下一轮准备R1
	MOV R1,A
	
	MOV DPTR,#KEYIN
	MOVX A,@DPTR       ; 读出键盘行扫描信号 (低有效)
	CPL A
	ANL A,#0FH         ; 取低4位 (键按下为1)
	JNZ HSEARCH        ; A不为零，找到所在列和行
	
	INC R5	           ; 列号加一
	DJNZ R2,LSEARCH    ; 循环查找
	
; ---- 确定行号 (将行码转换为行索引) ----
HSEARCH:
	MOV R7,#04H	       ; 一共有四行
LOOP2:	
	RRC A              ; 右移，检查最低位是否为1 (找到行)
	JC GET             ; 找到行
	DEC R4             ; 行号减一
	DJNZ R7,LOOP2
	
; ---- 确定输入的键码值 (查表) ----
GET:
	MOV A,R4           ; A = 行号
	MOV B,#6H
	MUL AB             ; A = 行号 * 6
	ADD A,R5           ; A = 偏移量 (行号*6 + 列号)
	MOV DPTR,#KEYTAB
	MOVC A,@A+DPTR     ; 查表，获取实际键码 (0-FH)
	MOV 26H,A          ; 键值暂时保存在内存中 (用于WAIT子程序)
	
WAIT:	
	MOV DPTR,#OUTBIG   ; 等待按键释放
	CLR A
	MOVX @DPTR,A       
	LCALL DELAY
	LCALL TEST
	JNZ WAIT           ; 如果还有键按下，继续等待
	MOV A,26H          ; 将键值重新存入A (作为返回值)
	RET

; --- T0 中断服务程序 TIME (闭环控制核心) ---
TIME:
	PUSH PSW           ; 保护现场
	PUSH ACC
	PUSH B
	PUSH DPL
	PUSH DPH
	
	SETB RS0           ; 选择寄存器组1
	CLR  RS1
	
	MOV R0,27H         ; 取出中断次数
	INC R0             ; 中断次数加一
	MOV 27H,R0         ; 存回
	
	CJNE R0,#14H,END1  ; 检查是否达到20次中断 (1秒采样周期)
	
	; --- 1秒采样周期到达 ---
	MOV R0,#00H
	MOV 27H,R0         ; 中断次数清零
	
	CLR  TR0           ; 停止计时
	CLR  TR1           ; 停止计数
	
	MOV  30H,TL1       ; 实际转速计数低位存入30H
	MOV  31H,TH1       ; 实际转速计数高位存入31H
	
	; --- 将实际转速 (31H:30H) 转换为16进制并显示在 LED 22-25 ---
	; 低位 30H 显示 (24H, 25H)
	MOV A,30H          
	MOV B,#0FH         
	DIV AB             ; A=高4位, B=低4位
	MOV DPTR,#LEDTAB
	MOVC A,@A+DPTR     
	MOV  24H,A
	MOV A,B
	MOVC A,@A+DPTR     
	MOV 25H,A

	; 高位 31H 显示 (22H, 23H)
	MOV A,31H          
	MOV B,#0FH         
	DIV AB             
	MOV DPTR,#LEDTAB
	MOVC A,@A+DPTR     
	MOV  22H,A
	MOV A,B
	MOVC A,@A+DPTR     
	MOV 23H,A

	; --- 闭环控制逻辑 (简单比例调节) ---
	MOV A,31H          ; 取转速高位
	JNZ SPEEDDOWN      ; 如果高位非0，转速极快，立即减速
	
	MOV A,30H          ; 取转速低位 (实际转速)
	CLR C              
	SUBB A,26H         ; 实际转速 (A) - 期望转速 (26H)
	
	JB CY,SPEEDUP      ; 有借位 (CY=1)，实际转速 < 期望值，需要加速
	JZ SUBEND          ; A=0，转速相等，不调整
	SJMP SPEEDDOWN     ; 实际转速 > 期望值，需要减速

SPEEDDOWN:
	MOV A,29H          ; 数字量 (DAC值) 放入A
	ADDC A,#01H        ; 数字量加一 (转速减慢)
	MOV 29H,A          
	SJMP SUBEND

SPEEDUP:
	MOV A,29H          ; 数字量 (DAC值) 放入A
	SUBB A,#01H        ; 数字量减一 (转速加快)
	MOV 29H,A          
	SJMP SUBEND

SUBEND:	
	; 重新启动定时器和计数器
	MOV TL0,#0B0H
	MOV TH0,#3CH       
	MOV TL1,#00H
	MOV TH1,#00H       
	
	SETB TR0           ; 启动T0计时
	SETB TR1           ; 启动T1计数

END1:	
	; 恢复现场
	POP DPH
	POP DPL
	POP B
	POP ACC
	POP PSW
	RETI               ; 中断返回

; --- 查表 (LED段码表和键盘码表) ---
LEDTAB:	
	; 0, 1, 2, 3, 4, 5, 6, 7 
	DB 3fh, 06h, 5bh, 4fh, 66h, 6dh, 7dh, 07h
	; 8, 9, A, B, C, D, E, F 
	DB 7fh, 6fh, 77h, 7ch, 39h, 5eh, 79h, 71h

KEYTAB:	
	; 4x6 键盘布局，对应键值 (0-F, 忽略功能键)
	DB 07h, 08h, 09h, 0ah, 10h, 0ffh, 
	DB 04h, 05h, 06h, 0bh, 11h, 14h,  
	DB 01h, 02h, 03h, 0ch, 12h, 15h,  
	DB 00h, 0fh, 0eh, 0dh, 13h, 16h
