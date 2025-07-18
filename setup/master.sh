#!/bin/bash

# Color codes
RC='\e[0m'
RED='\e[1;38;2;255;51;51m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'

# Github directory
githubDirectory="$(git rev-parse --show-toplevel 2>/dev/null)"

# Handle error messages and print them
log_error() {
    local log_file="error_log.txt"
    local timestamp=$(date +"%Y-%m-%d %T")  # Get current timestamp
    local log_message=$1  # First argument is treated as the error message
    
    # Create log file if it doesn't exist
    touch "$log_file"
    
    # Append error message with timestamp to the log file
    echo -e "[$timestamp] ERROR: $log_message" >> "$log_file"
    
    # Print error message to the terminal
    echo -e "${RED}Error: $log_message${RC}"
}

# Print message to the terminal
show_info() {
    local timestamp=$(date +"%Y-%m-%d %T")  # Get current timestamp
    echo -e "\n${YELLOW}[$timestamp] INFO: $1${RC}"
}

# Print success message to the terminal
success_message() {
    echo -e "${GREEN}$1 \xE2\x9C\x94${RC}"
}

# Function for updating repositories
update_repositories() {
    show_info "Performing full system upgrade on Arch..."
    if sudo pacman -Syu --noconfirm > /dev/null 2>&1; then
        success_message "System upgraded successfully"
        return 0
    else
        log_error "Failed to upgrade system"
        exit 1
    fi
}

install_programs() {
    show_info "Installing programs via pacman..."

    if [ -f program_list.txt ]; then
        while IFS= read -r program; do
            echo -e "\n\e[1;30;47mInstalling $program...${RC}"
            if sudo pacman -S --noconfirm --needed "$program" > /dev/null 2>&1; then
                success_message "$program installed"
            else
                log_error "Failed to install $program ✘"
                return 1
            fi
        done < program_list.txt
        success_message "Programs installation completed"
        return 0
    else
        log_error "Program list file not found. No programs installed 🚫"
        return 1
    fi
}

# Function to install terminal theme
configureTerminalTheme() {
    font_download_directory="/tmp/SETUP/"
    font_install_path="/usr/local/share/fonts/"
    
    # Add more fonts with their respective filenames and extraction directories here
    declare -A font_info=(
        ["Hack.zip"]="Hack"
        ["Meslo.zip"]="Meslo"
        ["FiraCode.zip"]="FiraCode"
    )

    show_info "Installing terminal theme..."

    for font_file in "${!font_info[@]}"; do
        font_name="${font_info[$font_file]}"
        font_download_path="${font_download_directory}${font_file}"
        font_extract_path="${font_download_directory}${font_name}"

        # Downloading latest release of the fonts from nerdfonts.com
        latest_release_url=$(curl -s "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" | jq -r ".assets[] | select(.name == \"$font_file\") | .browser_download_url")

        if [ -n "$latest_release_url" ]; then
            show_info "Downloading latest $font_name font release..."
            wget -q --show-progress=off -P "$font_download_directory" "$latest_release_url" || { log_error "Failed to download $font_name font"; return 1; }
            
            unzip -q "$font_download_path" -d "$font_extract_path" || { log_error "Failed to unzip $font_name font directory"; return 1; }
            
            sudo cp -r "$font_extract_path" "$font_install_path" || { log_error "Failed to copy $font_name font files"; return 1; }

            success_message "$font_name downloaded successfully."
        else
            log_error "Failed to fetch latest $font_name font release URL."
            return 1
        fi
    done

    # Update font cache and fetch/execute theme after all fonts are installed
    sudo fc-cache -f || { log_error "Failed to update font cache"; return 1; }
    
    show_info "Fetching and executing the theme from git..."
    bash -c "$(curl -sLo- https://git.io/JvvDs)" || { log_error "Failed to fetch the theme from git"; return 1; }
    
    success_message "Terminal theme installed successfully."
    return 0
}

