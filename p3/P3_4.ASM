; ==========================================
; 修改后的 CodeB
; 修复内容：
; 1. TIME 中断中增加了 PSW 的压栈保护和出栈恢复。
; 2. TIME 中断中增加了寄存器组切换 (SETB RS0)，防止 R0 与主程序冲突。
; ==========================================

ORG 0000H
    AJMP READY          ; 上电跳转到初始化

ORG 000BH               ; T0 中断入口
    AJMP TIME

; 定义地址
OUTBIG EQU 8002H    ; 位选 / 键盘列扫描
OUTSEG EQU 8004H    ; 段选
KEYIN  EQU 8001H    ; 键盘行输入
DAC    EQU 9000H    ; DAC 地址

; ------------------------------------------
; 初始化程序
; ------------------------------------------
READY:
    MOV SP,#60H         ; 设置堆栈指针

    ; 初始化显示缓冲区 (20H-25H)
    MOV 20H,#06H        ; 初始显示内容
    MOV 21H,#3FH
    MOV 22H,#3FH
    MOV 23H,#5BH
    MOV 24H,#3FH
    MOV 25H,#7FH

    MOV 26H,#00H        ; 期望转速
    MOV 27H,#00H        ; 中断计数器
    MOV 28H,#00H        ; 键盘输入暂存 (低位)
    MOV 29H,#20H        ; DAC 输出初值

    ; 定时器初始化
    MOV TMOD,#51H       ; T1计数(模式1), T0定时(模式1)
    MOV TL0,#0B0H       ; T0 定时初值 (50ms)
    MOV TH0,#3CH
    MOV TL1,#00H        ; T1 计数初值
    MOV TH1,#00H

    SETB ET0            ; 开 T0 中断
    SETB EA             ; 开总中断
    SETB TR0            ; 启动 T0
    SETB TR1            ; 启动 T1

; ------------------------------------------
; 主循环
; ------------------------------------------
MAIN:
    LCALL DACHANGE      ; 更新 DAC 输出
    LCALL DISPLAY       ; 数码管显示
    LCALL TEST          ; 检测按键
    JZ MAIN             ; 无按键则循环

    LCALL SEARCH        ; 有按键，获取键值 -> A
    
    ; --- 处理按键逻辑 ---
    MOV 20H, 21H        ; 移位显示：原左2移到左1
    MOV B, 28H          ; 取出上一次的键值 (作为高位)
    MOV 28H, A          ; 保存当前键值 (作为低位)

    ; 显示新按键
    MOV DPTR, #LEDTAB
    MOVC A, @A+DPTR
    MOV 21H, A          ; 新按键显示在左2位

    ; 计算期望转速: (上一次键值 * 16) + 当前键值
    MOV A, B            ; A = 旧键值
    MOV B, #10H         ; B = 16
    MUL AB              ; A = 旧键值 * 16
    ADD A, 28H          ; A = 结果 + 新键值
    MOV 26H, A          ; 更新期望转速

    LCALL DACHANGE      ; 立即刷新 DAC
    SJMP MAIN

; ------------------------------------------
; DAC 输出子程序
; ------------------------------------------
DACHANGE:
    MOV DPTR, #DAC
    MOV A, 29H
    MOVX @DPTR, A
    RET

; ------------------------------------------
; 显示子程序 (注意：这里使用了 R0)
; ------------------------------------------
DISPLAY:
    MOV R0, #20H        ; 数据指针
    MOV R1, #6          ; 循环6次
    MOV R2, #00100000B  ; 位选初值

DISP_LOOP:
    MOV DPTR, #OUTSEG
    MOV A, #00H
    MOVX @DPTR, A       ; 消影
    
    MOV A, @R0          ; 取段码
    MOVX @DPTR, A       ; 送段码

    MOV DPTR, #OUTBIG
    MOV A, R2
    MOVX @DPTR, A       ; 送位选

    RR A                ; 位选右移
    MOV R2, A

    LCALL DELAY
    INC R0              ; 指针加1 (若中断不保护R0，这里会出错)
    DJNZ R1, DISP_LOOP
    RET

; ------------------------------------------
; 延时子程序
; ------------------------------------------
DELAY:
    MOV R7, #02H
DEL1:
    MOV R6, #0FFH
DEL2:
    DJNZ R6, DEL2
    DJNZ R7, DEL1
    RET

; ------------------------------------------
; 键盘检测 (是否有键按下)
; ------------------------------------------
TEST:
    MOV DPTR, #OUTBIG
    MOV A, #00H
    MOVX @DPTR, A       ; 全扫描
    MOV DPTR, #KEYIN
    MOVX A, @DPTR
    CPL A
    ANL A, #0FH
    RET

