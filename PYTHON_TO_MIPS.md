# Translating the Prime Finder from Python to MIPS

The Python file is the algorithm. The assembly file is that same algorithm
expressed with registers, memory addresses, and branches. Procedure names
match function names, and the loops branch at the same decisions.

| File | Role |
| --- | --- |
| `python/prime_finder.py` | Run and read this first. |
| `mips/prime_finder.asm` | Translation, written for MARS. |
| This guide | The rules that turn one into the other. |

## Run the Python program

From the project root:

```text
python python/prime_finder.py
```

Enter an integer from 2 through 1000. Values outside that range, and
tokens that are not integers, are rejected and the prompt repeats.

```text
Enter the maximum number (2 to 1000): 10
Prime numbers up to 10:
2 3 5 7
```

A space follows each prime, including the last one.

## Run the assembly program

1. Open `mips/prime_finder.asm` in MARS.
2. Assemble (F3), then Run (F5).
3. Type the limit in the Run I/O pane and press Enter.

MARS syscall 5 reads an integer. The range test is the validation both
programs share. After a run, the Data Segment row for the label `sieve`
is the map: word `i` is 0 when `i` is prime and 1 when `i` is composite.

QtSpim accepts this file as well. The syscall numbers are the standard
SPIM set.

## How a line of Python becomes instructions

MIPS has no list type, no `print`, and no `while` syntax. Each Python
feature used in `prime_finder.py` has one fixed replacement.

| Python | MIPS |
| --- | --- |
| `def name(...):` | A label `name:` and `jr $ra` at each exit. |
| `name(...)` | Put arguments in `$a0`, `$a1`, then `jal name`. The return value is `$v0`. |
| A local that must survive a call | An `$s` register. Save the old `$s` on entry and restore it before `jr $ra`. |
| A local used only inside one straight stretch | A `$t` register. Assume any `jal` destroys it. |
| `sieve[i]` | `address = base + i * 4`, then `lw` or `sw` at `0(address)`. |
| `sieve[i] = value` | `sw value, 0(address)`. |
| `while condition:` | A label at the top, a branch past the body when the condition fails, and a `j` back to the label at the bottom. |
| `if condition:` | A branch that skips the body when the condition is false. |
| `input()` / `int(...)` | `li $v0, 5` / `syscall`. The integer comes back in `$v0`. |
| `print(text)` | `li $v0, 4` / `la $a0, text` / `syscall`. The string is a `.asciiz` in `.data`. Python adds a newline; the syscall does not, so `\n` is part of the string when a newline is wanted. |
| `print(number)` | `li $v0, 1` / `move $a0, number` / `syscall`. |
| A fixed list of integers | `.space` bytes in `.data`, or a word computed into a register. |
| `MIN_LIMIT`, `PRIME`, and the other names | `.eqv` at the top of the assembly file. `.eqv` pastes the number in where the name appears. |

`bgt`, `blt`, `move`, `li`, and `mul` are pseudo-instructions. MARS
expands them into the real comparison, add, and multiply instructions.
They are the right level for this program: each one is still one idea
from the Python line.

## Calls and the stack

`jal` writes the return address into `$ra`. A procedure that itself uses
`jal` must save `$ra` first, or the inner call overwrites the address
needed to get back to the caller.

```text
procedure:
    addi $sp, $sp, -8      # make a frame; $sp grows downward
    sw   $ra, 4($sp)       # keep main's return address
    jal  some_helper       # this jal replaces $ra
    lw   $ra, 4($sp)       # put main's address back
    addi $sp, $sp, 8
    jr   $ra
```

`init_sieve` and `run_sieve` never call anything, so they leave the stack
alone. `read_limit`, `print_primes`, and `main` do call, so they open a
frame. Frame sizes are multiples of 8 bytes.

`$s0` in `main` is the limit and `$s1` is the base of `sieve`. Argument
registers `$a0` and `$a1` are copied from those two immediately before
each `jal`, because a call is allowed to overwrite `$a`.

## The array

`sieve[i]` means "the status of the number i".

