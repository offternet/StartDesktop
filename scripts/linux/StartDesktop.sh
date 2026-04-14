#!/bin/bash

clear
# IMPORTANT: This script should NOT be run with sudo
# Instead, run as normal user and sudo will be called internally for installations

# Capture the real user's home directory (works even if script is accidentally run with sudo)
if [ -n "$SUDO_USER" ]; then
    # Script was run with sudo - get original user's home
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    # Script run normally
    REAL_USER="$USER"
    REAL_HOME="$HOME"
fi

# Initialize arrays
declare -a test_names
declare -a test_statuses
declare -a test_messages
declare -a test_commands

# Function to run all tests
run_all_tests() {
    # Reset arrays
    test_names=()
    test_statuses=()
    test_messages=()
    test_commands=()
    
    test_num=0
    total_tests=5
    
    # Function to run a test
    run_test() {
        local name="$1"
        local test_cmd="$2"
        local fail_msg="$3"
        local install_cmd="$4"
        
        ((test_num++))
        echo "--------------------------------------------------"
        echo "Running test $test_num of $total_tests: $name"
        
        if eval "$test_cmd" >/dev/null 2>&1; then
            echo "  Status: ✓ PASS"
            test_names+=("$name")
            test_statuses+=("PASS")
            test_messages+=("")
            test_commands+=("")
        else
            echo "  Status: ✗ FAIL"
            echo "  Reason: $fail_msg"
            test_names+=("$name")
            test_statuses+=("FAIL")
            test_messages+=("$fail_msg")
            test_commands+=("$install_cmd")
        fi
        echo ""
    }
    
    # Run all tests - using REAL_HOME consistently
    run_test "dialog package" \
        "command -v dialog" \
        "dialog is not installed (required for GUI menus)" \
        "sudo apt install -y dialog"
    
    run_test "socat package" \
        "command -v socat" \
        "socat is not installed" \
        "sudo apt install -y socat"
    
    run_test "gnome-terminal package" \
        "command -v gnome-terminal" \
        "gnome-terminal is not installed" \
        "sudo apt install -y gnome-terminal"
    
    run_test "libxapp-gtk3-module package" \
        "dpkg -l libxapp-gtk3-module 2>/dev/null | grep -q '^ii'" \
        "libxapp-gtk3-module is not installed" \
        "sudo apt install -y libxapp-gtk3-module"
    
    # Fixed file test with proper quoting
    run_test "StartDesktop-socat-server.sh file" \
        "[ -f \"$REAL_HOME/StartDesktop-socat-server.sh\" ]" \
        "File not found! Copy StartDesktop-socat-server.sh to $REAL_HOME" \
        "FILE_MISSING"
}

