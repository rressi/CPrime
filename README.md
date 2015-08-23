# CPrime, fast prime number generator

## Description

CPrime is a Python extension, written in Cython, that implements a function to
return all prime numbers below a passed maximum.

The implementations takes advantage of the following:
- *two order of magnitude faster*: thanks to Cython's' ability to generate
  native it is about 100 times faster than a reference implementation (see
  `test_CPrime.prime_numbers_reference`)
- *few memory, huge numbers*: it lazily calculates prime number so that
  does not need huge buffers up front for huge ranges. Actual memory
  requirements are at most tens of megabytes.
- *parallel execution*: internally it splits the job into tasks of up to one
  million elements and can execute them in parallel when needed. GIL is not
  taken in performance critical loops so that it can also work fine with other
  parallel tasks.
- *keep it simple*: the code is essentially Python with some borrowed
  constructs from C: structs, malloc/free, base types, static typing.

