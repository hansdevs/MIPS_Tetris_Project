#-------------------------------------------------------------
# TETRIS in MIPS Assembly (for MARS)
#
# Description: A simple ASCII Tetris clone in MIPS assembly. Inspired from the Tetris movie.
#
# Assemble and run in MARS 4.5. Make sure to enable the settings
# for MMIO simulator and "Run I/O on separate thread".
#-------------------------------------------------------------

# MMIO Memory-mapped I/O addresses
.eqv KEYBOARD_READY 0xffff0000
.eqv KEYBOARD_DATA 0xffff0004
.eqv DISPLAY_READY 0xffff0008
.eqv DISPLAY_DATA 0xffff000c

.data
# Board dimensions
BOARD_ROWS:      .word 20
BOARD_COLS:      .word 10

# Symbols for rendering
CHAR_EMPTY:      .byte ' '
CHAR_BLOCK:      .byte '#'
CHAR_BORDER:     .byte '|'
CHAR_NEWLINE:    .byte '\n'
CHAR_BOTTOM:     .byte '-'

# Prompt/messages
MSG_GAMEOVER:    .asciiz "GAME OVER! Press Enter to exit."
MSG_SCORE:       .asciiz "Score: "
MSG_LINES:       .asciiz " | Lines: "
MSG_START:       .asciiz "TETRIS - Use WASD to control"
MSG_DEBUG:       .asciiz "DEBUG: "

# Board array: We store 20*10 = 200 integers/bytes (0 = empty, 1.. = blocks)
# Using .space and storing as bytes for simplicity
.align 2
board:  .space 200       # 20 rows x 10 cols

# Current piece info
# We'll store the current piece's shape as 4x4 cells, plus an ID
currentPiece:    .space 16  # 4x4 = 16 cells
currentPieceX:   .word 0    # top-left x position (column)
currentPieceY:   .word 0    # top-left y position (row)
currentPieceID:  .word 0    # ID (0..6 for 7 pieces)

# Score and lines
score:   .word 0
lines:   .word 0

# Tetromino shapes (7 pieces, each 4 rotations of a 4x4)
# Each rotation is a 4x4 block with 1 = tile, 0 = empty
# We'll store them in a single array: pieceID * 4(rotations) * 16(cells)
# For simplicity, we only store the "default" orientation here; 
# rotation logic will handle rewriting them in currentPiece if needed.

# I-piece (horizontal by default)
# 4x4: 
# [0,1,0,0]
# [0,1,0,0]
# [0,1,0,0]
# [0,1,0,0]
I_piece: .byte 0,1,0,0,
               0,1,0,0,
               0,1,0,0,
               0,1,0,0

# O-piece
# [0,0,0,0]
# [0,1,1,0]
# [0,1,1,0]
# [0,0,0,0]
O_piece: .byte 0,0,0,0,
               0,1,1,0,
               0,1,1,0,
               0,0,0,0

# T-piece
# [0,0,0,0]
# [1,1,1,0]
# [0,1,0,0]
# [0,0,0,0]
T_piece: .byte 0,0,0,0,
               1,1,1,0,
               0,1,0,0,
               0,0,0,0

# S-piece
# [0,0,0,0]
# [0,1,1,0]
# [1,1,0,0]
# [0,0,0,0]
S_piece: .byte 0,0,0,0,
               0,1,1,0,
               1,1,0,0,
               0,0,0,0

# Z-piece
# [0,0,0,0]
# [1,1,0,0]
# [0,1,1,0]
# [0,0,0,0]
Z_piece: .byte 0,0,0,0,
               1,1,0,0,
               0,1,1,0,
               0,0,0,0

# J-piece
# [0,0,0,0]
# [1,0,0,0]
# [1,1,1,0]
# [0,0,0,0]
J_piece: .byte 0,0,0,0,
               1,0,0,0,
               1,1,1,0,
               0,0,0,0

