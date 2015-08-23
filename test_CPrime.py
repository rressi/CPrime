import itertools
import math
import random
import pyximport

pyximport.install()
from CPrime import prime_numbers, free_run
from CDividends import find_dividends


def prime_numbers_reference(num):
    """A reference implementation of a prime number generator.

    For num=10**7 it is 105 times slower than CPrime.prime_numbers
    on a CPU Intel i5 3335S @ 2.7GHz and 4 physical cores.

    More over needs much more memory to be allocated in advance, on
    an 8Gb machine it can raise a memory error already with num=10**8.
    """
    assert(num >= 2)

    # Allocates a buffer of booleans for the range [0, num),
    # each boolean will tell as if a number is prime or not:
    numbers = [True for x in range(num)]

    # From the range [3, sqrt(num)] we set to false (non prime)
    # all multiplicand of each number found that is still marked
    # as prime (we consider only odd numbers):
    k = int(math.sqrt(num))
    for x in range(3, k + 1, 2):
        if numbers[x]:
            y = x * x   # Multiplicands < x**2 have already been set
            while y < num:
                numbers[y] = False
                y += x   # Next multiplicand.

    # Now we collect and return all the values for witch a multiplicand
    # has not been found:
    result = [2]
    result.extend(x
                  for x in range(3, num, 2)
                  if numbers[x])
    return result


def test_base():
    """Base unit test for CPrime.prime_numbers()"""

    # Up to 10**7 e use a reference (but slow) implementation to test oru
    # fast algorithm:
    for order in range(1, 8):
        print('Order {}:'.format(order))
        max_number = 10 ** order
        prod_result = list(prime_numbers(max_number))
        ref_result = prime_numbers_reference(max_number)
        print('  PROD: ', prod_result[:100], '...' if order > 2 else '')
        print('  REF:  ', ref_result[:100], '...' if order > 2 else '')
        assert prod_result == ref_result
    # From 10**8 to 10**10 we just generate numbers and test some random subset
    # of them:
    for order in range(8, 11):
        print('Order {}:'.format(order))
        print('  Executing...')
        max_number = 10 ** order
        results = [0 for x in range(1000)]
        for x in prime_numbers(max_number):
            results[random.randint(0, 999)] = x
        print('  Evaluating {} results'.format(len(results)))
        for x in results:
            test_prime_number(x)


def test_prime_number(x):
    print('  Testing {}'.format(x))
    dividends = list(itertools.islice(find_dividends(x), 101))
    if dividends:
        print('    DIVIDENDS: ',
              dividends[100:],
              '...' if len(dividends) > 100 else '')
        assert False, "{} is not prime".format(x)


if __name__ == '__main__':
    test_base()
