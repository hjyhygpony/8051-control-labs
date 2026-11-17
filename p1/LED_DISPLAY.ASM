;=======================================================
; 实验3.1：键盘输入及LED移位显示程序
; 目的：显示学号/班号，并实现键盘输入左移显示
; 修复了所有 R 寄存器的 PUSH/POP 错误。
;=======================================================

; --- 端口定义 ---
KEY_IN_ADDR     EQU 8001H       ; 键盘读入口地址
LED_BIT_ADDR    EQU 8002H       ; 位选/列扫描口地址
LED_SEG_ADDR    EQU 8004H       ; 段选口地址

; --- 存储器定义 ---
DISP_BUFF       EQU 30H         ; 显示缓冲区起始地址 (30H-35H 存6位数)
KEY_TEMP        EQU 36H         ; 暂存按键值
KEY_FLAG        EQU 37H         ; 按键标志位 (0:无键, 1:有键)

        ORG     0000H
        LJMP    MAIN

        ORG     0030H           ; 跳过中断区
MAIN:
        MOV     SP, #60H        ; 设置堆栈

        ; --- 1. 初始化显示学号/班号 (6位) ---
        ; 请将以下6个字节改为你的学号/班号对应的数字值
        MOV     30H, #02H       ; 最左位 (Buffer[0]) - 示例值
        MOV     31H, #03H
        MOV     32H, #00H
        MOV     33H, #07H
        MOV     34H, #00H
        MOV     35H, #08H       ; 最右位 (Buffer[5])

MAIN_LOOP:
        LCALL   DISPLAY_SCAN    ; 动态显示并扫描键盘

        MOV     A, KEY_FLAG
        CJNE    A, #01H, NO_KEY_ACTION ; 检查是否有键按下

        ; --- 2. 有键按下，进行数据移位 ---
        LCALL   SHIFT_DATA      ; 移位并更新显示缓冲区
        MOV     KEY_FLAG, #00H  ; 清除按键标志

        ; --- 3. 等待按键释放 (防重复按键) ---
WAIT_UP:
        LCALL   DISPLAY_SCAN    ; 继续扫描显示，直到按键释放
        MOV     A, KEY_FLAG
        CJNE    A, #01H, KEY_RELEASED
        SJMP    WAIT_UP         ; 仍在按下，继续等待
KEY_RELEASED:

NO_KEY_ACTION:
        SJMP    MAIN_LOOP

;=======================================================
; DISPLAY_SCAN 子程序：动态扫描显示并同时扫描键盘
;=======================================================
DISPLAY_SCAN:
        PUSH    PSW
        PUSH    ACC
        PUSH    00H             ; R0 (已修正)
        PUSH    01H             ; R1 (已修正)

        MOV     R0, #DISP_BUFF  ; R0 指向显示缓冲区
        MOV     R1, #20H        ; R1 位选码初值 (从最左第二位开始，与你的代码一致)
        MOV     DPTR, #LED_BIT_ADDR ; 位选口地址

SCAN_LOOP:
    ; 输出位选码
    MOV A, R1
    MOVX @DPTR, A

    ; 输出段码
    PUSH DPH
    PUSH DPL
    MOV A, @R0
    MOV DPTR, #SEGMENT_TABLE
    MOVC A, @A+DPTR
    MOV DPTR, #LED_SEG_ADDR
    MOVX @DPTR, A
    POP DPL
    POP DPH

    ; 短延时维持亮度
    LCALL DEYS_SHORT

    ; 准备下一位
    INC R0
    MOV A, R1
    RR A
    MOV R1, A

    CJNE R0, #36H, SCAN_LOOP ; 循环6次

    POP 01H
    POP 00H
    POP ACC
    POP PSW
    RET

NO_KEY_IN_COL:
        ; 3. 输出段码 (显示数字)
        PUSH    DPH             ; 保存DPTR
        PUSH    DPL
        MOV     A, @R0          ; 取出要显示的数字 (0-9)
        MOV     DPTR, #SEGMENT_TABLE ; 字形表基址
        MOVC    A, @A+DPTR      ; 查表得段码
        MOV     DPTR, #LED_SEG_ADDR
        MOVX    @DPTR, A        ; 写段码到 8004H
        POP     DPL             ; 恢复DPTR
        POP     DPH

        ; 4. 延时，维持亮度
        LCALL   DEYS_SHORT

        ; 5. 准备下一位
        INC     R0              ; 缓冲区指针+1
        MOV     A, R1
        RR      A               ; 循环右移，改变位选位置 (匹配你的代码)
        MOV     R1, A

        CJNE    R0, #36H, SCAN_LOOP ; 6位扫描完毕 (30H -> 35H)

        POP     01H             ; R1 (已修正)
        POP     00H             ; R0 (已修正)
        POP     ACC
        POP     PSW
        RET