# Main script execution with loop
while true; do
    # Clear screen for better readability
    clear
    
    echo "========================================="
    echo "SYSTEM REQUIREMENT CHECK"
    echo "========================================="
    echo ""
    
    # Run all tests
    run_all_tests
    
    read -p "Press Enter key to continue test and see required actions"
    clear
    
    # Display summary
    echo "========================================="
    echo "FINAL TEST SUMMARY"
    echo "========================================="
    
    pass_count=0
    fail_count=0
    failed_tests=()
    failed_commands=()
    failed_messages=()
    package_tests=()
    package_commands=()
    file_missing=false
    
    for i in "${!test_names[@]}"; do
        if [ "${test_statuses[$i]}" = "PASS" ]; then
            echo "  ✓ PASS: ${test_names[$i]}"
            ((pass_count++))
        else
            echo "  ✗ FAIL: ${test_names[$i]}"
            echo "    → ${test_messages[$i]}"
            ((fail_count++))
            failed_tests+=("${test_names[$i]}")
            failed_commands+=("${test_commands[$i]}")
            failed_messages+=("${test_messages[$i]}")
            
            # Check if it's the missing file test
            if [[ "${test_names[$i]}" == *"file"* ]]; then
                file_missing=true
            fi
            
            # Track package tests separately (not the file)
            if [ -n "${test_commands[$i]}" ] && [ "${test_commands[$i]}" != "FILE_MISSING" ]; then
                package_tests+=("${test_names[$i]}")
                package_commands+=("${test_commands[$i]}")
            fi
        fi
    done
    
    echo "========================================="
    echo "TOTAL: $pass_count passed, $fail_count failed"
    echo "========================================="

    # Debug output to help troubleshoot file detection
    if [ "$file_missing" = true ]; then
        echo ""
        echo "🔍 DEBUG: File path being checked: $REAL_HOME/StartDesktop-socat-server.sh"
        echo ""
        echo "🔍 DEBUG: Current user: $(whoami)"
        echo ""
        echo "🔍 DEBUG: Home directory: $REAL_HOME"
        echo ""
        if [ -e "$REAL_HOME/StartDesktop-socat-server.sh" ]; then
            echo ""
            echo "🔍 DEBUG: File EXISTS at that location"
            echo ""
            ls -la "$REAL_HOME/StartDesktop-socat-server.sh"
        else
            echo "🔍 DEBUG: StartDesktop Server File DOES NOT EXIST at that location"
            echo ""
            echo "🔍 DEBUG: Checking if file exists with different casing:"
            echo ""
            ls -la "$REAL_HOME"/StartDesktop-socat-server* 2>/dev/null || echo "  No matching files found"
        fi
        echo ""
        read -p "Press Enter to continue to Summary of tests and actions..."
        clear
    fi
    
    # Check if all tests passed
    if [ $fail_count -eq 0 ]; then
        # All tests passed
        echo ""
        echo "✅ SUCCESS: All requirements are satisfied!"
        echo ""
    
        # Use dialog for the success message if available
        if command -v dialog >/dev/null 2>&1; then
            dialog --clear --title "Success" \
                --yesno "All requirements are satisfied!\n\nLaunch gnome-terminal now?" 10 50
            
            if [ $? -eq 0 ]; then
                clear
                echo "Launching StartDesktop socat server..."
                # Make sure the script is executable
                chmod +x "$REAL_HOME/StartDesktop-socat-server.sh" 2>/dev/null
                bash "$REAL_HOME/StartDesktop-socat-server.sh"
                exit 0
            else
                clear
                echo "Launch cancelled by user."
                exit 0
            fi
        else
            # Fallback to text mode
            read -p "▶ Press Enter key to launch StartDesktop server, or Ctrl+C to exit now"
            echo ""
            chmod +x "$REAL_HOME/StartDesktop-socat-server.sh" 2>/dev/null
            bash "$REAL_HOME/StartDesktop-socat-server.sh"
            exit 0
        fi
    else
        # Some tests failed
        echo ""
        echo "❌ ERROR: You have missing dependencies !!!."
        
        # Check if dialog is available
        if command -v dialog >/dev/null 2>&1; then
            # Build appropriate message based on what's missing
            if [ "$file_missing" = true ] && [ ${#package_tests[@]} -eq 0 ]; then
                # Only file is missing - show full path in message
                dialog --clear --title "Missing File" \
                    --msgbox "Missing file: $REAL_HOME/StartDesktop-socat-server.sh\n\n!!! Please copy StartDesktop to \n$REAL_HOME/\n\nPress OK after you have copied the file to re-run tests." 14 60
                
                # Clear dialog screen and wait for user
                clear
                echo "Please verify that StartDesktop-socat-server.sh is located at: $REAL_HOME/"
                echo ""
                read -p "Press Enter after you have copied the file to re-run tests..."
                continue
                
            elif [ ${#package_tests[@]} -gt 0 ]; then
                # Packages are missing (with or without file)
                package_list=""
                for i in "${!package_tests[@]}"; do
                    package_list="${package_list}\n• ${package_tests[$i]}"
                done
                
                missing_file_msg=""
                if [ "$file_missing" = true ]; then
                    missing_file_msg="\n📁 Missing File: $REAL_HOME/StartDesktop-socat-server.sh\n\n!!! Please copy StartDesktop Server to: $REAL_HOME/\n"
                fi
                
                # Ask user if they want to install missing packages
                dialog --clear --title "Missing Requirements" \
                    --yesno "Missing dependencies detected:$missing_file_msg\n\nThe following packages also need to be installed:$package_list\n\nConnect to the Internet and press a key to install missing packages.\n\nTo stop Installation and Exit Program Press ctrl+c" 20 60
                
                if [ $? -eq 0 ]; then
                    # User wants to install packages
                    # Extract package names
                    packages_to_install=""
                    for cmd in "${package_commands[@]}"; do
                        pkg_name=$(echo "$cmd" | awk '{print $NF}')
                        packages_to_install="$packages_to_install $pkg_name"
                    done
                    
                    # Close dialog to show installation in terminal
                    clear
                    
                    echo "========================================="
                    echo "INSTALLING REQUIRED PACKAGES"
                    echo "========================================="
                    echo ""
                    echo "Packages to install: $packages_to_install"
                    echo ""
                    
                    # Update package list
                    echo "Step 1: Updating package list..."
                    sudo apt update
                    
                    echo ""
                    echo "Step 2: Installing packages..."
                    sudo apt install -y $packages_to_install
                    
                    echo ""
                    echo "========================================="
                    echo "INSTALLATION COMPLETE"
                    echo "========================================="
                    
                    if [ "$file_missing" = true ]; then
                        echo ""
                        echo "📁 REMINDER: !!!! Please copy StartDesktop-socat-server.sh to: $REAL_HOME/"
                        echo ""
                    fi
                    
                    echo ""
                    echo "Press Enter to re-run tests and verify all requirements..."
                    read
                    
                    # Loop back to beginning to re-run tests
                    continue
                    
                else
                    # User chose not to install
                    dialog --clear --title "Setup Cancelled" \
                        --msgbox "Setup cancelled by user. Please install missing requirements manually and run the script again." 10 50
                    clear
                    echo "Setup cancelled by user. Exiting..."
                    exit 1
                fi
            fi
            
        else
            # dialog not available - text mode
            if [ "$file_missing" = true ]; then
                echo ""
                echo "📁 Missing file: $REAL_HOME/StartDesktop-socat-server.sh"
                echo ""
                echo "!!! Please copy StartDesktop Server file to: $REAL_HOME/"
                echo ""
            fi
            
            if [ ${#package_tests[@]} -gt 0 ]; then
                echo ""
                echo "The following packages also need to be installed:"
                for i in "${!package_tests[@]}"; do
                    echo "  - ${package_tests[$i]}"
                done
                echo ""
                read -p "Press Enter to install these packages, or Ctrl+C to exit"
                
                # Install packages
                packages_to_install=""
                for cmd in "${package_commands[@]}"; do
                    pkg_name=$(echo "$cmd" | awk '{print $NF}')
                    packages_to_install="$packages_to_install $pkg_name"
                done
                
                echo ""
                echo "Installing packages: $packages_to_install"
                sudo apt update
                sudo apt install -y $packages_to_install
                
                echo ""
                echo "Press Enter to re-run tests..."
                read
                continue
            elif [ "$file_missing" = true ]; then
                echo ""
                read -p "Press Enter after you have copied the file to re-run tests..."
                continue
            else
                echo ""
                echo "No action taken. Exiting..."
                exit 1
            fi
        fi
    fi
done