# L-piece
# [0,0,0,0]
# [0,0,1,0]
# [1,1,1,0]
# [0,0,0,0]
L_piece: .byte 0,0,0,0,
               0,0,1,0,
               1,1,1,0,
               0,0,0,0

# Combine them in an array for easy random selection
# We'll store pointer addresses, so each piece is 16 bytes
piecesArray: .word I_piece   # ID 0
             .word O_piece   # ID 1
             .word T_piece   # ID 2
             .word S_piece   # ID 3
             .word Z_piece   # ID 4
             .word J_piece   # ID 5
             .word L_piece   # ID 6

.text
.globl main

###########################################################################
# print_char
# Prints a single character to the MMIO display
# Input: $a0 = character to print
###########################################################################
print_char:
    # Save registers
    addi $sp, $sp, -8
    sw $t0, 0($sp)
    sw $t1, 4($sp)
    
    # Wait until display is ready - with timeout
    li $t1, 10000  # Timeout counter
wait_display:
    lw $t0, DISPLAY_READY
    bnez $t0, display_ready  # If ready bit is set, proceed
    
    # Timeout check - prevent infinite loop
    addi $t1, $t1, -1
    beqz $t1, skip_print  # If timeout, skip printing
    j wait_display
    
display_ready:
    # Display the character
    sw $a0, DISPLAY_DATA
    
skip_print:
    # Restore registers
    lw $t0, 0($sp)
    lw $t1, 4($sp)
    addi $sp, $sp, 8
    jr $ra

###########################################################################
# print_string
# Prints a null-terminated string to the MMIO display
# Input: $a0 = address of string
###########################################################################
print_string:
    # Save return address and registers
    addi $sp, $sp, -8
    sw $ra, 0($sp)
    sw $t0, 4($sp)
    
    # Save $a0
    move $t0, $a0
    
print_loop:
    lb $a0, 0($t0)
    beqz $a0, print_done  # Exit if null terminator
    
    # Print the character
    jal print_char
    
    # Move to next character
    addi $t0, $t0, 1
    j print_loop
    
print_done:
    # Restore return address and registers
    lw $ra, 0($sp)
    lw $t0, 4($sp)
    addi $sp, $sp, 8
    jr $ra

###########################################################################
# print_int
# Prints an integer to the MMIO display
# Input: $a0 = integer to print
###########################################################################
print_int:
    # Save registers
    addi $sp, $sp, -20
    sw $ra, 0($sp)
    sw $t0, 4($sp)
    sw $t1, 8($sp)
    sw $t2, 12($sp)
    sw $a0, 16($sp)  # Save original value
    
    # Handle 0 as a special case
    bnez $a0, not_zero
    li $a0, '0'
    jal print_char
    j print_int_done
    
not_zero:
    # Check if negative
    move $t0, $a0
    bgez $t0, positive
    
    # Print minus sign
    li $a0, '-'
    jal print_char
    
    # Make positive
    neg $t0, $t0
    
positive:
    # Convert to string (reversed)
    li $t1, 0  # Digit count
    
digit_loop:
    # Extract next digit
    li $t2, 10
    div $t0, $t2
    mfhi $t2  # Remainder (digit)
    mflo $t0  # Quotient
    
    # Push digit onto stack
    addi $sp, $sp, -4
    addi $t2, $t2, '0'  # Convert to ASCII
    sw $t2, 0($sp)
    
    # Increment digit count
    addi $t1, $t1, 1
    
    # Continue if more digits
    bnez $t0, digit_loop
    
    # Print digits in correct order
print_digits:
    # Pop digit from stack
    lw $a0, 0($sp)
    addi $sp, $sp, 4
    
    # Print digit
    jal print_char
    
    # Decrement digit count
    addi $t1, $t1, -1
    bnez $t1, print_digits
    
print_int_done:
    # Restore registers
    lw $ra, 0($sp)
    lw $t0, 4($sp)
    lw $t1, 8($sp)
    lw $t2, 12($sp)
    lw $a0, 16($sp)
    addi $sp, $sp, 20
    jr $ra

