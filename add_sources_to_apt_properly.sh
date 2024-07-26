#!/bin/bash

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

# Define repositories
declare -A repos=(
    [1]="CISOfy|https://packages.cisofy.com/keys/cisofy-software-public.key|deb [arch=amd64] https://packages.cisofy.com/community/lynis/deb/ stable main|lynis"
    [2]="Chrome|https://dl.google.com/linux/linux_signing_key.pub|deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main|google-chrome-stable"
    [3]="VSCode|https://packages.microsoft.com/keys/microsoft.asc|deb [arch=amd64,arm64,armhf] https://packages.microsoft.com/repos/code stable main|code"
    [4]="NordVPN|https://repo.nordvpn.com/gpg/nordvpn_public.asc|deb https://repo.nordvpn.com/deb/nordvpn/debian stable main|nordvpn"
    [5]="CrowdSec|https://packagecloud.io/crowdsec/crowdsec/gpgkey|deb https://packagecloud.io/crowdsec/crowdsec/debian/ bullseye main|crowdsec"
)

# Function to remove duplicate entries from sources.list.d
remove_duplicate_sources() {
    echo "Checking for and removing duplicate source entries..."
    
    # Temporary file
    temp_file=$(mktemp)

    # Process all files in sources.list.d
    cat /etc/apt/sources.list.d/*.list 2>/dev/null | grep -E '^deb|^# deb' | sort | uniq > "$temp_file"

    # Rewrite sources.list.d files
    for file in /etc/apt/sources.list.d/*.list; do
        > "$file"
    done

    while IFS= read -r line; do
        repo_name=$(echo "$line" | awk '{print $3}' | cut -d'/' -f3)
        echo "$line" > "/etc/apt/sources.list.d/${repo_name}.list"
    done < "$temp_file"

    # Clean up temporary file
    rm "$temp_file"
    
    echo "Duplicate entries removed and sources organized."
}

# Function to check if a repository is properly included
check_repo() {
    local name=$1
    local keyring_file="/etc/apt/keyrings/${name,,}.gpg"
    local sources_file="/etc/apt/sources.list.d/${name,,}.list"
    
    if [ -f "$keyring_file" ] && [ -f "$sources_file" ]; then
        return 0  # Repository is properly included
    else
        return 1  # Repository is not properly included
    fi
}

# Function to add a repository
add_repository() {
    local name=$1
    local keyring_url=$2
    local sources_list=$3

    if check_repo "$name"; then
        echo "Repository $name is already properly included. Skipping."
    else
        echo "Adding/fixing $name repository..."
        mkdir -p /etc/apt/keyrings
        wget -O- $keyring_url | gpg --dearmor -o "/etc/apt/keyrings/${name,,}.gpg"
        echo "deb [signed-by=/etc/apt/keyrings/${name,,}.gpg] $sources_list" > "/etc/apt/sources.list.d/${name,,}.list"
        echo "$name repository added/fixed successfully."
    fi
}

# Function to process user input
process_input() {
    local input=$1
    local max=$2
    local result=()
    if [[ $input == "a" ]]; then
        result=($(seq 1 $max))
    else
        IFS=',' read -ra choices <<< "$input"
        for choice in "${choices[@]}"; do
            if [[ $choice == *-* ]]; then
                IFS='-' read -r start end <<< "$choice"
                for ((i=start; i<=end; i++)); do
                    if ((i >= 1 && i <= max)); then
                        result+=("$i")
                    fi
                done
            elif ((choice >= 1 && choice <= max)); then
                result+=("$choice")
            fi
        done
    fi
    echo "${result[@]}"
}

# Display repository list
echo "Available repositories:"
for i in $(seq 1 ${#repos[@]}); do
    IFS='|' read -r name _ _ _ <<< "${repos[$i]}"
    echo "$i) $name"
done

# Get user input for repositories
echo "Enter repository numbers to add (comma-separated, dash for range, or 'a' for all):"
read -r repo_choice

# Process user input for repositories
selected_repos=($(process_input "$repo_choice" "${#repos[@]}"))

# Add selected repositories
for repo in "${selected_repos[@]}"; do
    IFS='|' read -r name keyring_url sources_list package <<< "${repos[$repo]}"
    add_repository "$name" "$keyring_url" "$sources_list"
done

# Remove duplicate sources
remove_duplicate_sources

# Update apt
apt update

# Display package list for selected repositories only
echo "Main packages for selected repositories:"
for i in "${selected_repos[@]}"; do
    IFS='|' read -r name _ _ package <<< "${repos[$i]}"
    echo "$i) $package"
done

# Get user input for package installation
echo "Enter package numbers to install (comma-separated, dash for range, or 'a' for all selected repositories):"
read -r install_choice

# Process user input for packages, limited to selected repositories
packages_to_install=($(process_input "$install_choice" "${#selected_repos[@]}"))

# Install selected packages
if [ ${#packages_to_install[@]} -gt 0 ]; then
    for pkg in "${packages_to_install[@]}"; do
        IFS='|' read -r _ _ _ package <<< "${repos[${selected_repos[$((pkg-1))]}]}"
        apt install -y "$package"
    done
fi

echo "Script completed."
