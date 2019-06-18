:: This file runs the python script in the appropriate directory
:: That allows the python script to be more generally applicable
ECHO OFF
cd ..\..
python .\factoryplanner\Scripts\code\checkout_branch.py factoryplanner
PAUSE