###########################################################################
# print_debug
# Prints a debug message with a value
# Input: $a0 = address of message, $a1 = value to print
###########################################################################
print_debug:
    addi $sp, $sp, -12
    sw $ra, 0($sp)
    sw $a0, 4($sp)
    sw $a1, 8($sp)
    
    # Print debug prefix
    la $a0, MSG_DEBUG
    jal print_string
    
    # Print message
    lw $a0, 4($sp)
    jal print_string
    
    # Print value
    lw $a0, 8($sp)
    jal print_int
    
    # Print newline
    li $a0, '\n'
    jal print_char
    
    lw $ra, 0($sp)
    addi $sp, $sp, 12
    jr $ra

###########################################################################
# main
# Entry point. Initializes the game, runs the main loop, ends on game over.
###########################################################################
main:
    # Print welcome message
    la $a0, MSG_START
    jal print_string
    li $a0, '\n'
    jal print_char
    
    # Initialize random seed
    li $v0, 30            # Syscall: time
    syscall
    move $t0, $v0         # random seed

    jal init_game
    
    # Debug output to verify game is starting
    li $a0, 'S'
    jal print_char
    li $a0, 'T'
    jal print_char
    li $a0, 'A'
    jal print_char
    li $a0, 'R'
    jal print_char
    li $a0, 'T'
    jal print_char
    li $a0, '\n'
    jal print_char

MainLoop:
    # Debug - print a dot to show the loop is running
    li $a0, '.'
    jal print_char
    
    # 1) Process input
    jal read_input

    # 2) Try to move piece down
    jal move_piece_down

    # 3) Check if game over
    jal check_gameover
    beq $v0, $zero, ContinueGame  # if v0 == 0, game not over, continue
    # Otherwise, game is over
    j game_over

ContinueGame:
    # 4) Draw
    jal draw_board
    jal draw_score

    # Simple delay to slow down the loop
    li $t1, 5000000          # Adjust to change speed
DelayLoop:
    addi $t1, $t1, -1
    bgtz $t1, DelayLoop

    # 5) Repeat
    j MainLoop

###########################################################################
# init_game
# Clear the board, set score to 0, lines to 0, generate first piece
###########################################################################
init_game:
    # Save return address
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    # Clear board array
    la $t0, board       # pointer to board
    li $t1, 200         # 20 rows * 10 cols
ClearLoop:
    sb $zero, 0($t0)    # store byte 0
    addi $t0, $t0, 1
    addi $t1, $t1, -1
    bgtz $t1, ClearLoop

    # Reset score and lines
    li $t2, 0
    sw $t2, score
    sw $t2, lines

    # Generate first piece
    jal generate_new_piece
    
    # Restore return address
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

###########################################################################
# generate_new_piece
# Picks a random piece from piecesArray, places it at top center
###########################################################################
generate_new_piece:
    # Save return address
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    # We'll do a simple pseudo-random: 
    # v0 = next random piece ID in [0..6]
    li $t1, 7
    jal get_random_in_range  # v0 = random 0..(t1-1)

    move $t2, $v0  # piece ID
    sw $t2, currentPieceID

    # Load piece definition into currentPiece (16 bytes)
    la $t3, piecesArray
    sll $t4, $t2, 2        # multiply ID by 4 to get offset
    add $t3, $t3, $t4      # pointer to the piece
    lw $t3, 0($t3)         # t3 now has the address of the piece data

    la $t5, currentPiece
    li $t6, 16
CopyPieceLoop:
    lb $t7, 0($t3)
    sb $t7, 0($t5)
    addi $t3, $t3, 1
    addi $t5, $t5, 1
    addi $t6, $t6, -1
    bgtz $t6, CopyPieceLoop

    # Position top-left X = 3 (somewhere near center of 10-col board)
    li $t0, 3
    sw $t0, currentPieceX
    # Position top-left Y = 0
    move $t0, $zero
    sw $t0, currentPieceY
    
    # Restore return address
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

