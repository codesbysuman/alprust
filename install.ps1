# Get the absolute path of the directory where this install script is running
$installDir = $PSScriptRoot

# Fetch the current user's PATH environment variable
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")

# Check if the folder is already in the path to prevent duplicates
if ($userPath -notlike "*$installDir*") {
    # Append the directory and save it back to the Windows Registry
    $newPath = $userPath + ";" + $installDir
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    
    Write-Host "`n[Success] alprust has been added to your Windows PATH!" -ForegroundColor Green
    Write-Host "Please close and restart your terminal/IDE to start using the 'alprust' command." -ForegroundColor Yellow
} else {
    Write-Host "`n[Info] alprust is already installed and configured in your PATH." -ForegroundColor Cyan
}