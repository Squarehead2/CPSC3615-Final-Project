"""
Prime Number Finder
CPSC 3615 — William Black, Darrel Nguyen, Lam Dao

Reference implementation of the Sieve of Eratosthenes.

This file is the algorithm the MIPS program in ../mips/prime_finder.asm
translates. Each function has the same name and the same control flow as
the matching procedure. Loops are written as "while" loops so they become
a label, a branch, and a jump, which is how MIPS expresses repetition.

The guide in ../PYTHON_TO_MIPS.md explains the translation rule by rule.
Read a function here, then the procedure of the same name in the .asm file.

Data layout
-----------
sieve[i] describes the number i. The index is the number, so a second
column of "the number itself" is unnecessary. That is the proposal's
two-column map (number, marked/unmarked) stored the way MIPS wants it:
one word per number.

    sieve[i] == PRIME (0)      the number i is still a prime candidate
    sieve[i] == COMPOSITE (1)  the number i has been marked composite

Only indexes 0 through the user's limit are used. The list is allocated
at its maximum size up front, the same way the assembly file reserves
a fixed block with .space. MIPS cannot grow an array with append().

Register roles used by the assembly version of each function are listed
in that function's docstring. Those notes are the bridge between the
two files.
"""

# Inclusive bounds checked before any sieve work. The assembly file
# repeats these with .eqv and in the prompt strings. Change them together.
MIN_LIMIT = 2
MAX_LIMIT = 1000

# Stored as integers, not Python bools, because a MIPS word holds a number.
# 0 is convenient: cleared memory (MARS .space) already contains 0.
PRIME = 0
COMPOSITE = 1

# A MIPS word is 4 bytes. Assembly turns "index * 4" into "shift left 2".
WORD_BYTES = 4


def read_limit():
    """
    Ask until the user enters an integer from MIN_LIMIT through MAX_LIMIT.

    MIPS procedure: read_limit
        Saves $ra on the stack, because this routine calls print/read helpers.
        Returns the accepted limit in $v0.
        $t0 holds the integer just read while it is compared.
        $t1 holds the bound it is compared against.

    Python-only behavior: a non-integer (letters, a blank line) raises
    ValueError and is rejected with the same message as an out-of-range
    number. MARS syscall 5 reads an integer; the range test below is the
    check both programs share. End-of-file has no MIPS counterpart; MARS
    simply waits until a number is typed.
    """
    prompt = f"Enter the maximum number ({MIN_LIMIT} to {MAX_LIMIT}): "
    error = f"Error: enter an integer from {MIN_LIMIT} to {MAX_LIMIT}."

    # Assembly: read_loop label. The branch back to it is the "continue".
    while True:
        try:
            # Assembly: jal print_string, then jal read_int. Result in $v0.
            typed = input(prompt)
            limit = int(typed)
        except ValueError:
            # Assembly has no ValueError path. See the docstring.
            print(error)
            continue
        except EOFError:
            raise SystemExit("No valid limit was entered.")

        # Assembly: blt limit, MIN_LIMIT, read_bad
        #           bgt limit, MAX_LIMIT, read_bad
        # A failing compare prints the error and jumps to read_loop.
        if limit < MIN_LIMIT or limit > MAX_LIMIT:
            print(error)
            continue

        # Assembly: move the accepted value into $v0, restore $ra, jr $ra.
        return limit


def init_sieve(limit, sieve):
    """
    Mark 0 and 1 composite, and mark 2..limit as prime candidates.

    MIPS procedure: init_sieve  (leaf: it calls nothing, so $ra stays put)
        $a0 = limit
        $a1 = base address of sieve
        $t0 = i
        $t1 = address of sieve[i], computed as base + i * WORD_BYTES
        $t2 = COMPOSITE

    0 and 1 are not prime. Every later index starts unmarked so the sieve
    can cross off composites. Cells past `limit` are never read.
    """
    # Assembly: address of sieve[0] is the base itself.
    #           address of sieve[1] is base + 4.
    sieve[0] = COMPOSITE
    sieve[1] = COMPOSITE

    # Assembly: li $t0, 2 / init_loop / bgt $t0, $a0, init_done
    i = 2
    while i <= limit:
        # Assembly:
        #   sll $t1, $t0, 2        # i * 4, because a word is 2^2 bytes
        #   add $t1, $a1, $t1      # base + offset
        #   sw  PRIME, 0($t1)
        sieve[i] = PRIME
        i = i + 1


