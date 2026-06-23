#!/bin/bash

# Get the absolute path of the directory where this script lives
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

echo "Configuring alprust for macOS/Linux..."

# 1. Force executable permissions on the alprust shell script locally
chmod +x "$SCRIPT_DIR/alprust"

echo "Creating global symlink in /usr/local/bin..."

# 2. Safely create a symlink. If the directory requires admin rights, use sudo automatically
if [ -w /usr/local/bin ]; then
    ln -sf "$SCRIPT_DIR/alprust" /usr/local/bin/alprust
else
    echo "Administrative privileges required to link to /usr/local/bin. Prompting for sudo..."
    sudo ln -sf "$SCRIPT_DIR/alprust" /usr/local/bin/alprust
fi

echo -e "\033[32m\n[Success] Installation complete! You can now use the 'alprust' command anywhere.\033[0m"