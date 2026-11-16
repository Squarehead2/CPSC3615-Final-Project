# Prime Number Finder
# CPSC 3615 — William Black, Darrel Nguyen, Lam Dao
#
# MIPS translation of python/prime_finder.py.
# Assemble and run this file in MARS (the instruction set and syscall
# numbers below match QtSpim as well).
#
# Read each procedure next to the Python function of the same name.
# PYTHON_TO_MIPS.md is the line-by-line translation guide.
#
# -----------------------------------------------------------------------
# What the program does
# -----------------------------------------------------------------------
# 1. Read an integer limit. Accept only MIN_LIMIT .. MAX_LIMIT.
# 2. Build a word array, sieve, where the index is the number:
#       0  prime candidate
#       1  composite
#    Slots 0 and 1 are marked composite. Slots 2 .. limit start as prime.
# 3. Sieve of Eratosthenes. For each prime p while p * p <= limit, mark
#    p*p, p*p+p, p*p+2p, ... as composite.
# 4. Print every index from 2 .. limit that is still 0.
#
# -----------------------------------------------------------------------
# Memory
# -----------------------------------------------------------------------
# sieve is (MAX_LIMIT + 1) words. Words are used so each element is a
# natural lw/sw. The address of sieve[i] is:
#
#     base + i * 4
#
# Multiplying by 4 is a left shift of 2, because 4 = 2^2:
#
#     sll  offset, i, 2
#     add  address, base, offset
#
# The index itself is the number, so the proposal's "number column" does
# not need its own words. The stored word is only the marked/unmarked
# status.
#
# -----------------------------------------------------------------------
# Registers
# -----------------------------------------------------------------------
#   $a0-$a1   arguments into a procedure. Not preserved across jal.
#   $v0       return value, and the syscall number during a syscall.
#   $t0-$t9   scratch. A procedure may overwrite these. Do not expect
#             them to survive a jal.
#   $s0-$s7   callee-saved. If a procedure writes one, it restores the
#             caller's value before jr $ra.
#   $ra       return address written by jal. Any procedure that uses jal
#             must save $ra first, or the nested call replaces it.
#   $sp       stack pointer. Grows toward smaller addresses.
#
# main keeps the two values that must survive calls:
#   $s0  limit
#   $s1  base address of sieve
#
# -----------------------------------------------------------------------
# Syscalls used (MARS / SPIM)
# -----------------------------------------------------------------------
#   1   print integer in $a0
#   4   print null-terminated string at $a0
#   5   read integer into $v0
#   10  exit
#
# -----------------------------------------------------------------------
# Stack
# -----------------------------------------------------------------------
# The frame size is a multiple of 8 so $sp stays double-word aligned,
# which is the convention MIPS uses for stack frames.

.data

# One word per number from 0 through MAX_LIMIT.
# (1000 + 1) * 4 = 4004 bytes. If MAX_LIMIT changes, change this too.
.align 2
sieve:      .space 4004

# Python's print() adds a newline. syscall 4 does not, so the newlines
# live in the strings that correspond to the end of a print().
prompt:     .asciiz "Enter the maximum number (2 to 1000): "
error_msg:  .asciiz "Error: enter an integer from 2 to 1000.\n"
header:     .asciiz "Prime numbers up to "
colon_nl:   .asciiz ":\n"
space_str:  .asciiz " "
newline:    .asciiz "\n"


# Named constants. .eqv is text substitution, like a Python name bound
# to an int. Keep these in agreement with python/prime_finder.py and
# with the numbers written in the strings above.
# MARS form: name, then value, no comma. The name is replaced with the
# number wherever it appears, the same way the Python names are used.
.eqv PRIME 0
.eqv COMPOSITE 1
.eqv MIN_LIMIT 2
.eqv MAX_LIMIT 1000


.text
.globl main


