import cython
from cython.parallel cimport parallel, prange
from libc.stdlib cimport calloc, free
from os import cpu_count

ctypedef int Long

DEF BLOCK_SIZE = (10 ** 6)
cdef Long MAX_THREADS = cpu_count()

cdef Long _log10(Long x) nogil:
    cdef:
        Long y
        Long z
    y = 0
    z = 10
    while z <= x:
        z *= 10
        y += 1
    return y

ctypedef struct _Task:
    Long x_min
    Long x_max
    Long* begin
    Long* end
    char* cache
    Long last_cleared

cdef void _task_free(_Task *self) nogil:
    if self.begin:
        free(self.begin)
        self.begin = NULL
    self.end = NULL
    self.cache = NULL

@cython.cdivision(True)
cdef int _task_alloc(_Task *self) nogil:
    cdef:
        Long block_size
        Long max_results
        Long num_bytes
    if self.cache != NULL:
        return 1  # Already allocated

    block_size = self.x_max - self.x_min
    max_results = block_size // _log10(block_size)

    num_bytes = max_results * sizeof(Long)
    num_bytes += block_size * sizeof(char)
    self.begin = <Long *>calloc(1, <size_t>num_bytes)
    if not self.begin:
        return 0  # Failure
    self.end = self.begin
    self.cache = <char *>(self.begin + max_results)
    self.last_cleared = 0

    return 1  # Success

cdef inline int _task_is_prime(const _Task *self, Long x) nogil:
    return self.cache[x - self.x_min] == 0

@cython.cdivision(True)
cdef inline int _task_clear_products(_Task *self,
                                     Long x) nogil:
    cdef:
        Long y

    # Finds the first product of x to be cleared:
    y = max(x * x,                          # First one from itself
            self.x_min + x - (self.x_min % x))  # First one from x_min
    if y >= self.x_max:
        return 0  # End of boundary reached

    while y < self.x_max:
        self.cache[y - self.x_min] = 1
        y += x
    return 1  # Success

cdef inline void _task_push_back(_Task *self, Long x) nogil:
    self.end[0] = x
    self.end += 1

cdef Long _task_execute(_Task *self, const _Task *source) nogil:
    cdef:
        Long x_max
        Long* src_it
        Long* src_end
        Long y
        Long x

    x_max = self.x_max

    # A: uses prime numbers from source to mark their products as non primes:
    src_it = source.begin + self.last_cleared
    src_end = source.end
    if src_it < src_end:
        while src_it < src_end:
            y = src_it[0]
            if not _task_clear_products(self, y):
                break  # Out of bound reached.
            src_it += 1
        self.last_cleared = src_it - source.begin
        x_max = min(x_max, (y * y))

    # B: all elements [x, x_max) untouched by step A are prime numbers:
    x = self.x_min
    if self.begin < self.end:
        x = 2 + self.end[-1]  # Continues from previous iteration
    else:
        x += (1 - (x % 2))  # If even, moves x to the next odd number
    while x < x_max:
        if _task_is_prime(self, x):
            _task_push_back(self, x)
        x += 2  # Evaluates only odd numbers

    return x_max  # Success!


cdef class _TaskIter:

    cdef:
        _Task* tasks
        _Task* task_it
        _Task* task_end
        Long* result_it

    def __cinit__(self):
        self.tasks = NULL
        self.task_it = NULL
        self.task_end = NULL
        self.result_it = NULL

    cdef clear(self):
        cdef:
            _Task* task_it
            _Task* task_end
        task_it = self.tasks
        task_end = self.task_end
        while task_it < task_end:
            _task_free(task_it)
            task_it += 1
        free(self.tasks)
        self.tasks = NULL
        self.task_it = NULL
        self.task_end = NULL
        self.result_it = NULL

    cdef void sink_tasks(self, Long num_tasks, _Task* tasks):
        self.clear()
        self.tasks = tasks
        self.task_it = tasks
        self.task_end = tasks + num_tasks

    cdef void start(self):
        self.result_it = NULL
        if self.task_it < self.task_end:
            if self.task_it.begin < self.task_it.end:
                self.result_it = self.task_it.begin

    def __dealloc__(self):
        self.clear()

    def __iter__(self):
        return self

    def __next__(self):
        cdef:
            Long result

        if self.result_it == NULL:
            raise StopIteration()

        if self.result_it == self.task_it.end:
            _task_free(self.task_it)
            self.result_it = NULL
            while self.task_it < self.task_end:
                if self.task_it.begin < self.task_it.end:
                    self.result_it = self.task_it.begin
                    break
                self.task_it += 1
            else:
                raise StopIteration()

        result = self.result_it[0]
        self.result_it += 1
        return result


@cython.cdivision(True)
def c_prime_numbers(Long num,
                    Long max_threads=MAX_THREADS):
    cdef:
        Long num_tasks
        Long num_failures
        _Task *tasks = NULL
        _Task *task0 = NULL
        Long x
        Long i
        Long block_size

    # Generates a vector of tasks:
    num_tasks = 1 + ((num - 1) // BLOCK_SIZE)
    tasks = <_Task *> calloc(sizeof(_Task),
                             <size_t>num_tasks)
    if tasks:
        # This python object will magically deallocate user memory when
        # destroyed:
        results = _TaskIter()
        results.sink_tasks(num_tasks, tasks)
    else:
        raise MemoryError('Cannot allocate task array')
    with nogil:
        x = 0
        i = 0
        while x < num:
            block_size = min(num - x, BLOCK_SIZE)
            tasks[i].x_min = x
            tasks[i].x_max = x + block_size
            x += block_size
            i += 1

    # Executes task 0:
    task0 = tasks + 0
    if not _task_alloc(task0):
        raise MemoryError('Cannot allocate buffers for task 0')
    with nogil:
        _task_push_back(task0, 2)
        _task_push_back(task0, 3)
        _task_push_back(task0, 5)
        _task_push_back(task0, 7)
        while _task_execute(task0, task0) < task0.x_max:
            pass

    # Potentially parallel executions:
    if num_tasks > 1:
        num_failures = 0
        with nogil, parallel(num_threads=max_threads):
            for i in prange(1, num_tasks):
                if _task_alloc(tasks + i):
                    _task_execute(tasks + i, task0)
                else:
                    num_failures += 1
        if num_failures:
            raise MemoryError('Cannot allocate buffers for {} tasks'
                              .format(num_failures))

    # Success!
    results.start()
    return results