# Function to download and configure yt-dlp
configureYtdlp() {
    show_info "Installing yt-dlp..."

    if [ ! -d "$HOME/.local/bin" ]; then
        mkdir -p "$HOME/.local/bin" || { log_error "Failed to create directory $HOME/.local/bin"; return 1; }
    fi

    if ! curl -sL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o "$HOME/.local/bin/yt-dlp"; then
        log_error "Failed to download yt-dlp binary"
        return 1
    else
        success_message "yt-dlp installed successfully."
        return 0
    fi
}

# Function to copy binaries to .local/bin
configureBinary() {
    show_info "Configuring binaries..."

    # Copying my binaries except channels.toml
    for file in "$githubDirectory/bin/"*; do
        [[ "$file" == *.toml ]] && continue
        cp "$file" "$HOME/.local/bin/" || { log_error "Failed to copy $file"; return 1; }
    done > /dev/null 2>&1

    # Ensure all files in ~/.local/bin are executable
    for file in "$HOME/.local/bin/"*; do
        [ -f "$file" ] && [ ! -x "$file" ] && chmod +x "$file"
    done

    success_message "Binaries copied to .local/bin."
    return 0
}

# Function to configure twitchtv
configureTwitch() {
    show_info "Configuring Twitch..."

    local twitchDir="$HOME/.config/twitchtv"

    #Copy channels.toml to twitchDir
    if [ ! -d "$twitchDir" ]; then
        mkdir -p "$twitchDir" || { log_error "Failed to create $twitchDir"; return 1; }
    fi

    cp "$githubDirectory/bin/"*.toml "$twitchDir" || { log_error "Failed to copy channels.toml to $twitchDir"; return 1; }

    success_message "Twitch config file setup succesfully."
    return 0
}

# Function to install Secure Boot signing script and pacman hook
configureSBScripts() {
    show_info "Setting up Secure Boot signing scripts..."

    if [ ! -d "/etc/initcpio/post" ]; then
        sudo mkdir -p /etc/initcpio/post || { log_error "Failed to create /etc/initcpio/post"; return 1; }
    fi

    if [ ! -d "/etc/pacman.d/hooks" ]; then
        sudo mkdir -p /etc/pacman.d/hooks || { log_error "Failed to create /etc/pacman.d/hooks"; return 1; }
    fi

    sudo cp "$githubDirectory/bash_configs/SB-sign-scripts/kernel-sbsign" /etc/initcpio/post/ || { log_error "Failed to copy kernel-sbsign to /etc/initcpio/post" ; return 1; }

    # Make kernel-sbsign executable if it's not already
    if [ ! -x /etc/initcpio/post/kernel-sbsign ]; then
        sudo chmod +x /etc/initcpio/post/kernel-sbsign || { log_error "Failed to set executable permissions for kernel-sbsign"; return 1; }
    fi

    sudo cp "$githubDirectory/bash_configs/SB-sign-scripts/80-secureboot.hook" /etc/pacman.d/hooks/ || { log_error "Failed to copy 80-secureboot.hook to /etc/pacman.d/hooks"; return 1; }

    success_message "Secure Boot scripts and hook installed successfully."
    return 0
}

# Function to replace .bashrc and install gitinfo binary
configureBash() {
    show_info "Configuring .bashrc and installing gitinfo..."

    # Backup existing .bashrc
    if [ -f "$HOME/.bashrc" ]; then
        cp "$HOME/.bashrc" "$HOME/.bashrc.backup" || { log_error "Failed to backup existing .bashrc"; return 1; }
        success_message "Existing .bashrc backed up as .bashrc.backup"
    fi

    # Copy and hide dot files from source to destination 
    copied_files=()
    for file in "$githubDirectory/bash_configs/"*; do
        filename=$(basename "$file")
        dest="$HOME/$filename"
        hidden_dest="$HOME/.$filename"

        if cp "$file" "$dest"; then
            if mv "$dest" "$hidden_dest"; then
                copied_files+=("$hidden_dest")
            else
                log_error "Failed to hide $filename"
                return 1
            fi
        else
            log_error "Failed to copy $filename"
            return 1
        fi
    done

    success_message "Bash setup successful. Copied and hid files: ${copied_files[*]}"
    return 0
}

