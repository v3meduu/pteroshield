#!/bin/bash

sudo apt-get install figlet

# Check if figlet is installed
if ! command -v figlet &> /dev/null; then
    echo "Please install figlet to run this script."
    exit 1
fi

# The message to display
message="PteroShield » The script isn't ready yet"

# Generate ASCII art text using figlet and display it
figlet -f slant "$message"
