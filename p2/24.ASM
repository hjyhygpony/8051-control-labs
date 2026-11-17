

; 程序开始
ORG 0000H
    LJMP MAIN

ORG 0030H
MAIN:
    MOV SP, #60H
    MOV R3, #0          ; 相位指针初始化

MAIN_LOOP:
    ; 正转加速100步
    MOV R4, #0          ; 方向标志设为正转
    MOV R5, #100        ; 步数
    MOV R6, #100        ; 初始延时参数（慢速）
    MOV R7, #10         ; 目标延时参数（快速）
    ACALL ACCELERATE_RUN
    
    ; 正转匀速100步
    MOV R4, #0          ; 方向标志设为正转
    MOV R5, #100        ; 步数
    MOV R6, #10         ; 固定延时参数
    ACALL CONSTANT_RUN
    
    ; 正转减速100步
    MOV R4, #0          ; 方向标志设为正转
    MOV R5, #100        ; 步数
    MOV R6, #10         ; 初始延时参数（快速）
    MOV R7, #100        ; 目标延时参数（慢速）
    ACALL DECELERATE_RUN
    
    ; 短暂停顿
    ACALL DELAY_LONG
    
    ; 反转加速100步
    MOV R4, #1          ; 方向标志设为反转
    MOV R5, #100        ; 步数
    MOV R6, #100        ; 初始延时参数（慢速）
    MOV R7, #10         ; 目标延时参数（快速）
    ACALL ACCELERATE_RUN
    
    ; 反转匀速100步
    MOV R4, #1          ; 方向标志设为反转
    MOV R5, #100        ; 步数
    MOV R6, #10         ; 固定延时参数
    ACALL CONSTANT_RUN
    
    ; 反转减速100步
    MOV R4, #1          ; 方向标志设为反转
    MOV R5, #100        ; 步数
    MOV R6, #10         ; 初始延时参数（快速）
    MOV R7, #100        ; 目标延时参数（慢速）
    ACALL DECELERATE_RUN
    
    ; 短暂停顿
    ACALL DELAY_LONG
    
    SJMP MAIN_LOOP      ; 循环执行

; 加速运行子程序（简化版）
ACCELERATE_RUN:
    PUSH ACC
    PUSH PSW
    PUSH 00H
    PUSH 01H
    PUSH 05H
    PUSH 06H
    PUSH 07H
    
    MOV A, R5
    MOV R0, A           ; 步数计数器
    
    ; 计算每一步的延时变化量
    MOV A, R6           ; 初始延时
    CLR C
    SUBB A, R7          ; 初始延时 - 目标延时
    MOV B, R5           ; 总步数
    DIV AB              ; 延时变化量 = 延时差 / 步数
    MOV R1, A           ; R1存储延时变化量
    
    MOV A, R6           ; 当前延时 = 初始延时
    MOV R2, A           ; R2存储当前延时
    
ACCEL_LOOP:
    ACALL STEP_MOTOR    ; 执行一步
    
    ; 使用两层循环的延时
    MOV A, R2
    ACALL SIMPLE_DELAY  ; 简化延时
    
    ; 更新延时（加速）
    MOV A, R2
    CLR C
    SUBB A, R1          ; 减去延时变化量
    MOV R2, A
    
    ; 边界检查
    MOV A, R2
    CLR C
    SUBB A, R7
    JNC ACCEL_CONTINUE
    MOV A, R7
    MOV R2, A
    
ACCEL_CONTINUE:
    DJNZ R0, ACCEL_LOOP
    
    POP 07H
    POP 06H
    POP 05H
    POP 01H
    POP 00H
    POP PSW
    POP ACC
    RET

; 匀速运行子程序（简化版）
CONSTANT_RUN:
    PUSH ACC
    PUSH PSW
    PUSH 00H
    PUSH 05H
    PUSH 06H
    
    MOV A, R5
    MOV R0, A           ; 步数计数器
    
