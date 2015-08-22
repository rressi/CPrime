import cython
from cython.parallel cimport parallel, prange
from libc.stdlib cimport calloc, free
from os import cpu_count

ctypedef long long Long
ctypedef enum Result:
    SUCCESS = 0
    MEMORY_ERROR = -1
    STOP_ITERATION = -2
    VALUE_ERROR = -3
ctypedef enum Bool:
    FALSE = 0
    TRUE = 1

DEF BLOCK_SIZE = (10 ** 6)
cdef Long MAX_THREADS = cpu_count()


def raise_error(Result result):
    if result == MEMORY_ERROR:
        raise MemoryError()
    elif result == STOP_ITERATION:
        raise StopIteration()
    elif result == VALUE_ERROR:
        raise ValueError()


cdef Long _sqrt(Long x) nogil:
    cdef:
        Long y
    y = 0
    while y * y <= x:
        y += 1
    return y


ctypedef struct _FoundDividends:
    Long num_found  # Number of dividends found in the buffer
    Long size       # Size of the buffer


@cython.cdivision(True)
cdef _FoundDividends* _dividends(Long x, Long max_threads) nogil:
    cdef:
        Long block_size
        Long num_bytes
        _FoundDividends* result
        char *buffer
        Long num_found
        Long y

    # Allocates a buffer for found dividends:
    block_size = _sqrt(x) + 1
    num_bytes = sizeof(_FoundDividends) + sizeof(char) * block_size
    result = <_FoundDividends *>calloc(1, num_bytes)
    if not result:
        return NULL
    buffer = <char *>(result + 1)

    # Calculates dividends in parallel and fill the buffer:
    num_found = 0
    with parallel(num_threads=max_threads):
        for y in prange(2, block_size,
                        schedule='static'):
            if (x % y) == 0:
                buffer[y] = 1
                num_found += 1

    # Returns the found results:
    result.num_found = num_found
    result.size = block_size
    return result


cdef class _DividendsGenerator:
    """A sequence generator to calculate dividends of x."""

    cdef:
        Long x  # Target number whose dividends have to be found
        Long y  # Last dividend found
        Long i  # Counts the number od dividends found
        Long max_threads  # maximum number of threads that can be spared
        _FoundDividends* dividends

    def __init__(self, x, max_threads=MAX_THREADS):
        """Initializes the sequence generator.

        :param x: the target number whose dividends have to be found

        :param max_threads: maximum number of threads that can be spared
        """
        self.x = x
        self.y = 1
        self.i = 0
        self.max_threads = 0
        self.dividends = NULL

    def __iter__(self):
        return self

    def __dealloc__(self):
        free(self.dividends)

    def __next__(self):
        cdef:
            Long value
            Result result
        value = self.next()  # Executes a pure C compiled method.
        if value < 0:
            result = <Result>value
            raise_error(result)  # Converts an error to proper Python exception
        return value

    cdef Long next(self) nogil:
        cdef:
            Long y
            Long buffer_size
            char *buffer

        # At first step calculates all dividends:
        if not self.dividends:
            self.dividends = _dividends(self.x, self.max_threads)
            if not self.dividends:
                return MEMORY_ERROR

        # This check speeds up when there are few or no dividends:
        if self.i >= self.dividends.num_found:
            return STOP_ITERATION  # No more dividends have been found

        # Looks the next dividend to be returned:
        buffer_size = self.dividends.size
        buffer = <char *>(self.dividends + 1)
        for y in range(self.y + 1, self.dividends.size):
            if buffer[y]:
                break
        else:
            return STOP_ITERATION

        # Updates object state:
        self.y = y
        self.i += 1
        return y


def find_dividends(Long x, max_threads=MAX_THREADS):
    """Calculates all dividends of x.

    :param x: the target number whose dividends have to be found

    :param max_threads: maximum number of threads that can be spared

    :return a sequence generator containing dividends of it.
    """

    if x <= 0:
        raise ValueError('X must be strictly positive')

    return _DividendsGenerator(x, max_threads=max_threads)





