#!/bin/bash

# Navigate to your project directory
# Replace with the absolute path to your project
cd /Users/johnfranchak/Documents/GitHub/sip_dashboard

# Render the project
# This assumes 'quarto' is in your system PATH
/usr/local/bin/quarto render timelines.qmd --cache-refresh
