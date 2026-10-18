import os
import sys

# Tests import the package from python/ without an install
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "python"))
