:: This file runs the python script in the appropriate directory
:: That allows the python script to be more generally applicable
ECHO OFF
cd ..\..
python .\factoryplanner\Scripts\code\build_release.py
PAUSE