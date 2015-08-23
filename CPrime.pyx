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

# ------------------------------------------------------------------------------

def prime_numbers(Long number,
                  Long max_threads=MAX_THREADS):
    """Calculates all prime numbers that are less than the passed one.

    :param number: the maximum number

    :param max_threads: the maximum number of threads that can be spared
    concurrently. If not passed number of current CPU cores is used.

    :return: a strictly sorted sequence of prime numbers.
    """
    cdef:
        Result result
    # Creates and return a prime number generator:
    generator = _PrimeGenerator()
    result = generator.create_tasks(number, max_threads)
    if result != SUCCESS:
        _raise_error(result)  # Failure.

    return generator  # Success.


def free_run(Long number, Long max_threads=MAX_THREADS):
    """This function executes generation of prime numbers in a purely native
    internal loop in order to measure the speed of our generator.

    :param number: the maximum number

    :param max_threads: the maximum number of threads that can be spared
    concurrently. If not passed number of current CPU cores is used.
    """
    cdef:
        _PrimeGenerator seq
    seq = prime_numbers(number=number,
                        max_threads=max_threads)
    with nogil:
        # Our free run:
        while seq.next() >= 0:
            pass

# ------------------------------------------------------------------------------

cdef class _PrimeGenerator:
    """
    This class implements a Python sequence generator in order to lazily
    calculate prime numbers during its iteration.

    Prime numbers are calculated over bunches of BLOCK_SIZE integer numbers
    and returned in a sorted order.
    """

    cdef:
        Long max_threads
        _Task* tasks
        _Task* task_it
        _Task* task_end
        Long* result_it
        Long* result_end

    def __init__(self):
        """Constructor."""
        self.max_threads = 1
        self.tasks = NULL
        self.task_it = NULL
        self.task_end = NULL
        self.result_it = NULL
        self.result_end = NULL

    def __dealloc__(self):
        """Destructor."""
        self.clear()

    def __iter__(self):
        return self

    def __next__(self):
        cdef:
            Long value
            Result result
        value = self.next()  # The step is executed by a purely native method.
        if value < 0:
            result = <Result>value
            _raise_error(result)
        return value

    cdef Result create_tasks(self, Long number, Long max_threads) nogil:
        """
        Given the maximum number where the iterator should stop (up to
        10 ** 12), it allocates the necessary tasks.

        This method should be called just after the object construction.

        :param number: maximum number where the iteration should stop.
        :param max_threads: maximum number of threads to be used concurrently.

        :return:
        - SUCCESS on success.
        - VALUE_ERROR if number is <= 1
        - MEMORY_ERROR if a memory allocation failure happened.
        """
        cdef:
            Long num_tasks
            _Task* tasks = NULL
            Long x
            Long i
            Long block_size
        try:
            if number <= 1:  # Precondition
                return VALUE_ERROR

            self.clear()  # Ensures this object is in a clear state

            # Allocates the vector of tasks:
            num_tasks = 1 + ((number - 1) // BLOCK_SIZE)
            tasks = <_Task *> calloc(sizeof(_Task),
                                     <size_t>num_tasks)
            if not tasks:
                return MEMORY_ERROR

            # Fills it with task input parameters:
            x = 0
            i = 0
            while x < number:
                block_size = min(number - x, BLOCK_SIZE)
                tasks[i].x_min = x
                tasks[i].x_max = x + block_size
                x += block_size
                i += 1

            # Updates object status:
            self.max_threads = max_threads
            self.tasks, tasks = tasks, NULL
            self.task_it = self.tasks
            self.task_end = self.tasks + num_tasks

            return SUCCESS

        finally:
            free(tasks)  # Allocates if not null.

    cdef void clear(self) nogil:
        """Resets the executor status, if needed deallocates all the memory."""
        cdef:
            _Task* task_it
            _Task* task_end
        if self.tasks:
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
        self.result_end = NULL
        self.max_threads = 1

    cdef Long next(self) nogil:
        """Returns next prime number.

        :return:
        - On success, the next prime number.
        - STOP_ITERATION: if there are no more prime numbers.
        - MEMORY_ERROR: on memory allocation failures.
        """
        cdef:
            Long result

        # If there are no results ready, tries to generate next bunch of
        # prime numbers:
        if not self.result_it:
            if not self.task_it \
                    or self.task_it == self.task_end:
                return STOP_ITERATION
            else:
                if self.task_it == self.tasks:
                    result = <Long>_task_execute_first(self.task_it)
                elif not self.task_it.begin:
                    result = <Long>_task_execute_group(self.task_it,
                                                       self.task_end,
                                                       self.tasks,
                                                       self.max_threads)
                if result < 0:
                    self.result_it = NULL
                    self.result_end = NULL
                    return result  # Failure.
                self.result_it = self.task_it.begin
                self.result_end = self.task_it.end
                self.task_it += 1

        # Emits one result:
        result = self.result_it[0]
        self.result_it += 1

        # No more results:
        if self.result_it == self.result_end:
            # Deallocate previous task if it is not the first:
            if self.task_it - 1 > self.tasks:
                _task_free(self.task_it - 1)
            self.result_it = NULL
            self.result_end = NULL

        return result  # Success

# ------------------------------------------------------------------------------

ctypedef struct _Task:
    # A task to be executed to partially calculate prime numbers.
    Long x_min         # First number to be tested.
    Long x_max         # Last number (exclusive) to be tested.
    Long* begin        # Beginning of the buffer of found results.
    Long* end          # End (exclusive) of the buffer of found results.
    char* cache        # An internal cache containing a boolean for each tested
                       # number (range [x_min, x_max)). The boolean is set to true
                       # when at least one dividend have been found.
    Long last_cleared  # Position of the last cleared element in the cache


cdef Result _task_execute_first(_Task *root_task) nogil:
    """
    To execute task[0] we need to insert the very first prime numbers
    manually, than the real execution can happen.

    The task's range [x_min, x_max) is supposed to start form zero.

    :param root_task: the task to be executed.

    :return:
    - SUCCESS on success.
    - MEMORY_ERROR if a memory allocation failure happened.
    """
    cdef:
        Result result
        Long x
        Long i

    # Allocates memory:
    result = _task_alloc(root_task)
    if result != SUCCESS:
        return MEMORY_ERROR

    # Manually inserts first primes:
    _task_push_back(root_task, 2)
    _task_push_back(root_task, 3)
    _task_push_back(root_task, 5)
    _task_push_back(root_task, 7)

    # Executes the task, it should have several steps that will find
    # prime numbers exponentially: 7 -> 49 -> 2401 ...
    _task_execute(root_task, root_task)
    return SUCCESS


cdef Result _task_execute_group(_Task *task_it,
                                _Task *task_end,
                                const _Task *root_task,
                                Long max_threads) nogil:
    """
    After the task[0] have been executed, we can use prime numbers from its
    execution to find out prime number for following tasks.

    It works up to task[0].x_max ** 2. Up to BLOCK_SIZE ** 2 that is in
    actual implementation 10 ** 12.

    The good think is that the following tasks can be performed in parallel
    because they have no inter dependencies.

    :param task_it: begin of the group of tasks to be executed in parallel.
    :param task_end: end of the group of tasks to be executed in parallel.
    :param root_task: the root task providing needed prime numbers.
    :param max_threads: maximum number of threads to be used at once.

    :return:
    - SUCCESS on success.
    - MEMORY_ERROR if a memory allocation failure happened.
    """
    cdef:
        Long num_threads
        Long num_failures  # Used to count memory allocation failures.
        Long i

    num_threads = min(max_threads,
                      <Long>(task_end - task_it))
    num_failures = 0
    with parallel(num_threads=num_threads):
        for i in prange(num_threads):
            if _task_alloc(task_it + i) == SUCCESS:
                _task_execute(task_it + i, root_task)
            else:
                num_failures += 1
    if num_failures:
        return MEMORY_ERROR
    return SUCCESS


@cython.cdivision(True)
cdef Result _task_alloc(_Task *self) nogil:
    """ Allocates memory necessary tu run the task.

    :param self: the task.
    :return:
    - SUCCESS on success
    - MEMORY_ERROR on allocation failure
    """
    cdef:
        Long block_size
        Long max_results
        Long num_bytes

    # Performs one single allocation for the two C arrays to be allocated:
    # - an array containing at most (x_max - x_min) / log10(x_max - x_min) results
    # - an array containing (x_max - x_min) boolean flags.

    block_size = self.x_max - self.x_min
    max_results = block_size // _log10(block_size)

    num_bytes = max_results * sizeof(Long)
    num_bytes += block_size * sizeof(char)
    self.begin = <Long *>calloc(1, <size_t>num_bytes)
    if not self.begin:
        return MEMORY_ERROR
    self.end = self.begin
    self.cache = <char *>(self.begin + max_results)
    self.last_cleared = 0

    return SUCCESS


cdef void _task_free(_Task *self) nogil:
    free(self.begin)
    self.begin = NULL
    self.end = NULL
    self.cache = NULL


cdef inline Bool _task_is_prime(const _Task *self, Long x) nogil:
    """Reads from task's cache if X can be a prime number.

    The task must have been executed before and the execution should
    have covered also X: x_min <= x < x_max.
    """
    if <Bool>(self.cache[x - self.x_min]):
        return FALSE
    else:
        return TRUE


@cython.cdivision(True)
cdef inline Result _task_clear_products(_Task *self,
                                        Long x) nogil:
    """Set cache cells of products of X to true where x is a prime number.

    This method works only if have already been called with all prime numbers
    that are smaller than X.
    """
    cdef:
        Long y

    # Finds the first product of x to be cleared:
    y = max(x * x,                              # First one from itself
            self.x_min + x - (self.x_min % x))  # First one in the target range
    if y >= self.x_max:
        return STOP_ITERATION  # No more primes to be tested by the caller.

    # This is the most performance critical loop of the algorithm, as you can see
    # there are no expensive operations here, just sums and vector assignments.
    while y < self.x_max:
        self.cache[y - self.x_min] = TRUE  # X is dividend of Y
        y += x
    return SUCCESS


cdef inline void _task_push_back(_Task *self, Long x) nogil:
    """Saves one prime number to the result's vector.

    Prime numbers are saved in a strictly ordered manner.

    :param x: one prime number.
    """
    self.end[0] = x
    self.end += 1


cdef void _task_execute(_Task *self, const _Task *source) nogil:
    """Executes one task."""
    cdef:
        Long x_max
        Long* src_it
        Long* src_end
        Long y
        Long x

    x_max = 0
    while x_max < self.x_max:  # if self == source we need more loops.
        x_max = self.x_max

        # A: uses prime numbers from source to mark their products as non primes:
        src_it = source.begin + self.last_cleared
        src_end = source.end
        if src_it < src_end:
            while src_it < src_end:
                y = src_it[0]
                if STOP_ITERATION == _task_clear_products(self, y):
                    break  # Out of bound reached.
                src_it += 1
            self.last_cleared = src_it - source.begin

            # On first execution we need more loops:
            if source == self:
                x_max = min(x_max, (y * y))

        # B: all elements [x_min, x_max) untouched by step A are prime numbers:
        x = self.x_min
        if self.begin < self.end:
            x = 2 + self.end[-1]  # Continues from previous iteration
        else:
            x += (1 - (x % 2))  # If X is even, moves x to the next odd number
        while x < x_max:
            if _task_is_prime(self, x):
                _task_push_back(self, x)
            x += 2  # Evaluates only odd numbers

# ------------------------------------------------------------------------------

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

def _raise_error(Result result):
    """Converts an error code to a Python exception."""
    if result == MEMORY_ERROR:
        raise MemoryError()
    elif result == STOP_ITERATION:
        raise StopIteration()
    elif result == VALUE_ERROR:
        raise ValueError()
