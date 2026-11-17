OUTBIG EQU 8002H    ; 位选控制端口，用于选择要显示的数码管
OUTSEG EQU 8004H    ; 段选控制端口，用于控制数码管显示的数字
KEYIN  EQU 8001H    ; 键盘输入端口，用于读取按键状态

; 时钟数据缓冲区：
; 20H 21H 22H 23H 24H 25H

;*********** 时钟初始化设置 ************
READY:     
MOV 25H,#08H  ; 8
MOV 24H,#00H  ; 0
MOV 23H,#02H  ; 2
MOV 22H,#00H  ; 0
MOV 21H,#00H  ; 0
MOV 20H,#01H  ; 1
;*************************************

MOV R7,#6     ; 设置按键输入计数器(6位显示)
MAIN:      
LCALL DISPLAY   ; 调用显示子程序，刷新数码管显示
LCALL TEST      ; 检测是否有按键按下
JZ MAIN         ; 无按键(Z=1)，继续显示刷新
LCALL SEARCH    ; 有按键，调用键值查找程序

; 显示缓冲区左移，为新键值腾出位置 
MOV 20H,21H     ; 
MOV 21H,22H     ; 
MOV 22H,23H     ; 
MOV 23H,24H     ; 
MOV 24H,25H     ; 
MOV 25H,A       ; 新键值
DJNZ R7, MAIN   ; 循环接收6次按键输入
SHIZHONG:
LCALL DELONE    ; 延时1秒
LCALL ADD1      ; 时间加1秒
SJMP SHIZHONG   ; 循环执行时钟功能

;*********** 显示模块 **************
DISPLAY:  ; 数码管动态显示子程序 (优化后：先关位选再开下一位位选)
MOV R0,#20H
MOV R1,#6
MOV R2,#00100000B  ; 位选信号，从最左边数码管开始(位5为1)

LOOP3:
; 1. 关闭所有显示（清除上一位的位选信号，消除拖影）
MOV DPTR,#OUTBIG
MOV A,#00H
MOVX @DPTR,A

; 2. 查表获取段码
MOV DPTR,#LEDTAB
MOV A,@R0
MOVC A,@A+DPTR   ; 查表获取对应的段码
MOV B,A

; 3. 输出段码
MOV DPTR,#OUTSEG
MOV A,B
MOVX @DPTR,A     ; 段码输出到8004H端口

; 4. 输出位选信号
MOV DPTR,#OUTBIG
MOV A,R2
MOVX @DPTR,A     ; 位选输出到8002H端口

; 5. 准备下一位
RR A             ; 右移，选择下一位数码管
MOV R2,A
LCALL DELAY      ; 显示延时
INC R0           ; 指向下一个显示数据
DJNZ R1,LOOP3
RET
;************************************

DELAY:    MOV R5,#01H      ; 短延时子程序 (无变化)
DEL1:     MOV R6,#00H
DEL2:     DJNZ R6,DEL2
DJNZ R5,DEL1
RET

TEST:     ; 键盘检测子程序 (无变化)
MOV DPTR,#OUTBIG
MOV A,#00H
MOVX @DPTR,A   ; 向所有列输出0
MOV DPTR,#KEYIN
MOVX A,@DPTR   ; 读取行状态
CPL A          ; 取反(有按键行为1)
ANL A,#0FH     ; 保留低4位(行信号)
RET            ; 返回：A=0无按键，A≠0有按键

SEARCH:   ; 键值查找子程序 (无变化，逻辑正确)
MOV R1,#00100000B ; 初始列选信号
MOV R2,#06H      ; 6列需要扫描
MOV R5,#00H      ; 列计数器(0-5)
MOV R4,#03H      ; 行偏移量(用于映射行号 3,2,1,0)
LSEARCH:  ; 列扫描循环
MOV A,R1
CPL A
MOV DPTR,#OUTBIG
MOVX @DPTR,A   ; 输出列选信号
CPL A
RR A           ; 准备下一列的选通信号
MOV R1,A
MOV DPTR,#KEYIN
MOVX A,@DPTR   ; 读取行状态
CPL A
ANL A,#0FH     ; 保留低4位
JNZ HSEARCH    ; 有按键，转行扫描
INC R5         ; 无按键，列计数器加1
DJNZ R2,LSEARCH ; 继续扫描下一列
HSEARCH:  ; 行扫描处理
MOV R6,#04H    ; 4行需要检查
LOOP2:    RRC A          ; 带进位右移，检测各行
JC GET         ; 该行有按键，转键值获取
DEC R4         ; 行偏移量减1
DJNZ R6,LOOP2
GET:      ; 计算键值：键值 = 行号(R4)×6 + 列号(R5)
MOV A,R4
MOV B,#6H
MUL AB
ADD A,R5
MOV DPTR,#KEYTAB
MOVC A,@A+DPTR ; 查表获取实际键值
MOV 26H,A      ; 暂存键值
WAIT:     ; 等待按键释放 (无变化)
MOV DPTR,#OUTBIG
CLR A
MOVX @DPTR,A   ; 关闭所有列
LCALL DELAY
LCALL TEST
JNZ WAIT       ; 按键未释放，继续等待
MOV A,26H      ; 恢复键值
RET

;******************** 时间加1子程序 ***********************
ADD1:     ; 秒低位加1 (地址25H)
MOV A,25H
INC A
MOV 25H,A
CJNE A,#0AH,QUIT
MOV 25H,#00H     ; 到10，秒低位归零

; 加1 (地址24H)
MOV A,24H
INC A
MOV 24H,A
CJNE A,#06H,QUIT ; 未到60秒，返回
MOV 24H,#00H     ; 到60秒，秒高位归零

; 加1 (地址23H)
MOV A,23H
INC A
MOV 23H,A
CJNE A,#0AH,QUIT ; 未到10分钟，返回
MOV 23H,#00H     ; 到10分钟，分低位归零

; 加1 (地址22H)
MOV A,22H
INC A
MOV 22H,A
CJNE A,#06H,QUIT ; 未到60分钟，返回
MOV 22H,#00H     ; 到60分钟，分高位归零

; 加1 (地址21H)
MOV A,21H
INC A
MOV 21H,A

; 检查是否到达10 (触发时高位进位)
CJNE A,#0AH,QUIT; 

; 到10，进位
MOV 21H,#00H     ; 时低位归零
MOV A,20H
INC A
MOV 20H,A

QUIT:     RET
;***********************************************************

;************ 1秒延时子程序 ***********
DELONE:   ; 三重循环实现约1秒延时 (无变化)
MOV 27H,#3
L3:       MOV 28H,#10
L2:       MOV 29H,#10
L1:       LCALL DISPLAY    ; 调用显示防止闪烁
DJNZ 29H,L1
DJNZ 28H,L2
DJNZ 27H,L3
RET
;************************************

; 七段数码管段码表(共阳极，0-F)
LEDTAB:   
DB 3FH, 06H, 5BH, 4FH, 66H, 6DH, 7DH, 07H  ; 0-7
DB 7FH, 6FH, 77H, 7CH, 39H, 5EH, 79H, 71H  ; 8-F

; 键盘键值映射表(6列×4行布局)
KEYTAB:   
DB 07H, 08H, 09H, 0AH, 10H, 0FFH  ; 第1行
DB 04H, 05H, 06H, 0BH, 11H, 14H  ; 第2行
DB 01H, 02H, 03H, 0CH, 12H, 15H  ; 第3行
DB 00H, 0FH, 0EH, 0DH, 13H, 16H  ; 第4行