###########################################################################
# move_piece_down
# Moves the current piece down by 1 if possible; otherwise locks it in place,
# checks for lines, and spawns a new piece.
###########################################################################
move_piece_down:
    # Save return address
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    # Save original Y
    lw $t0, currentPieceY
    addi $t1, $t0, 1  # Y+1
    sw $t1, currentPieceY

    # Check collision
    jal collision_detect
    beq $v0, $zero, NoCollision  # if no collision, done

    # If collision, revert Y
    sw $t0, currentPieceY

    # Lock piece in place
    jal lock_piece

    # Check lines
    jal check_full_lines

    # Generate a new piece
    jal generate_new_piece

NoCollision:
    # Restore return address
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

###########################################################################
# collision_detect
# Returns v0 = 1 if collision with board or bottom, else 0.
###########################################################################
collision_detect:
    # We'll iterate over 4x4 of currentPiece; any cell=1 => check board pos
    # If out of board or board cell != 0 => collision

    lw $t0, currentPieceX
    lw $t1, currentPieceY

    la $t2, currentPiece

    li $t3, 0           # row index in piece
CollisionRowLoop:
    li $t4, 0           # col index in piece
CollisionColLoop:
    # load piece cell
    sll $t6, $t3, 2               # row * 4
    add $t6, $t6, $t4
    add $t7, $t2, $t6
    lb $t7, 0($t7)                # piece cell

    beq $t7, $zero, SkipCell     # if cell=0, skip

    # compute board position
    # boardX = t0 + t4
    # boardY = t1 + t3
    add $t8, $t0, $t4
    add $t9, $t1, $t3

    # Check if out of bounds
    # if boardX < 0 or boardX >= 10 => collision
    # if boardY >= 20 => collision (top can't be < 0 if we spawn at y=0)
    bltz $t8, CollisionYes
    li $s0, 10
    bge $t8, $s0, CollisionYes
    li $s1, 20
    bge $t9, $s1, CollisionYes

    # Check if board cell is occupied
    # index = boardY * 10 + boardX
    mul $s2, $t9, $s0
    add $s2, $s2, $t8

    la $s3, board
    add $s3, $s3, $s2
    lb $s4, 0($s3)
    bne $s4, $zero, CollisionYes

SkipCell:
    addi $t4, $t4, 1
    blt $t4, 4, CollisionColLoop

    addi $t3, $t3, 1
    blt $t3, 4, CollisionRowLoop

    # No collision found
    move $v0, $zero
    jr $ra

CollisionYes:
    li $v0, 1
    jr $ra

###########################################################################
# lock_piece
# Writes the current piece cells into the board array
###########################################################################
lock_piece:
    lw $t0, currentPieceX
    lw $t1, currentPieceY

    la $t2, currentPiece

    li $t3, 0
LockRowLoop:
    li $t4, 0
LockColLoop:
    sll $t6, $t3, 2
    add $t6, $t6, $t4
    add $t7, $t2, $t6
    lb $t7, 0($t7)
    beq $t7, $zero, LockSkip

    # boardX = t0 + t4
    # boardY = t1 + t3
    add $t8, $t0, $t4
    add $t9, $t1, $t3

    # index = boardY * 10 + boardX
    li $s0, 10
    mul $s1, $t9, $s0
    add $s1, $s1, $t8

    la $s2, board
    add $s2, $s2, $s1
    sb $t7, 0($s2)

LockSkip:
    addi $t4, $t4, 1
    blt $t4, 4, LockColLoop

    addi $t3, $t3, 1
    blt $t3, 4, LockRowLoop

    jr $ra

###########################################################################
# check_full_lines
# Checks each row if it's fully occupied (all != 0). If so, remove it,
# move everything above it down, increment lines and score.
###########################################################################
check_full_lines:
    # Save return address
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    li $t0, 0         # row = 0
CheckRowLoop:
    # Check if row is full
    li $t1, 0         # col index
    li $t2, 1         # assume full