def run_sieve(limit, sieve):
    """
    Cross off composite numbers using the Sieve of Eratosthenes.

    MIPS procedure: run_sieve  (leaf)
        $a0 = limit
        $a1 = base address of sieve
        $t0 = p, the current candidate
        $t1 = p * p, also used as a scratch address
        $t3 = sieve[p]
        $t4 = multiple, the index currently being marked

    Two limits keep the loops small, which is the optimization in the
    proposal:

      1. The outer loop stops once p * p exceeds the limit. Any composite
         n <= limit has a factor at most sqrt(n), so every composite is
         marked by the time p passes that point. Comparing p * p with the
         limit avoids a square-root instruction.
      2. Marking for a prime p starts at p * p, then steps by p. Smaller
         multiples of p were already marked by a smaller prime.

    Composites are skipped as candidates. Every multiple of 4 is already
    a multiple of 2, and the same is true for every later composite.

    Overflow note for assembly: p * p must fit in a signed 32-bit register.
    sqrt(2^31 - 1) is about 46340. MAX_LIMIT is 1000, so the product fits.
    """
    # Assembly: li $t0, 2 / sieve_outer / mul / bgt product, limit, sieve_done
    p = 2
    while p * p <= limit:
        # Assembly: load sieve[p]. bne that word, PRIME, next_p
        # PRIME is 0, so "still a candidate" means the word is zero.
        if sieve[p] == PRIME:
            # First multiple that might still be unmarked.
            multiple = p * p

            # Assembly: mark_loop / bgt $t4, $a0, next_p
            while multiple <= limit:
                # Same address math as init_sieve: base + multiple * 4.
                sieve[multiple] = COMPOSITE
                multiple = multiple + p

        # Next candidate, whether or not this p was prime.
        p = p + 1


def print_primes(limit, sieve):
    """
    Walk the finished map and print every index whose word is still PRIME.

    MIPS procedure: print_primes
        Calls print_string and print_int, so it saves $ra and the $s
        registers it uses:
            $s0 = i
            $s1 = limit
            $s2 = base address of sieve
        $t registers are not safe across a jal. The index and the base
        have to live in $s registers, which the procedure restores before
        returning.

    A space follows each prime. The final print() supplies the newline.
    MARS does not add a newline on its own: the assembly version prints
    a "\\n" string after the loop. See PYTHON_TO_MIPS.md.
    """
    # Assembly splits this into three syscalls: the leading text, the
    # integer limit, and the string ":\\n".
    print(f"Prime numbers up to {limit}:")

    # Assembly: li $s0, 2 / print_loop / bgt $s0, $s1, print_done
    i = 2
    while i <= limit:
        if sieve[i] == PRIME:
            # Assembly: jal print_int with $a0 = i, then jal print_string
            # on a single space. print() here does both.
            print(i, end=" ")
        i = i + 1

    print()


def main():
    """
    Reserve the map, read a limit, build the sieve, and print the primes.

    MIPS procedure: main
        $s0 = limit, kept across jal because $a0 is overwritten by calls
        $s1 = base address of sieve (la $s1, sieve)
        Before each jal, those values are copied into $a0 and $a1.
    """
    # Assembly reserves this block in the .data section:
    #   sieve: .space (MAX_LIMIT + 1) * WORD_BYTES
    # Index 0 is a real slot, so the length is MAX_LIMIT + 1, not MAX_LIMIT.
    sieve = [PRIME] * (MAX_LIMIT + 1)

    limit = read_limit()
    init_sieve(limit, sieve)
    run_sieve(limit, sieve)
    print_primes(limit, sieve)


if __name__ == "__main__":
    main()
