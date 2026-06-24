#!/bin/sh

# Get the absolute path of the directory where this script lives
SCRIPT_DIR="$( cd "$( dirname "$0" )" >/dev/null 2>&1 && pwd )"

echo "Configuring alprust for macOS/Linux/Termux..."

# 1. Force executable permissions on the alprust shell script locally
chmod +x "$SCRIPT_DIR/alprust"

# 2. Detect Termux environment and get target binary directory
is_termux=false
if [ -n "$TERMUX_VERSION" ]; then
    is_termux=true
else
    case "$PREFIX" in
        *com.termux*) is_termux=true ;;
    esac
fi

if [ "$is_termux" = true ]; then
    TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
    INSTALL_DIR="$TERMUX_PREFIX/bin"
    echo "Termux environment detected. Creating symlink in $INSTALL_DIR..."
    
    # 3. Fix shebang in the alprust script to use Termux's bash path directly
    if [ -f "$SCRIPT_DIR/alprust" ]; then
        echo "Fixing shebang in alprust script for Termux compatibility..."
        sed -i "1s|^#!.*|#!$TERMUX_PREFIX/bin/bash|" "$SCRIPT_DIR/alprust"
    fi
    
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

printf "\n\033[32m[Success] Installation complete! You can now use the 'alprust' command anywhere.\033[0m\n"