# -----------------------------------------------------------------------
# main
# Python: main()
#
#   sieve = [PRIME] * (MAX_LIMIT + 1)     # already reserved as `sieve`
#   limit = read_limit()
#   init_sieve(limit, sieve)
#   run_sieve(limit, sieve)
#   print_primes(limit, sieve)
# -----------------------------------------------------------------------
main:
    # Three saved registers: $ra, $s0, $s1. 16 bytes keeps 8-byte alignment.
    addi $sp, $sp, -16
    sw   $ra, 12($sp)
    sw   $s0, 8($sp)
    sw   $s1, 4($sp)

    jal  read_limit          # accepted limit comes back in $v0
    move $s0, $v0            # $s0 = limit, stable across later jal
    la   $s1, sieve          # $s1 = base address, stable across later jal

    # $a registers are arguments. Copy from $s on every call because the
    # callee, and the syscalls it makes, are free to overwrite $a0/$a1.
    move $a0, $s0
    move $a1, $s1
    jal  init_sieve

    move $a0, $s0
    move $a1, $s1
    jal  run_sieve

    move $a0, $s0
    move $a1, $s1
    jal  print_primes

    lw   $ra, 12($sp)
    lw   $s0, 8($sp)
    lw   $s1, 4($sp)
    addi $sp, $sp, 16

    # Stop the program. syscall 10 does not return.
    li   $v0, 10
    syscall


# -----------------------------------------------------------------------
# read_limit
# Python: read_limit()
#
# Ask until the integer in $v0 is between MIN_LIMIT and MAX_LIMIT.
# Return that integer in $v0.
#
# This procedure calls other procedures, so the $ra that main's jal
# stored is saved before the first nested jal.
# -----------------------------------------------------------------------
read_limit:
    addi $sp, $sp, -8
    sw   $ra, 4($sp)

read_loop:
    # Python: typed = input(prompt)
    la   $a0, prompt
    jal  print_string

    # Python: limit = int(typed). Syscall 5 blocks until an integer arrives.
    jal  read_int
    move $t0, $v0            # $t0 = candidate limit

    # Python: if limit < MIN_LIMIT or limit > MAX_LIMIT: reject
    # bgt/blt are pseudo-instructions. MARS expands each one into a
    # comparison plus a beq/bne. Both operands are registers here so the
    # compare is easy to see.
    li   $t1, MIN_LIMIT
    blt  $t0, $t1, read_bad

    li   $t1, MAX_LIMIT
    bgt  $t0, $t1, read_bad

    move $v0, $t0            # return value
    j    read_ok

read_bad:
    la   $a0, error_msg
    jal  print_string
    j    read_loop           # Python: continue

read_ok:
    lw   $ra, 4($sp)
    addi $sp, $sp, 8
    jr   $ra


# -----------------------------------------------------------------------
# init_sieve
# Python: init_sieve(limit, sieve)
#
# $a0 = limit
# $a1 = base address of sieve
#
# Leaf procedure: no jal, so $ra is still main's return address and the
# stack is left alone. $a0 and $a1 are only read, never overwritten.
# -----------------------------------------------------------------------
init_sieve:
    # sieve[0] = COMPOSITE. The base address is the address of element 0.
    li   $t2, COMPOSITE
    sw   $t2, 0($a1)

    # sieve[1] = COMPOSITE. Element 1 sits one word (4 bytes) later.
    sw   $t2, 4($a1)

    # i = 2
    li   $t0, 2

init_loop:
    # while i <= limit, written as "branch out when i > limit".
    bgt  $t0, $a0, init_done

    # address = base + i * 4
    sll  $t1, $t0, 2
    add  $t1, $a1, $t1

    # sieve[i] = PRIME
    li   $t3, PRIME
    sw   $t3, 0($t1)

    addi $t0, $t0, 1         # i = i + 1
    j    init_loop

init_done:
    jr   $ra


