# CPrime, fast prime number generator

## Description

CPrime is a Python extension, written in Cython, that implements a function to
return all prime numbers below a passed maximum.

```python
import pyximport;
pyximport.install()
import CPrime

for x in CPrime.prime_numbers(10 ** 8):
  print('{} is prime'.format(x))
```

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


## Compiling extensions


You can compile CPrime extensions and its companion CDividends with the
following command:


```sh
python3 setup.py build_ext --inplace
```


## Performances

As a benchmark we execute the following in a python console:

```python
import timeit
timeit.timeit('import CPrime; CPrime.free_run(10**9)', number=1)
timeit.timeit('import CPrime; CPrime.free_run(10**10)', number=1)
```

### Results:

| CPU | OS  | Python | C compiler | 10 ^ 9 | 10 ^ 10 |
| --- | --- | ------ | ---------- | ------ | ------- |
| Intel i5-3335S @2.7GHz, 4 cores | Windows 10 | Python 3.4.3 | msvc 10 | 2.778s | 28.043s |
| Intel i5-3335S @2.7GHz, 4 cores | OSX Yosemite 10.4 | Python 3.4.1 | Apple LLVM 6.1.0 (LLVM 3.6) **no OpenMP** | 2.904s | 30.561s |
| Intel i5-3335S @2.7GHz, 4 cores | OSX Yosemite 10.4 | Python 2.7.2 | Apple LLVM 6.1.0 (LLVM 3.6) **no OpenMP** | 3.021s | 30.884s |
| Intel i5-3335S @2.7GHz, 4 cores | Ubuntu 12.04 LTS (virtualized inside OSX Yosemite 10.4 ) | Python 3.4.0 | gcc 4.8.4 | 4.068s | 39.704 |
| Intel i5-3335S @2.7GHz, 4 cores | Ubuntu 14.04 (virtualized inside OSX Yosemite 10.4 ) | Python 3.4.3 | gcc 4.9.2 | 3.131 | 31.251 |
