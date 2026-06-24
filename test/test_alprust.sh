#!/usr/bin/env bash

# Test script for alprust (Bash script)

echo "Starting alprust validation tests..."

# Test 1: Verify command injection block
printf "Test 1: Verifying command injection blocking..."
output=$(bash ../alprust check --features '; rm -rf /' 2>&1)
if echo "$output" | grep -q "Invalid/dangerous characters detected"; then
    echo -e " \033[32mPASSED\033[0m"
else
    echo -e " \033[31mFAILED\033[0m"
    echo "Output was: $output"
    exit 1
fi

# Test 2: Verify clean check run
printf "Test 2: Verifying clean check run..."
output=$(bash ../alprust check 2>&1)
if echo "$output" | grep -q "Syntax verification passed cleanly"; then
    echo -e " \033[32mPASSED\033[0m"
else
    echo -e " \033[31mFAILED\033[0m"
    echo "Output was: $output"
    exit 1
fi

echo -e "\033[32mAll tests completed successfully!\033[0m"
exit 0
