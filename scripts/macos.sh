#!/bin/bash

# macOS script to select and run various convenience scripts
# It runs the selected python script in the appropriate directory

origin=$(pwd)
# Detect the modname using the name of the parent folder
cd ".."
modname=${PWD##*/}

cd "./scripts/code"
codedir=$(pwd)

echo "[1] New changelog entry"
echo "[2] Switch branch"
echo "[3] Build release"
echo -e "Select script to run: \c"
read choice

# This will error if choice is not a number
if [ $choice -eq 1 ]
then
    cd "../../modfiles/"
    script="${codedir}/new_changelog_entry.py"
elif [ $choice -eq 2 ]
then
    cd "../../../"
    script="${codedir}/switch_branch.py"
elif [ $choice -eq 3 ]
then
    cd "../../../"
    script="${codedir}/build_release.py"
else
    exit
fi

python3 $script $modname
cd $origin