;=======================================================
; 修改后的 KEY_SCAN 子程序：带行列扫描和消抖
; 输出：有按键按下时 C=1, KEY_FLAG=1, KEY_TEMP=键值(0-15)
;       无按键按下时 C=0, KEY_FLAG=0
;=======================================================
KEY_SCAN:
    PUSH ACC
    PUSH B
    PUSH 00H  ; 保护R0
    PUSH DPH
    PUSH DPL

    ; 1. 检测是否有任何按键按下
    MOV DPTR, #LED_BIT_ADDR
    MOV A, #00H  ; 准备向所有行（位选线）输出0，扫描所有行
    MOVX @DPTR, A

    MOV DPTR, #KEY_IN_ADDR
    MOVX A, @DPTR  ; 读取所有列线状态
    CPL A          ; 取反，因为通常低电平表示按下
    ANL A, #0FH    ; 只关心低4位（列线）
    JZ NO_KEY_PRESSED  ; 如果所有列线都是高电平（取反后为0），则无按键

    ; 2. 有按键按下，进行消抖延时[7,8](@ref)
    LCALL DEYS_10MS  ; 延时约10ms，避开抖动期

    ; 3. 消抖后再次检测，并开始逐行扫描确定具体按键
    MOV R0, #0FEH    ; 行扫描初始值，从第0行开始（1111 1110）
    MOV R1, #0       ; 记录当前行号

SCAN_ROW:
    MOV DPTR, #LED_BIT_ADDR
    MOV A, R0
    MOVX @DPTR, A    ; 将扫描值输出到行线

    MOV DPTR, #KEY_IN_ADDR
    MOVX A, @DPTR    ; 读取列线状态
    CPL A
    ANL A, #0FH      ; 屏蔽高4位
    JNZ KEY_FOUND_IN_ROW  ; 如果列线非全高，说明该行有按键按下

    ; 该行无按键，扫描下一行
    MOV A, R0
    RL A             ; 左移一位，扫描下一行
    MOV R0, A
    INC R1           ; 行号加1
    CJNE R1, #4, SCAN_ROW  ; 假设4行，扫描完所有行

    SJMP NO_KEY_PRESSED  ; 所有行扫描完毕仍未找到，视为抖动或无按键

KEY_FOUND_IN_ROW:
    ; 4. 确定列号
    MOV R2, A        ; 保存列线状态
    MOV R3, #0       ; 记录当前列号

FIND_COL_BIT:
    RRC A           ; 带进位右移
    JNC COL_FOUND    ; 如果进位C为0，找到所在列
    INC R3          ; 列号加1
    SJMP FIND_COL_BIT

COL_FOUND:
    ; 5. 计算键值 (键值 = 行号 * 4 + 列号)，或其他映射方式
    MOV A, R1
    MOV B, #4
    MUL AB          ; A = 行号 * 4
    ADD A, R3       ; A = 行号*4 + 列号
    MOV KEY_TEMP, A ; 保存键值
    MOV KEY_FLAG, #01H
    SETB C
    SJMP KEY_SCAN_EXIT

NO_KEY_PRESSED:
    MOV KEY_FLAG, #00H
    CLR C

KEY_SCAN_EXIT:
    POP DPL
    POP DPH
    POP 00H
    POP B
    POP ACC
    RET
;=======================================================
; SHIFT_DATA 子程序：将缓冲区数据左移一位
;=======================================================
SHIFT_DATA:
        MOV     R0, #30H        ; 从 Buffer[0] 开始
        MOV     R1, #31H        ; 从 Buffer[1] 开始
SHIFT_LOOP:
        MOV     A, @R1
        MOV     @R0, A          ; Buffer[i] = Buffer[i+1] (左移)
        INC     R0
        INC     R1
        CJNE    R1, #36H, SHIFT_LOOP ; 循环到 Buffer[4] = Buffer[5]

        MOV     A, KEY_TEMP
        MOV     35H, A          ; 将新键值放入最右侧 (Buffer[5])
        RET

;=======================================================
; 延时子程序 (已修正 PUSH/POP)
;=======================================================
DEYS_SHORT:                     ; 短延时 (维持动态扫描亮度)
        PUSH    06H             ; R6 (已修正)
        PUSH    07H             ; R7 (已修正)
        MOV     R6, #02H
DEYS_LOOP_OUT:
        MOV     R7, #0FFH
DEYS_LOOP_IN:
        DJNZ    R7, DEYS_LOOP_IN
        DJNZ    R6, DEYS_LOOP_OUT
        POP     07H             ; R7 (已修正)
        POP     06H             ; R6 (已修正)
        RET

DEYS_10MS:                      ; 长延时 (约10ms，用于去抖)
        PUSH    06H             ; R6 (已修正)
        PUSH    07H             ; R7 (已修正)
        MOV     R6, #10
D10_LOOP:
        MOV     R7, #250
        DJNZ    R7, $
        DJNZ    R6, D10_LOOP
        POP     07H             ; R7 (已修正)
        POP     06H             ; R6 (已修正)
        RET

;=======================================================
; 字形表 (共阴极 LED 数码管，0-F)
;=======================================================
SEGMENT_TABLE:
        DB 3FH, 06H, 5BH, 4FH, 66H, 6DH, 7DH, 07H, 7FH, 6FH
        DB 77H, 7CH, 39H, 5EH, 79H, 71H

        END