CONSTANT_LOOP:
    ACALL STEP_MOTOR    ; 执行一步
    
    ; 使用固定延时
    MOV A, R6
    ACALL SIMPLE_DELAY
    
    DJNZ R0, CONSTANT_LOOP
    
    POP 06H
    POP 05H
    POP 00H
    POP PSW
    POP ACC
    RET

; 减速运行子程序（简化版）
DECELERATE_RUN:
    PUSH ACC
    PUSH PSW
    PUSH 00H
    PUSH 01H
    PUSH 05H
    PUSH 06H
    PUSH 07H
    
    MOV A, R5
    MOV R0, A           ; 步数计数器
    
    ; 计算每一步的延时变化量
    MOV A, R7           ; 目标延时
    CLR C
    SUBB A, R6          ; 目标延时 - 初始延时
    MOV B, R5           ; 总步数
    DIV AB              ; 延时变化量 = 延时差 / 步数
    MOV R1, A           ; R1存储延时变化量
    
    MOV A, R6           ; 当前延时 = 初始延时
    MOV R2, A           ; R2存储当前延时
    
DECEL_LOOP:
    ACALL STEP_MOTOR    ; 执行一步
    
    ; 使用两层循环的延时
    MOV A, R2
    ACALL SIMPLE_DELAY
    
    ; 更新延时（减速）
    MOV A, R2
    ADD A, R1           ; 加上延时变化量
    MOV R2, A
    
    ; 边界检查
    MOV A, R2
    CLR C
    SUBB A, R7
    JC DECEL_CONTINUE
    MOV A, R7
    MOV R2, A
    
DECEL_CONTINUE:
    DJNZ R0, DECEL_LOOP
    
    POP 07H
    POP 06H
    POP 05H
    POP 01H
    POP 00H
    POP PSW
    POP ACC
    RET

; 步进电机单步控制子程序
STEP_MOTOR:
    PUSH ACC
    PUSH PSW
    
    MOV A, R4
    JZ FORWARD          ; 如果方向为0，正转

REVERSE:                ; 反转
    MOV A, R3
    DEC A               ; 相位指针减1
    ANL A, #03H         ; 取模4，保持0-3范围
    MOV R3, A
    SJMP OUTPUT

FORWARD:               ; 正转
    MOV A, R3
    INC A               ; 相位指针加1
    ANL A, #03H         ; 取模4，保持0-3范围
    MOV R3, A

OUTPUT:
    MOV DPTR, #STEP_TABLE
    MOVC A, @A+DPTR
    MOV P1, A           ; 输出到P1口
    ACALL SHORT_DELAY   ; 短延时确保电机响应
    
    POP PSW
    POP ACC
    RET

; 简化延时子程序（两层循环）
; 输入：A=延时参数（值越大，延时越长）
SIMPLE_DELAY:
    PUSH 00H
    PUSH 01H
    PUSH ACC
    
    MOV R0, A           ; 外层循环计数器
SIMPLE_DELAY_LOOP1:
    MOV R1, #100        ; 内层循环计数器
SIMPLE_DELAY_LOOP2:
    DJNZ R1, SIMPLE_DELAY_LOOP2
    DJNZ R0, SIMPLE_DELAY_LOOP1
    
    POP ACC
    POP 01H
    POP 00H
    RET

; 短延时子程序（用于步进电机响应）
SHORT_DELAY:
    PUSH 00H
    MOV R0, #10
SHORT_DELAY_LOOP:
    DJNZ R0, SHORT_DELAY_LOOP
    POP 00H
    RET

; 长延时子程序（正反转之间的停顿）
DELAY_LONG:
    PUSH 00H
    PUSH 01H
    MOV R0, #50
DELAY_LONG_LOOP1:
    MOV R1, #200
DELAY_LONG_LOOP2:
    DJNZ R1, DELAY_LONG_LOOP2
    DJNZ R0, DELAY_LONG_LOOP1
    POP 01H
    POP 00H
    RET

; 步进电机相序表
STEP_TABLE:
    DB 01H, 02H, 04H, 08H  ; A-B-C-D相

END