```text
index:   0   1   2   3   4   5   6   7   8   9  10
byte:    0   4   8  12  16  20  24  28  32  36  40
```

Byte offset = index × 4. The shift `sll offset, i, 2` is that multiply.
The add of the base is what makes it a real address. Every `sieve[i]`
in the Python file becomes that pair plus a load or a store:

```text
sll  $t1, $t0, 2        # i * 4
add  $t1, $a1, $t1      # base + offset
lw   $t3, 0($t1)        # read sieve[i]
sw   $t3, 0($t1)        # write sieve[i]
```

The block is `(MAX_LIMIT + 1) * 4` bytes, 4004 with the current cap,
because index 0 is a real element. `.space` fills those bytes with zero,
and `init_sieve` still writes every used slot so the initialization loop
is visible and a later edit cannot inherit a stale mark.

0 means prime candidate. 1 means composite. Using a word per number,
instead of a byte, keeps every access on `lw` and `sw`.

## The sieve, in the same order as the code

`init_sieve` writes 1 into indexes 0 and 1, then 0 into indexes 2 through
`limit`.

`run_sieve` then does this, matching the Python `while` loops:

```text
p = 2
while p * p <= limit:
    if sieve[p] == PRIME:
        multiple = p * p
        while multiple <= limit:
            sieve[multiple] = COMPOSITE
            multiple = multiple + p
    p = p + 1
```

`p * p <= limit` is the proposal's rule "stop once the candidate passes
the square root of the limit," without a square-root instruction.
Starting at `p * p` is the other half of that optimization: multiples
smaller than `p * p` were already marked by a smaller prime.

The assembly outer loop is the same test, inverted so the branch leaves
the loop:

```text
sieve_outer:
    mul  $t1, $t0, $t0          # p * p
    bgt  $t1, $a0, sieve_done   # exit when p * p > limit
    ...
    addi $t0, $t0, 1
    j    sieve_outer
```

## Walk-through for limit 10

After `init_sieve`, the words are:

```text
index   0  1  2  3  4  5  6  7  8  9  10
value   1  1  0  0  0  0  0  0  0  0   0
```

- `p = 2`. `4 <= 10`, and `sieve[2]` is 0. Mark 4, 6, 8, 10.
- `p = 3`. `9 <= 10`, and `sieve[3]` is 0. Mark 9.
- `p = 4`. `16 > 10`. The outer loop ends. Index 4 is composite, so it
  would have been skipped even if the loop had continued. Its multiples
  are already multiples of 2.

```text
index   0  1  2  3  4  5  6  7  8  9  10
value   1  1  0  0  1  0  1  0  1  1   1
```

`print_primes` walks from 2 to 10 and prints the indexes that still hold
0: `2 3 5 7`.

Address check for the store that marks 9, if `sieve` sits at
`0x10010000`:

```text
offset  = 9 * 4 = 36 = 0x24
address = 0x10010000 + 0x24 = 0x10010024
```

In the Data Segment, that word becomes 1.

## Boundaries the program is built to show

| Input | Result |
| --- | --- |
| 2 | One prime, `2`. The outer sieve loop does not run, because `2 * 2 > 2`. |
| 3 | `2 3`. Same reason: `4 > 3`. |
| 4 | `2 3`. `p = 2` marks 4, then `3 * 3 > 4`. |
| 1, 0, negatives, 1001 and above | Error line, then the prompt again. |
| 1000 | Accepted. This is the largest map the `.space` block can describe. |

## Keep the two files in step

- `MIN_LIMIT`, `MAX_LIMIT`, `PRIME`, and `COMPOSITE` exist in both files.
- The prompt and the error text in `.data` repeat the numeric bounds.
  `.eqv` cannot splice a number into a string.
- `sieve: .space 4004` is `(MAX_LIMIT + 1) * 4`.
- A MIPS `p * p` must stay inside a signed 32-bit register. The cap of
  1000 guarantees that. Raising the cap past 46340 needs a wider multiply
  and a different comparison.