# -----------------------------------------------------------------------
# run_sieve
# Python: run_sieve(limit, sieve)
#
# $a0 = limit
# $a1 = base address of sieve
# $t0 = p
# $t4 = multiple
#
# Leaf procedure, same reason as init_sieve.
#
# p * p is computed with mul. For this program p never exceeds
# sqrt(MAX_LIMIT), and 1000 fits in a signed 32-bit product. A limit
# above about 46340 would wrap the product and break the comparison.
# -----------------------------------------------------------------------
run_sieve:
    li   $t0, 2              # p = 2

sieve_outer:
    # while p * p <= limit
    mul  $t1, $t0, $t0       # $t1 = p * p
    bgt  $t1, $a0, sieve_done

    # if sieve[p] != PRIME: skip to the next candidate
    sll  $t2, $t0, 2
    add  $t2, $a1, $t2
    lw   $t3, 0($t2)         # $t3 = sieve[p]
    # bne takes two registers. PRIME is loaded so the compare matches
    # the Python test "sieve[p] == PRIME" even though that value is 0.
    li   $t7, PRIME
    bne  $t3, $t7, next_p

    # multiple = p * p. $t1 still holds that product.
    move $t4, $t1

mark_loop:
    # while multiple <= limit
    bgt  $t4, $a0, next_p

    # sieve[multiple] = COMPOSITE
    sll  $t5, $t4, 2
    add  $t5, $a1, $t5
    li   $t6, COMPOSITE
    sw   $t6, 0($t5)

    add  $t4, $t4, $t0       # multiple = multiple + p
    j    mark_loop

next_p:
    addi $t0, $t0, 1         # p = p + 1
    j    sieve_outer

sieve_done:
    jr   $ra


# -----------------------------------------------------------------------
# print_primes
# Python: print_primes(limit, sieve)
#
# $a0 = limit on entry, then reused as the syscall argument.
# $a1 = base address on entry.
#
# Because print helpers are called inside the loop, the values that must
# survive those calls are moved into $s registers:
#   $s0 = i
#   $s1 = limit
#   $s2 = base address
# -----------------------------------------------------------------------
print_primes:
    addi $sp, $sp, -16
    sw   $ra, 12($sp)
    sw   $s0, 8($sp)
    sw   $s1, 4($sp)
    sw   $s2, 0($sp)

    move $s1, $a0            # limit
    move $s2, $a1            # sieve base

    # Python: print(f"Prime numbers up to {limit}:")
    # Three syscalls, because a MIPS print is either a string or an int.
    la   $a0, header
    jal  print_string
    move $a0, $s1
    jal  print_int
    la   $a0, colon_nl
    jal  print_string

    li   $s0, 2              # i = 2

print_loop:
    bgt  $s0, $s1, print_done

    # Load sieve[i] and print i only when the word is still PRIME.
    sll  $t0, $s0, 2
    add  $t0, $s2, $t0
    lw   $t1, 0($t0)
    li   $t2, PRIME
    bne  $t1, $t2, print_next

    move $a0, $s0
    jal  print_int
    la   $a0, space_str
    jal  print_string

print_next:
    addi $s0, $s0, 1         # i = i + 1
    j    print_loop

print_done:
    # Python: print()  — the newline after the row of primes.
    la   $a0, newline
    jal  print_string

    lw   $ra, 12($sp)
    lw   $s0, 8($sp)
    lw   $s1, 4($sp)
    lw   $s2, 0($sp)
    addi $sp, $sp, 16
    jr   $ra


# -----------------------------------------------------------------------
# Tiny syscall wrappers.
#
# Each one is a leaf. The caller puts the syscall argument in $a0.
# $v0 is both the syscall number and, for read_int, the value read.
# Keeping syscalls in one place means the sieve procedures show the
# algorithm instead of the service numbers.
# -----------------------------------------------------------------------

# Python: print(text) with no extra newline. $a0 = address of the string.
print_string:
    li   $v0, 4
    syscall
    jr   $ra

# Python: print(number). $a0 = the integer.
print_int:
    li   $v0, 1
    syscall
    jr   $ra

# Python: int(input()). Result is left in $v0 for the caller.
read_int:
    li   $v0, 5
    syscall
    jr   $ra
