# Windows script to select and run various convenience scripts
# It runs the selected python script in the appropriate directory

# Set the mod name here
$modname = "factoryplanner"

$origin = Get-Location
Set-Location -Path ".\code"
$codedir = Get-Location

Write-Host "[1] New changelog entry"
Write-Host "[2] Switch branch"
Write-Host "[3] Build release"
Write-Host "[4] Update Factorio"
$choice = Read-Host -Prompt "Select script to run"

if ($choice -eq 1) {
    Set-Location -Path "..\..\modfiles\"
    $script = $codedir.tostring() + "\new_changelog_entry.py"
} elseif ($choice -eq 2) {
    Set-Location -Path "..\..\..\"
    $script = $codedir.tostring() + "\switch_branch.py"
} elseif ($choice -eq 3) {
    Set-Location -Path "..\..\..\"
    $script = $codedir.tostring() + "\build_release.py"
} elseif ($choice -eq 4) {
    Set-Location -Path "..\..\..\"
    $script = $codedir.tostring() + "\update_factorio.py"
} else {
    Exit
}

python $script $modname
Set-Location -Path $origin

Read-Host -Prompt "Press any key to exit"