; ------------------------------------------
; 键盘扫描 (获取键值)
; ------------------------------------------
SEARCH:
    MOV R1, #00100000B  ; 列扫描初值
    MOV R2, #06H        ; 6列
    MOV R5, #00H        ; 列计数
    MOV R4, #03H        ; 行计数

LSEARCH:
    MOV A, R1
    CPL A
    MOV DPTR, #OUTBIG
    MOVX @DPTR, A       ; 输出列信号
    CPL A
    RR A
    MOV R1, A

    MOV DPTR, #KEYIN
    MOVX A, @DPTR
    CPL A
    ANL A, #0FH
    JNZ HSEARCH         ; 找到行

    INC R5
    DJNZ R2, LSEARCH

HSEARCH:
    MOV R7, #04H
H_LOOP:
    RRC A
    JC KEY_GET
    DEC R4
    DJNZ R7, H_LOOP

KEY_GET:
    MOV A, R4           ; 行
    MOV B, #6H
    MUL AB
    ADD A, R5           ; + 列
    MOV DPTR, #KEYTAB
    MOVC A, @A+DPTR
    MOV 26H, A          ; 暂存键值

KEY_WAIT:               ; 等待按键释放
    MOV DPTR, #OUTBIG
    CLR A
    MOVX @DPTR, A
    LCALL DELAY
    LCALL TEST
    JNZ KEY_WAIT
    MOV A, 26H          ; 返回键值
    RET

; ------------------------------------------
; T0 中断服务程序 (PID控制/测速)
; ------------------------------------------
TIME:
    PUSH PSW            ; 【关键修正】保护程序状态字
    PUSH ACC
    PUSH B
    PUSH DPL
    PUSH DPH

    SETB RS0            ; 【关键修正】切换到寄存器组 1
    CLR  RS1            ; 这样中断里用的 R0 就不会影响主程序的 R0

    MOV R0, 27H         ; 取中断次数
    INC R0
    MOV 27H, R0
    CJNE R0, #14H, TIME_EXIT ; 未满 20 次 (1秒) 则退出

    ; --- 1秒时间到 ---
    MOV R0, #00H
    MOV 27H, R0

    CLR TR0
    CLR TR1

    MOV 30H, TL1        ; 读取计数值
    MOV 31H, TH1

    ; --- 刷新显示缓冲区 (转速) ---
    ; 处理低位 30H -> 24H, 25H
    MOV A, 30H
    MOV B, #0FH
    DIV AB
    MOV DPTR, #LEDTAB
    MOVC A, @A+DPTR
    MOV 24H, A
    MOV A, B
    MOVC A, @A+DPTR
    MOV 25H, A

    ; 处理高位 31H -> 22H, 23H
    MOV A, 31H
    MOV B, #0FH
    DIV AB
    MOV DPTR, #LEDTAB
    MOVC A, @A+DPTR
    MOV 22H, A
    MOV A, B
    MOVC A, @A+DPTR
    MOV 23H, A

    ; --- 调速控制 ---
    MOV A, 31H
    JNZ SPEED_DOWN      ; 高位不为0，转速太快

    MOV A, 30H
    CLR C
    SUBB A, 26H         ; 实际 - 期望
    JB CY, SPEED_UP     ; 实际 < 期望 -> 加速
    JZ RESTART          ; 相等 -> 不变
    SJMP SPEED_DOWN     ; 实际 > 期望 -> 减速

SPEED_DOWN:
    MOV A, 29H
    ADDC A, #01H        ; DAC值加大 (假设反向控制)
    MOV 29H, A
    SJMP RESTART

SPEED_UP:
    MOV A, 29H
    SUBB A, #01H        ; DAC值减小
    MOV 29H, A
    SJMP RESTART

RESTART:
    MOV TL0, #0B0H
    MOV TH0, #3CH
    MOV TL1, #00H
    MOV TH1, #00H
    SETB TR0
    SETB TR1

TIME_EXIT:
    POP DPH
    POP DPL
    POP B
    POP ACC
    POP PSW             ; 【关键修正】恢复程序状态字 (切回寄存器组 0)
    RETI

; ------------------------------------------
; 查表数据
; ------------------------------------------
LEDTAB:
    DB 3FH, 06H, 5BH, 4FH, 66H, 6DH, 7DH, 07H
    DB 7FH, 6FH, 77H, 7CH, 39H, 5EH, 79H, 71H

KEYTAB:
    DB 07H, 08H, 09H, 0AH, 10H, 0FFH
    DB 04H, 05H, 06H, 0BH, 11H, 14H
    DB 01H, 02H, 03H, 0CH, 12H, 15H
    DB 00H, 0FH, 0EH, 0DH, 13H, 16H

END