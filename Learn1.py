import math
import pyximport

pyximport.install()
from Learn1Fast import c_prime_numbers


def prime_numbers(num):

    numbers = [True for x in range(num)]

    k = int(math.sqrt(num))
    for x in range(2, k + 1):
        if numbers[x]:
            y = x * 2
            while y < num:
                numbers[y] = False
                y += x

    return [x
            for x in range(2, num, 1)
            if numbers[x]]


def test_prime_numbers(prime_numbers):
    for n in prime_numbers:
        for i in range(2, 1 + n // 2):
            assert (n / i) != float(n // i), \
                "{} is not prime, can divided by {}".format(n, i)


print(list(c_prime_numbers(100)))
print(prime_numbers(100))
