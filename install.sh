#!/usr/bin/env bash

# Get the absolute path of the directory where this script lives
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

echo "Configuring alprust for macOS/Linux..."

# 1. Force executable permissions on the alprust shell script locally
chmod +x "$SCRIPT_DIR/alprust"

# 2. Detect target binary directory (support Termux, default to /usr/local/bin)
if [ -n "$TERMUX_VERSION" ] || [[ "$PREFIX" == *com.termux* ]]; then
    INSTALL_DIR="${PREFIX:-/data/data/com.termux/files/usr}/bin"
    echo "Termux environment detected. Creating symlink in $INSTALL_DIR..."
    
    if [ -d "$INSTALL_DIR" ] && [ -w "$INSTALL_DIR" ]; then
        ln -sf "$SCRIPT_DIR/alprust" "$INSTALL_DIR/alprust"
    else
        echo "Error: Termux binary directory $INSTALL_DIR is not writable or does not exist."
        exit 1
    fi
else
    INSTALL_DIR="/usr/local/bin"
    echo "Creating global symlink in $INSTALL_DIR..."
    
    if [ -w "$INSTALL_DIR" ]; then
        ln -sf "$SCRIPT_DIR/alprust" "$INSTALL_DIR/alprust"
    else
        echo "Administrative privileges required to link to $INSTALL_DIR. Prompting for sudo..."
        sudo ln -sf "$SCRIPT_DIR/alprust" "$INSTALL_DIR/alprust"
    fi
fi

echo -e "\033[32m\n[Success] Installation complete! You can now use the 'alprust' command anywhere.\033[0m"