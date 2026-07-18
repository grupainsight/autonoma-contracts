from setuptools import setup, find_packages

setup(
    name="autonoma-contracts",
    version="1.0.0",
    packages=find_packages(),
    install_requires=[
        "pydantic>=2.0",
    ],
)
