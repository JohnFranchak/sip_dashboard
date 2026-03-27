#!/bin/bash

# Define the exact path to your mounted SMB share
MOUNT_POINT="/Volumes/padlab"

# Check if the mount point appears in the active mounts list
# We include "smbfs" to ensure it's an SMB mount, and add a trailing space 
# after $MOUNT_POINT to prevent partial matches (e.g., matching "ShareName2")
if ! mount | grep "smbfs" | grep -1 "on $MOUNT_POINT "; then
    echo "Error: SMB share is not mounted at $MOUNT_POINT."
    exit 1 # Exits the script with an error code
fi

echo "SMB share is mounted! Continuing with the script..."

# --- Your script logic goes here ---

# Navigate to your project directory
# Replace with the absolute path to your project
cd /Users/johnfranchak/Documents/GitHub/sip_dashboard

# Render the project
# This assumes 'quarto' is in your system PATH
/usr/local/bin/Rscript generate_timelines.r
/usr/local/bin/Rscript generate_summaries.r

# Add changes to Git
git add .

# Commit with a timestamped message
git commit -m "Generated timelines: $(date +'%Y-%m-%d %H:%M:%S')"

# Push to GitHub (assumes your 'origin' and 'main' branch are set up)
git push origin main
