# Test script for alprust.ps1

Write-Host "Starting alprust validation tests..." -ForegroundColor Cyan

# Test 1: Verify command injection block
Write-Host "Test 1: Verifying command injection blocking..." -NoNewline
$output = powershell -ExecutionPolicy Bypass -Command "../alprust.ps1 check --features '; rm -rf /'" 2>&1
if ($output -match "Invalid/dangerous characters detected") {
    Write-Host " PASSED" -ForegroundColor Green
} else {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "Output was: $output"
    exit 1
}

# Test 2: Verify clean check run
Write-Host "Test 2: Verifying clean check run..." -NoNewline
$output = powershell -ExecutionPolicy Bypass -Command "../alprust.ps1 check" 2>&1
if ($output -match "Syntax verification passed cleanly") {
    Write-Host " PASSED" -ForegroundColor Green
} else {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "Output was: $output"
    exit 1
}

Write-Host "All tests completed successfully!" -ForegroundColor Green
exit 0