CheckColLoop:
    # index = row * 10 + col
    li $t6, 10
    mul $t7, $t0, $t6
    add $t7, $t7, $t1

    la $t8, board
    add $t8, $t8, $t7
    lb $t9, 0($t8)
    beq $t9, $zero, NotFull  # if any cell=0 => not full

    addi $t1, $t1, 1
    blt $t1, 10, CheckColLoop

    # If we reach here, row is full
    # Remove row, move everything above down by 1
    jal remove_row

    # increment lines
    lw $s0, lines
    addi $s0, $s0, 1
    sw $s0, lines

    # update score
    # Tetris scoring is more complex usually, but let's do +100 per line
    lw $s1, score
    addi $s1, $s1, 100
    sw $s1, score

    # Don't increment row because new row replaced old => check same row again
    j CheckRowLoop

NotFull:
    addi $t0, $t0, 1
    li $t4, 20
    blt $t0, $t4, CheckRowLoop
    
    # Restore return address
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

###########################################################################
# remove_row
# Shift all rows above the current $t0 down by 1.
###########################################################################
remove_row:
    # $t0 is the full row
    # We'll copy row-1 into row, row-2 into row-1, etc..., top row becomes empty
    move $a0, $t0

RemoveRowLoop:
    blez $a0, ClearTopRow   # if a0 <= 0, we're done shifting
    # for col in [0..9]
    li $t1, 0
RowShiftColLoop:
    # src index = (a0 - 1)*10 + t1
    li $t2, 10
    addi $t3, $a0, -1
    mul $t3, $t3, $t2
    add $t3, $t3, $t1

    # dst index = a0*10 + t1
    mul $t4, $a0, $t2
    add $t4, $t4, $t1

    la $t5, board
    add $t6, $t5, $t3
    lb $t7, 0($t6)

    add $t8, $t5, $t4
    sb $t7, 0($t8)

    addi $t1, $t1, 1
    blt $t1, 10, RowShiftColLoop

    addi $a0, $a0, -1
    j RemoveRowLoop

ClearTopRow:
    # Clear top row = row 0
    li $t1, 0
ClearTopRowLoop:
    la $t5, board
    add $t5, $t5, $t1
    sb $zero, 0($t5)
    addi $t1, $t1, 1
    li $t2, 10
    blt $t1, $t2, ClearTopRowLoop

    jr $ra

###########################################################################
# check_gameover
# If newly spawned piece collides immediately => game over
###########################################################################
check_gameover:
    # Save return address
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    # after generate_new_piece, if we have collision, we lose
    jal collision_detect
    move $v0, $v0   # if v0=1 => collision => game over
    
    # Restore return address
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

###########################################################################
# read_input
# Checks keyboard for WASD (or arrow keys) to move left, right, rotate, or drop.
###########################################################################
read_input:
    # Save return address
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    # Check if a key is available using MMIO
    lw $t0, KEYBOARD_READY
    beqz $t0, NoInput    # If no key is ready, return

    # Read the key
    lw $v0, KEYBOARD_DATA

    # Char in $v0
    # Let's interpret: 
    # 'a' => move left
    # 'd' => move right
    # 'w' => rotate
    # 's' => move down immediately
    # ' ' => drop (optional, we can skip)

    li $t1, 'a'
    beq $v0, $t1, MoveLeft
    li $t1, 'd'
    beq $v0, $t1, MoveRight
    li $t1, 'w'
    beq $v0, $t1, Rotate
    li $t1, 's'
    beq $v0, $t1, MoveDown
    li $t1, ' '
    beq $v0, $t1, HardDrop

    j NoInput

MoveLeft:
    jal move_left
    j NoInput

MoveRight:
    jal move_right
    j NoInput

Rotate:
    jal rotate_piece
    j NoInput

MoveDown:
    jal move_piece_down
    j NoInput

HardDrop:
    # Keep moving piece down until collision
    li $t2, 0  # Counter to prevent infinite loop
