#!/bin/bash
# socat-url-server.sh - Terminal Pre-processor with full command chaining support
# Supports complex commands like: sudo_"sudo apt-get update && sudo apt-get upgrade"
# And GUI dialogs: bash_"yad --question --text='Is this awesome?'; sudo apt-get update; xdg-open 'https://deepseek.com'"

PORT=9000

# Function to run commands in a new terminal window (for bash_ prefixed commands)
runBash_cmd() {
    local cmd="$1"
    
    gnome-terminal --window --title="Bash: $cmd" -- bash -c "
        echo '========================================='
        echo 'Now executing: $cmd'
        echo '========================================='
        sleep 1
        echo ''
        echo 'Running command(s)...'
        echo ''
        eval \"$cmd\"
        echo ''
        echo '========================================='
        echo 'Command(s) completed. Press any key to close...'
        echo '========================================='
        read -n 1
        exit
    " &
    
    echo "[$(date +%H:%M:%S)] Bash command launched: $cmd"
}

# Function to run commands with sudo (password prompt via yad)
runSudo_cmd() {
    local cmd="$1"
    
    # Use yad for password prompt
    gnome-terminal --window --title="Sudo: $cmd" -- bash -c "
        echo '========================================='
        echo 'Now executing (with sudo): $cmd'
        echo '========================================='
        sleep 1
        echo ''
        
        # Get sudo password via yad dialog
        PASSWORD=\$(yad --title='Sudo Authentication' \\
            --form --field='Password':H \\
            --width=400 --height=150 --center \\
            --text='Enter sudo password for:' \\
            --text=\"<b>Command: $cmd</b>\" \\
            --separator='' --button='Cancel:1' --button='OK:0')
        
        if [ \$? -eq 0 ] && [ -n \"\$PASSWORD\" ]; then
            echo \"\$PASSWORD\" | sudo -S bash -c \"$cmd\"
            if [ \$? -eq 0 ]; then
                echo ''
                echo '✓ Command executed successfully'
            else
                echo ''
                echo '✗ Command failed'
            fi
        else
            echo 'Authentication cancelled or failed'
        fi
        
        echo ''
        echo '========================================='
        echo 'Press any key to close...'
        echo '========================================='
        read -n 1
        exit
    " &
    
    echo "[$(date +%H:%M:%S)] Sudo command launched: $cmd"
}
export -f runBash_cmd
export -f runSudo_cmd

# Function to run regular commands (no terminal, background)
runRegular_cmd() {
    local cmd="$1"
    
    # For regular commands, just execute in background
    eval "$cmd" > /dev/null 2>&1 &
    
    echo "[$(date +%H:%M:%S)] Regular command executed: $cmd"
}

# Function to sanitize command by removing trailing query parameters and whitespace
sanitize_command() {
    local raw="$1"
    local sanitized="$raw"
    
    # Remove everything after ? (query parameters)
    sanitized="${sanitized%%\?*}"
    
    # Remove everything after & (ampersand)
    sanitized="${sanitized%%&*}"
    
    # Remove trailing whitespace
    sanitized="$(echo "$sanitized" | sed 's/[[:space:]]*$//')"
    
    echo "$sanitized"
}

# Function to parse and execute command based on prefix
parse_and_execute() {
    local raw_cmd="$1"
    local cmd=""
    local prefix=""
    
    # First sanitize the raw command to remove query parameters
    local sanitized_cmd=$(sanitize_command "$raw_cmd")
    
    echo "[$(date +%H:%M:%S)] Raw command: $raw_cmd"
    echo "[$(date +%H:%M:%S)] Sanitized command: $sanitized_cmd"
    
    # Check for bash_ prefix with quoted command (bash_"command here")
    if [[ "$sanitized_cmd" =~ ^bash_\"(.+)\"$ ]]; then
        prefix="bash"
        cmd="${BASH_REMATCH[1]}"
        echo "[$(date +%H:%M:%S)] Detected bash_ prefix with quotes for: $cmd"
        runBash_cmd "$cmd"
        
    # Check for bash_ prefix without quotes (backward compatibility)
    elif [[ "$sanitized_cmd" =~ ^bash_ ]]; then
        prefix="bash"
        cmd="${sanitized_cmd#bash_}"
        echo "[$(date +%H:%M:%S)] Detected bash_ prefix for: $cmd"
        runBash_cmd "$cmd"
        
    # Check for sudo_ prefix with quoted command (sudo_"command here")
    elif [[ "$sanitized_cmd" =~ ^sudo_\"(.+)\"$ ]]; then
        prefix="sudo"
        cmd="${BASH_REMATCH[1]}"
        echo "[$(date +%H:%M:%S)] Detected sudo_ prefix with quotes for: $cmd"
        runSudo_cmd "$cmd"
        
    # Check for sudo_ prefix without quotes (backward compatibility)
    elif [[ "$sanitized_cmd" =~ ^sudo_ ]]; then
        prefix="sudo"
        cmd="${sanitized_cmd#sudo_}"
        echo "[$(date +%H:%M:%S)] Detected sudo_ prefix for: $cmd"
        runSudo_cmd "$cmd"
        
    # Regular command (no prefix)
    else
        cmd="$sanitized_cmd"
        echo "[$(date +%H:%M:%S)] Regular command: $cmd"
        runRegular_cmd "$cmd"
    fi
}

# Create the responder script
cat > /tmp/url-responder.sh << 'EOF'
#!/bin/bash
# Universal URL responder - Terminal Pre-processor

# Read the HTTP request first line
read request

# Log the request
echo "[$(date +%H:%M:%S)] Request: $request" >&2

# Extract the full path and query string
full_path=$(echo "$request" | sed -n 's|GET \([^ ]*\) HTTP.*|\1|p')

if [ -z "$full_path" ]; then
    full_path=$(echo "$request" | awk '{print $2}')
fi

echo "[$(date +%H:%M:%S)] Full path: $full_path" >&2

# Extract command from URL - handle quoted commands properly
cmd=""

# Pattern 1: /launch/COMMAND
if [[ "$full_path" =~ /launch/(.+)$ ]]; then
    cmd="${BASH_REMATCH[1]}"
fi

# Pattern 2: /linuxapps/COMMAND (legacy)
if [ -z "$cmd" ] && [[ "$full_path" =~ /linuxapps/(.+)$ ]]; then
    cmd="${BASH_REMATCH[1]}"
fi

# Pattern 3: /exec/COMMAND
if [ -z "$cmd" ] && [[ "$full_path" =~ /exec/(.+)$ ]]; then
    cmd="${BASH_REMATCH[1]}"
fi

# Pattern 4: Direct /COMMAND (for curl testing)
if [ -z "$cmd" ] && [[ "$full_path" =~ ^/([^?]+)$ ]]; then
    cmd="${BASH_REMATCH[1]}"
fi

# Pattern 5: From query string ?cmd=COMMAND
if [ -z "$cmd" ] && [[ "$full_path" =~ cmd=([^&]+) ]]; then
    cmd="${BASH_REMATCH[1]}"
fi

# URL decode the command (convert %22 to " etc.)
if [ -n "$cmd" ]; then
    # First, decode %22 to " (double quote)
    cmd=$(echo "$cmd" | sed 's/%22/"/g')
    # Decode %20 to space
    cmd=$(echo "$cmd" | sed 's/%20/ /g')
    # Decode %3B to ;
    cmd=$(echo "$cmd" | sed 's/%3B/;/g')
    # Decode %26 to &
    cmd=$(echo "$cmd" | sed 's/%26/\&/g')
    # Decode other URL encodings
    cmd=$(printf '%b' "${cmd//%/\\x}" 2>/dev/null || echo "$cmd")
fi

echo "[$(date +%H:%M:%S)] Extracted command: $cmd" >&2

# If command found, process it
if [ -n "$cmd" ]; then
    echo "Processing command: $cmd" >&2
    
    # Call the parse function (exported from parent)
    if declare -f parse_and_execute > /dev/null 2>&1; then
        parse_and_execute "$cmd"
    else
        # Fallback: direct execution if function not available
        echo "WARNING: parse_and_execute not available, using direct execution" >&2
        
        # Sanitize in fallback too
        sanitized_cmd=$(echo "$cmd" | sed 's/?.*$//' | sed 's/&.*$//')
        
        # Check for bash_ prefix with quotes
        if [[ "$sanitized_cmd" =~ ^bash_\"(.+)\"$ ]]; then
            cmd="${BASH_REMATCH[1]}"
            gnome-terminal --window --title="Bash: $cmd" -- bash -c "echo 'Executing: $cmd'; eval \"$cmd\"; read -n 1" &
        # Check for bash_ prefix without quotes
        elif [[ "$sanitized_cmd" =~ ^bash_ ]]; then
            cmd="${sanitized_cmd#bash_}"
            gnome-terminal --window --title="Bash: $cmd" -- bash -c "echo 'Executing: $cmd'; eval \"$cmd\"; read -n 1" &
        # Check for sudo_ prefix with quotes
        elif [[ "$sanitized_cmd" =~ ^sudo_\"(.+)\"$ ]]; then
            cmd="${BASH_REMATCH[1]}"
            PASSWORD=$(yad --title='Sudo' --form --field='Password':H --separator='' --button='OK:0')
            if [ -n "$PASSWORD" ]; then
                echo "$PASSWORD" | sudo -S bash -c "$cmd"
            fi
        # Check for sudo_ prefix without quotes
        elif [[ "$sanitized_cmd" =~ ^sudo_ ]]; then
            cmd="${sanitized_cmd#sudo_}"
            PASSWORD=$(yad --title='Sudo' --form --field='Password':H --separator='' --button='OK:0')
            if [ -n "$PASSWORD" ]; then
                echo "$PASSWORD" | sudo -S bash -c "$cmd"
            fi
        else
            # Regular command
            eval "$cmd" &
        fi
    fi
fi

# Send HTTP response with auto-close
echo "HTTP/1.0 200 OK"
echo "Content-Type: text/html"
echo "Connection: close"
echo ""
echo "<!DOCTYPE html>"
echo "<html>"
echo "<head><title>Executing Command</title></head>"
echo "<body onload='window.close()'>"
echo "<p>Command executing...</p>"
echo "</body>"
echo "</html>"
EOF

chmod +x /tmp/url-responder.sh

# Export functions for use in the responder script
export -f parse_and_execute
export -f runBash_cmd
export -f runSudo_cmd
export -f runRegular_cmd
export -f sanitize_command

# Get local IP
get_ip() {
    ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1
}

SERVER_IP=$(get_ip)
[ -z "$SERVER_IP" ] && SERVER_IP="127.0.0.1"

echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║     TERMINAL PRE-PROCESSOR - Ultimate Command Execution Server   ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""
echo "Server running on: Local: http://localhost:$PORT"
echo "  Network: http://$SERVER_IP:$PORT"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 COMPLEX COMMAND EXAMPLES:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Multiple apt commands with chaining:"
echo "   http://$SERVER_IP:$PORT/launch/sudo_\"sudo apt-get update && sudo apt-get upgrade -y\""
echo ""
echo "2. GUI dialog + system commands:"
echo "   http://$SERVER_IP:$PORT/launch/bash_\"yad --question --text='Proceed?'; sudo apt-get update; xdg-open 'https://deepseek.com'\""
echo ""
echo "3. Complex scripting with variables:"
echo "   http://$SERVER_IP:$PORT/launch/bash_\"for i in {1..5}; do echo \\\"Count: \$i\\\"; sleep 1; done\""
echo ""
echo "4. Multi-line commands with semicolons:"
echo "   http://$SERVER_IP:$PORT/launch/bash_\"cd /tmp; mkdir test; touch test/file.txt; ls -la test/\""
echo ""
echo "5. Conditional execution:"
echo "   http://$SERVER_IP:$PORT/launch/bash_\"which firefox && firefox || echo 'Firefox not installed'\""
echo ""
echo "6. Background processes:"
echo "   http://$SERVER_IP:$PORT/launch/bash_\"nautilus &; gnome-calculator &\""
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 SYNTAX RULES:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "• Use double quotes around the entire command: prefix_\"your command here\""
echo "• Multiple commands: separate with ; or && or ||"
echo "• Escape inner double quotes with backslash: \\\""
echo "• Query parameters (?_cb=xxx) are automatically stripped"
echo ""
echo "🔧 PREFIXES:"
echo "  bash_  - Opens terminal window, runs commands (no sudo)"
echo "  sudo_  - Prompts for password, runs with elevated privileges"
echo "  (none) - Runs silently in background"
echo ""
echo "✨ Features: yad dialogs, command chaining, variables, conditionals, loops"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

# Run socat with the responder
socat TCP-LISTEN:$PORT,reuseaddr,fork EXEC:/tmp/url-responder.sh
