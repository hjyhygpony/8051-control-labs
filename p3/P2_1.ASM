ORG 0000H
    LJMP MAIN

    ORG 0030H
MAIN:
    MOV SP, #60H
    MOV R3, #0          ; 步进电机相位索引
    MOV R4, #0          ; 方向控制 (0=正转, 1=反转)
    MOV R5, #0          ; 运行状态 (0=加速, 1=匀速, 2=减速)
    MOV R6, #0          ; 当前步数计数
    MOV R7, #100        ; 速度参数定义

RUN_LOOP:
    ; 正转加速100步
    MOV R4, #0          ; 正转方向
    MOV R5, #0          ; 加速状态
    MOV R6, #0          ; 重置步数计数
    MOV R7, #200        ; 初始速度（慢速）
    ACALL RUN_STEPS

    ; 正转匀速100步
    MOV R5, #1          ; 匀速状态
    MOV R6, #0          ; 重置步数计数
    MOV R7, #50         ; 匀速速度
    ACALL RUN_STEPS

    ; 正转减速100步
    MOV R5, #2          ; 减速状态
    MOV R6, #0          ; 重置步数计数
    MOV R7, #50         ; 初始速度
    ACALL RUN_STEPS

    ; 反转加速100步
    MOV R4, #1          ; 反转方向
    MOV R5, #0          ; 加速状态
    MOV R6, #0          ; 重置步数计数
    MOV R7, #200        ; 初始速度（慢速）
    ACALL RUN_STEPS

    ; 反转匀速100步
    MOV R5, #1          ; 匀速状态
    MOV R6, #0          ; 重置步数计数
    MOV R7, #50         ; 匀速速度
    ACALL RUN_STEPS

    ; 反转减速100步
    MOV R5, #2          ; 减速状态
    MOV R6, #0          ; 重置步数计数
    MOV R7, #50         ; 初始速度
    ACALL RUN_STEPS

    SJMP RUN_LOOP       ; 循环反复

; 运行指定步数的子程序
RUN_STEPS:
    PUSH ACC
    PUSH PSW
    PUSH 00H            ; 保护R0
    PUSH 01H            ; 保护R1
    PUSH 02H            ; 保护R2
    
    MOV R0, #100        ; 目标步数

RUN_LOOP_INNER:
    ACALL STEP_MOTOR    ; 执行一步
    
    ; 根据运行状态调整速度
    MOV A, R5
    CJNE A, #0, CHECK_UNIFORM  ; 检查是否为加速状态
    
    ; 加速状态：速度逐渐增加（延迟减少）
    MOV A, R7
    CLR C
    SUBB A, #2          ; 每次加速减少延迟
    MOV R7, A
    CJNE A, #50, SPEED_ADJUSTED  ; 达到目标速度
    SJMP SPEED_ADJUSTED

CHECK_UNIFORM:
    CJNE A, #1, CHECK_DECEL  ; 检查是否为匀速状态
    ; 匀速状态：速度保持不变
    SJMP SPEED_ADJUSTED

CHECK_DECEL:
    ; 减速状态：速度逐渐减少（延迟增加）
    MOV A, R7
    ADD A, #2           ; 每次减速增加延迟
    MOV R7, A
    CJNE A, #200, SPEED_ADJUSTED  ; 达到最低速度

SPEED_ADJUSTED:
    ACALL VARIABLE_DELAY ; 可变延迟
    INC R6              ; 步数加1
    DJNZ R0, RUN_LOOP_INNER
    
    POP 02H             ; 恢复R2
    POP 01H             ; 恢复R1
    POP 00H             ; 恢复R0
    POP PSW
    POP ACC
    RET

; 步进电机控制子程序
STEP_MOTOR:
    PUSH ACC
    PUSH PSW

    MOV A, R4           ; 检查方向
    JNZ REVERSE_DIR     ; 如果R4不为0，则反转

    ; 正转方向
    MOV A, R3
    INC A               ; 相位索引递增
    ANL A, #03H
    MOV R3, A
    SJMP OUTPUT_STEP

REVERSE_DIR:
    ; 反转方向
    MOV A, R3
    DEC A               ; 相位索引递减
    ANL A, #03H
    MOV R3, A

OUTPUT_STEP:
    MOV DPTR, #STEP_TABLE
    MOVC A, @A+DPTR
    MOV P1, A           ; 输出到P1

    POP PSW
    POP ACC
    RET

; 可变延迟子程序（基于R7的值）
VARIABLE_DELAY:
    PUSH 00H
    PUSH 01H
    PUSH 02H
    PUSH 07H            ; 保护R7
    
    MOV A, R7           ; 使用R7作为延迟基数
    MOV R0, A
VD_LOOP1:
    MOV R1, #10
VD_LOOP2:
    MOV R2, #100
VD_LOOP3:
    DJNZ R2, VD_LOOP3
    DJNZ R1, VD_LOOP2
    DJNZ R0, VD_LOOP1
    
    POP 07H             ; 恢复R7
    POP 02H
    POP 01H
    POP 00H
    RET

; 固定延迟子程序（保持兼容性）
DELAY:
    PUSH 02H
    PUSH 03H
    MOV R2, #50
DELAY_LOOP1:
    MOV R3, #200
DELAY_LOOP2:
    DJNZ R3, DELAY_LOOP2
    DJNZ R2, DELAY_LOOP1
    POP 03H
    POP 02H
    RET

; 步进电机相位表
STEP_TABLE:
    DB 01H, 02H, 04H, 08H  ; 4相步进电机驱动序列

    END