DropLoop:
    # Safety check - prevent infinite loop
    addi $t2, $t2, 1
    li $t3, 30  # Maximum iterations
    bge $t2, $t3, NoInput
    
    # Save current Y position to detect if we've moved
    lw $t0, currentPieceY
    
    # Try to move down
    jal move_piece_down
    
    # Check if Y position changed (if not, we've hit bottom)
    lw $t1, currentPieceY
    beq $t0, $t1, NoInput  # If Y didn't change, we're done dropping
    
    j DropLoop

NoInput:
    # Restore return address
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

###########################################################################
# move_left, move_right
###########################################################################
move_left:
    # Save return address
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    # x--
    lw $t0, currentPieceX
    addi $t0, $t0, -1
    sw $t0, currentPieceX

    # check collision
    jal collision_detect
    beq $v0, $zero, NoCollLeft

    # revert move
    lw $t0, currentPieceX
    addi $t0, $t0, 1
    sw $t0, currentPieceX

NoCollLeft:
    # Restore return address
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

move_right:
    # Save return address
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    lw $t0, currentPieceX
    addi $t0, $t0, 1
    sw $t0, currentPieceX

    # check collision
    jal collision_detect
    beq $v0, $zero, NoCollRight

    # revert
    lw $t0, currentPieceX
    addi $t0, $t0, -1
    sw $t0, currentPieceX

NoCollRight:
    # Restore return address
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

###########################################################################
# rotate_piece
# A simplistic "rotate left" or "rotate right" (here: always rotate clockwise).
# We'll read currentPiece, rotate in a temp buffer, then check collision.
# If collision, revert.
###########################################################################
rotate_piece:
    # Save return address
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    # We only store the piece in currentPiece (4x4). 
    # We'll do a 90-degree rotation: out[col][3-row] = in[row][col]
    la $t0, currentPiece
    addi $sp, $sp, -16
    move $t2, $sp         # temp buffer on stack to hold rotated cells

    li $t3, 0           # row
RotRowLoop:
    li $t4, 0           # col
RotColLoop:
    # inIndex = row*4 + col
    sll $t5, $t3, 2
    add $t5, $t5, $t4
    add $t6, $t0, $t5
    lb $t6, 0($t6)

    # outIndex = col*4 + (3 - row)
    li $t7, 3
    sub $t7, $t7, $t3
    sll $t8, $t4, 2
    add $t8, $t8, $t7
    add $t9, $t2, $t8
    sb $t6, 0($t9)

    addi $t4, $t4, 1
    blt $t4, 4, RotColLoop

    addi $t3, $t3, 1
    blt $t3, 4, RotRowLoop

    # Copy temp buffer back to currentPiece
    li $t7, 16
    la $t8, currentPiece
    move $t9, $sp
CopyRotBack:
    lb $s0, 0($t9)
    sb $s0, 0($t8)
    addi $t9, $t9, 1
    addi $t8, $t8, 1
    addi $t7, $t7, -1
    bgtz $t7, CopyRotBack

    # Check collision
    jal collision_detect
    beq $v0, $zero, NoCollRotate

    # revert by rotating 3 more times (or rotate CCW once). We'll do 3 more times for simplicity
    li $t1, 3
RevertLoop:
    jal rotate_piece_clockwise
    addi $t1, $t1, -1
    bgtz $t1, RevertLoop

NoCollRotate:
    addi $sp, $sp, 16
    # Restore return address
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# Helper to rotate piece clockwise once, used in revert loop
rotate_piece_clockwise:
    # Save return address
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    la $t0, currentPiece
    addi $sp, $sp, -16
    move $t2, $sp

    li $t3, 0           # row
RotRowLoop2:
    li $t4, 0           # col
RotColLoop2:
    sll $t5, $t3, 2
    add $t5, $t5, $t4
    add $t6, $t0, $t5
    lb $t6, 0($t6)

    li $t7, 3
    sub $t7, $t7, $t3
    sll $t8, $t4, 2
    add $t8, $t8, $t7
    add $t9, $t2, $t8
    sb $t6, 0($t9)

    addi $t4, $t4, 1
    blt $t4, 4, RotColLoop2

    addi $t3, $t3, 1
    blt $t3, 4, RotRowLoop2

    # copy back
    li $t7, 16
    la $t8, currentPiece
    move $t9, $sp
