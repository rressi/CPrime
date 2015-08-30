from distutils.core import setup
from distutils.extension import Extension
from Cython.Distutils import build_ext
import platform

extra_compile_args = []
extra_link_args = []

if platform.system() == 'Linux':
    extra_compile_args.append('-fopenmp')
    extra_link_args.append('-fopenmp')
elif platform.system() == 'Windows':
    extra_compile_args.append('/openmp')
    extra_link_args.append('/openmp')

ext_modules = [Extension(name,
                         [name + '.pyx'],
                         extra_compile_args=extra_compile_args,
                         extra_link_args=extra_link_args)
               for name in ["CPrime", "CDividends"]]

setup(name='CPrime, fast prime numbers generator',
      cmdclass={'build_ext': build_ext},
      ext_modules=ext_modules,
      requires=['cython'])
