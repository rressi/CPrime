# CPrime, fast prime number generator

## Description

CPrime is a Python package that implements a function to return all prime
numbers below a passed maximum.

```python
import CPrime
for x in CPrime.prime_numbers(10 ** 8):
  print('{} is prime'.format(x))
```

It is implemented in Cython to maximize its efficiency:
- **Fast**: it is two order of magnitude faster than a reference implementation
  (see `test_CPrime.prime_numbers_reference`) because is a natively compiled
  python extension.
- **Lazy**: it calculates lazily results while returning them, this allow
  it to use a fixed amount of maximum memory and to avoid to block the calling
  thread for more than some milliseconds.
- **Hungry**: after the first block of prime numbers generated it calculates
  following blocks using multiple threads in parallel.
- **Simple**: the code is essentially Python with some borrowed constructs from C
  like structs, purely native cunctions, malloc/free, base types, static typing,
  parallel ranges. All of it written in a clean and simple way.
- **Portable**: the code is platform agnostic, works in any platform supported by
  Cython. It support either Python 3 either Python 2.


## Compiling CPrime


You can compile CPrime extension with the following command:


```sh
python3 setup.py build_ext --inplace
```

A python extension is build inside the whole folder that can be used by simply
importing `CPrime`


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
| Intel i5-3335S @2.7GHz, 4 cores | OSX Yosemite 10.4 | Python 3.4.1 | Apple LLVM 6.1.0 (LLVM 3.6) **no OpenMP** | 5.134s | 53.182s |
| Intel i5-3335S @2.7GHz, 4 cores | OSX Yosemite 10.4 | Python 2.7.6 | Apple LLVM 6.1.0 (LLVM 3.6) **no OpenMP** | 5.005s | 51.906s |
| Intel i5-3335S @2.7GHz, 4 cores | Ubuntu 12.04 LTS (virtualized inside OSX Yosemite 10.4 ) | Python 3.4.0 | gcc 4.8.4 | 4.068s | 39.704 |
| Intel i5-3335S @2.7GHz, 4 cores | Ubuntu 14.04 (virtualized inside OSX Yosemite 10.4 ) | Python 3.4.3 | gcc 4.9.2 | 3.131 | 31.251 |

From the results:
- There are no notable differencies between Python 2 and Python 3 because most of 
  the time is spent inside native C code.
- Since LLVM still does not support OpenMP we were not able to activate parallel
  execution under Apple OSX and as a conseguence results we'v obtained worst results.
- Probably virtual machines are reducing performances but we need more results to
  confirm it.