CopyRotBack2:
    lb $s0, 0($t9)
    sb $s0, 0($t8)
    addi $t9, $t9, 1
    addi $t8, $t8, 1
    addi $t7, $t7, -1
    bgtz $t7, CopyRotBack2

    addi $sp, $sp, 16
    # Restore return address
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

###########################################################################
# draw_board
# Prints out the board row by row, with borders
###########################################################################
draw_board:
    # Save return address
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    # Clear screen - print multiple newlines
    li $t0, 5
CLoop:
    lb $a0, CHAR_NEWLINE
    jal print_char
    addi $t0, $t0, -1
    bgtz $t0, CLoop

    li $t1, 0   # row
DrawRowLoop:
    lb $a0, CHAR_BORDER
    jal print_char

    li $t2, 0   # col
DrawColLoop:
    # index = row*10 + col
    li $t3, 10
    mul $t4, $t1, $t3
    add $t4, $t4, $t2
    la $t5, board
    add $t5, $t5, $t4
    lb $t6, 0($t5)

    beq $t6, $zero, PrintEmpty

    # Print block
    lb $a0, CHAR_BLOCK
    jal print_char
    j NextCell

PrintEmpty:
    lb $a0, CHAR_EMPTY
    jal print_char

NextCell:
    addi $t2, $t2, 1
    li $t7, 10
    blt $t2, $t7, DrawColLoop

    # Right border
    lb $a0, CHAR_BORDER
    jal print_char

    # New line
    lb $a0, CHAR_NEWLINE
    jal print_char

    addi $t1, $t1, 1
    li $t8, 20
    blt $t1, $t8, DrawRowLoop

    # Print bottom border
    lb $a0, CHAR_BORDER
    jal print_char
    li $t2, 0
BottomBorderLoop:
    lb $a0, CHAR_BOTTOM
    jal print_char
    addi $t2, $t2, 1
    li $t7, 10
    blt $t2, $t7, BottomBorderLoop
    lb $a0, CHAR_BORDER
    jal print_char
    lb $a0, CHAR_NEWLINE
    jal print_char
    
    # Restore return address
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

###########################################################################
# draw_score
# Prints out the score and lines cleared
###########################################################################
draw_score:
    # Save return address
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    # Print "Score: " ...
    la $a0, MSG_SCORE
    jal print_string

    # Print score number
    lw $a0, score
    jal print_int

    # Print " | Lines Cleared: "
    la $a0, MSG_LINES
    jal print_string

    # Print lines
    lw $a0, lines
    jal print_int

    # New line
    lb $a0, CHAR_NEWLINE
    jal print_char
    
    # Restore return address
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

###########################################################################
# game_over
# Print message, wait for Enter, then exit
###########################################################################
game_over:
    # Draw final board/score
    jal draw_board
    jal draw_score

    # Print message
    la $a0, MSG_GAMEOVER
    jal print_string

    # wait for enter
WaitEnter:
    lw $t0, KEYBOARD_READY
    beqz $t0, WaitEnter
    
    lw $t0, KEYBOARD_DATA
    li $t1, 10        # newline char
    beq $t0, $t1, ExitGame
    j WaitEnter

ExitGame:
    # exit
    li $v0, 10
    syscall

###########################################################################
# get_random_in_range
# input: $t1 = range max (exclusive)
# output: $v0 = random in [0..$t1-1]
###########################################################################
get_random_in_range:
    # We'll do a naive pseudo-random approach using $t0 (seed)
    # For simplicity, let's do $t0 = $t0 + 12345
    addi $t0, $t0, 12345

    # mod by t1
    div $t0, $t1
    mfhi $v0               # remainder = random in [0..t1-1]
    jr $ra
