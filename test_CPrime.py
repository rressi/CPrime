import itertools
import math
import random
import pyximport

pyximport.install()
from CPrime import prime_numbers, free_run
from CDividends import find_dividends


def prime_numbers_reference(num):

    numbers = [True for x in range(num)]

    k = int(math.sqrt(num))
    for x in range(2, k + 1):
        if numbers[x]:
            y = x * x
            while y < num:
                numbers[y] = False
                y += x

    return [x
            for x in range(2, num, 1)
            if numbers[x]]


def test_base():
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