# Function to copy the desktop files of firefox
setupDesktopFiles() {
    show_info "Installing desktop files of firefox..."

    if [ ! -d "$HOME/.local/share/applications" ]; then
        mkdir -p "$HOME/.local/share/applications" || { log_error "Failed to create applications directory."; return 1; }
    fi

    cp "$githubDirectory/firefox/"*.desktop "$HOME/.local/share/applications/" > /dev/null 2>&1 || { log_error "Desktop files could not be copied."; return 1; }
    sudo cp "$githubDirectory/firefox/"*.png /usr/share/icons/hicolor/256x256/apps/ > /dev/null 2>&1 || { log_error "Icons could not be copied."; return 1; }

    success_message "Desktop files and icons copied succesfully."
    return 0
}

# Function to configure mpv
configureMpv() {
    show_info "Configuring mpv..."

    local mpv_config_dir="$HOME/.config/mpv"
    local yt_dlp_path="$HOME/.local/bin/yt-dlp"

    if [ ! -d "$mpv_config_dir" ]; then
        mkdir -p "$mpv_config_dir" || { log_error "Failed to create directory $mpv_config_dir"; return 1; }
    fi

    # Copy all config files first
    cp "$githubDirectory/mpv/"* "$mpv_config_dir/" || { log_error "Failed to copy files to $mpv_config_dir"; return 1; }

    # Replace placeholder in the mpv.conf file with actual yt-dlp path
    sed -i "s|__YT_DLP_PATH__|$yt_dlp_path|g" "$mpv_config_dir/mpv.conf"

    success_message "MPV configured successfully"
    return 0
}

# Function to configure streamlink with virtualenvironment
configureStreamlink() {
    show_info "Configuring streamlink with python virtualenvironment..."

    # Create the virtual environment only if it doesn't already exist
    if [ ! -d "$HOME/myenv" ]; then
        if python -m venv "$HOME/myenv" > /dev/null 2>&1; then
            show_info "Virtual environment created at $HOME/myenv"
        else
            log_error "Failed to create Python virtual environment at $HOME/myenv."
            return 1
        fi
    fi

    show_info "Installing Streamlink..."
    source "$HOME/myenv/bin/activate"

    if pip install -U streamlink > /dev/null 2>&1; then
        deactivate
        success_message "Streamlink installed successfully."
        return 0
    else
        log_error "Failed to install streamlink"
        deactivate
        return 1
    fi
}

# Function to finalize the installation
finalConfigurations() {
    configureYtdlp
    configureBinary
    configureTwitch
    configureStreamlink
    configureBash
    configureTerminalTheme
    configureMpv
    configureSBScripts
    setupDesktopFiles

    success_message "\nEverything setup successfully. Enjoy Linux"
}

# Funtion to cleanup the configuration files
cleanUp() {
    local directory="/tmp/SETUP"
    show_info "Cleaning junk files..."

    if [ -d "$directory" ]; then
        rm -rf "$directory"
        success_message "Junk files removed succesfully"
    fi
}

# Function to create SETUP directory in /tmp if it doesn't exist
create_SETUP_directory() {
    if [ ! -d "/tmp/SETUP" ]; then
        mkdir -p "/tmp/SETUP"
    fi
}

# Main function

# Array of valid case names
valid_args=("full" "arch")
# Join the elements of the array with a pipe separator
valid_args_str=$(IFS=\|; echo "${valid_args[*]}")

check_argument() {
    create_SETUP_directory

    local arg="$1"

    case $arg in
        full)
            show_info "Running install function..."
            # User's commands for install function
            update_repositories
            install_programs
            finalConfigurations
            ;;
        test)
            show_info "Testing funtions..."
            ;;
        *)
            log_error "The argument you provided is invalid"
            log_error "Usage: bash script_name.sh [${valid_args_str}]"
            return 1
            ;;
    esac
}

# Check for arguments and invoke the necessary actions
if [ $# -eq 0 ]; then
    log_error "Please provide an argument."
    log_error "Usage: bash script_name.sh [${valid_args_str}]"
    exit 1
fi

check_argument "$1"
