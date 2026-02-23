#!/bin/bash

# Navigate to your project directory
# Replace with the absolute path to your project
cd /Users/johnfranchak/Documents/GitHub/sip_dashboard

# Render the project
# This assumes 'quarto' is in your system PATH
/usr/local/bin/Rscript generate_timelines.qmd
/usr/local/bin/Rscript generate_summaries.qmd

# Add changes to Git
git add .

# Commit with a timestamped message
git commit -m "Generated timelines: $(date +'%Y-%m-%d %H:%M:%S')"

# Push to GitHub (assumes your 'origin' and 'main' branch are set up)
git push origin main
