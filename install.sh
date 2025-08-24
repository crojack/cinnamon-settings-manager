#!/bin/bash

# Cinnamon Settings Manager Installation Script
# This script installs the Cinnamon Settings Manager and all its modules
# Copyright (c) 2025 - MIT License

set -e  # Exit on any error

# Color codes for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="$HOME/.local/bin"
DATA_DIR="$HOME/.local/share/cinnamon-settings-manager"
DESKTOP_DIR="$HOME/.local/share/applications"

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}  Cinnamon Settings Manager Install  ${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo ""
}

# Check if running on compatible system
check_system() {
    print_info "Checking system compatibility..."

    if ! command -v gcc &> /dev/null; then
        print_error "gcc is required but not installed. Please install build-essential package."
        echo "  Ubuntu/Debian: sudo apt install build-essential"
        echo "  Fedora: sudo dnf install gcc"
        echo "  Arch: sudo pacman -S base-devel"
        exit 1
    fi

    if ! command -v pkg-config &> /dev/null; then
        print_error "pkg-config is required but not installed."
        echo "  Ubuntu/Debian: sudo apt install pkg-config"
        echo "  Fedora: sudo dnf install pkgconf-devel"
        echo "  Arch: sudo pacman -S pkgconf"
        exit 1
    fi

    # Check for required libraries
    if ! pkg-config --exists xcursor; then
        print_error "libXcursor development files are required but not found."
        echo "  Ubuntu/Debian: sudo apt install libxcursor-dev"
        echo "  Fedora: sudo dnf install libXcursor-devel"
        echo "  Arch: sudo pacman -S libxcursor"
        exit 1
    fi

    if ! pkg-config --exists libpng; then
        print_error "libpng development files are required but not found."
        echo "  Ubuntu/Debian: sudo apt install libpng-dev"
        echo "  Fedora: sudo dnf install libpng-devel"
        echo "  Arch: sudo pacman -S libpng"
        exit 1
    fi

    # Check for Perl modules (will warn if missing)
    perl -e "use Gtk3;" 2>/dev/null || {
        print_warning "Gtk3 Perl module not found. Install with:"
        echo "  Ubuntu/Debian: sudo apt install libgtk3-perl"
        echo "  Fedora: sudo dnf install perl-Gtk3"
        echo "  Arch: sudo pacman -S perl-gtk3"
        echo "  CPAN: cpan Gtk3"
    }

    perl -e "use JSON;" 2>/dev/null || {
        print_warning "JSON Perl module not found. Install with:"
        echo "  Ubuntu/Debian: sudo apt install libjson-perl"
        echo "  Fedora: sudo dnf install perl-JSON"
        echo "  Arch: sudo pacman -S perl-json"
        echo "  CPAN: cpan JSON"
    }

    perl -e "use Moo;" 2>/dev/null || {
        print_warning "Moo Perl module not found. Install with:"
        echo "  Ubuntu/Debian: sudo apt install libmoo-perl"
        echo "  Fedora: sudo dnf install perl-Moo"
        echo "  Arch: Available in AUR: perl-moo"
        echo "  CPAN: cpan Moo"
    }

    print_success "System compatibility check completed"
}

# Compile xcursor_extractor
compile_xcursor_extractor() {
    print_info "Compiling xcursor_extractor..."

    if [ ! -f "xcursor_extractor.c" ]; then
        print_error "xcursor_extractor.c not found in current directory"
        exit 1
    fi

    # Get compiler flags from pkg-config
    CFLAGS=$(pkg-config --cflags xcursor libpng)
    LIBS=$(pkg-config --libs xcursor libpng)

    print_info "Using CFLAGS: $CFLAGS"
    print_info "Using LIBS: $LIBS"

    # Compile with optimization and warnings
    gcc -O2 -Wall -Wextra $CFLAGS -o xcursor_extractor xcursor_extractor.c $LIBS

    if [ $? -eq 0 ]; then
        print_success "xcursor_extractor compiled successfully"
    else
        print_error "Failed to compile xcursor_extractor"
        exit 1
    fi
}

# Create directory structure
create_directories() {
    print_info "Creating directory structure..."

    # Create main directories
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$DATA_DIR"
    mkdir -p "$DESKTOP_DIR"

    # Create data subdirectories
    mkdir -p "$DATA_DIR/config"
    mkdir -p "$DATA_DIR/icons"
    mkdir -p "$DATA_DIR/previews"
    mkdir -p "$DATA_DIR/thumbnails"

    # Create module-specific data directories
    mkdir -p "$DATA_DIR/cinnamon-theme-manager"
    mkdir -p "$DATA_DIR/cinnamon-theme-manager/config"
    mkdir -p "$DATA_DIR/cinnamon-theme-manager/previews"

    mkdir -p "$DATA_DIR/cinnamon-application-themes-manager"
    mkdir -p "$DATA_DIR/cinnamon-application-themes-manager/config"
    mkdir -p "$DATA_DIR/cinnamon-application-themes-manager/previews"

    mkdir -p "$DATA_DIR/cinnamon-icon-themes-manager"
    mkdir -p "$DATA_DIR/cinnamon-icon-themes-manager/config"
    mkdir -p "$DATA_DIR/cinnamon-icon-themes-manager/previews"

    mkdir -p "$DATA_DIR/cinnamon-cursor-themes-manager"
    mkdir -p "$DATA_DIR/cinnamon-cursor-themes-manager/config"
    mkdir -p "$DATA_DIR/cinnamon-cursor-themes-manager/thumbnails"

    mkdir -p "$DATA_DIR/cinnamon-backgrounds-manager"
    mkdir -p "$DATA_DIR/cinnamon-backgrounds-manager/config"
    mkdir -p "$DATA_DIR/cinnamon-backgrounds-manager/thumbnails"

    mkdir -p "$DATA_DIR/cinnamon-font-manager"
    mkdir -p "$DATA_DIR/cinnamon-font-manager/config"

    print_success "Directory structure created"
}

# Install files
install_files() {
    print_info "Installing application files..."

    # Install the compiled xcursor_extractor
    if [ -f "xcursor_extractor" ]; then
        cp xcursor_extractor "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/xcursor_extractor"
        print_success "xcursor_extractor installed to $INSTALL_DIR/"
    else
        print_error "xcursor_extractor binary not found"
        exit 1
    fi

    # Install main application
    if [ -f "cinnamon-settings-manager.pl" ]; then
        cp cinnamon-settings-manager.pl "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/cinnamon-settings-manager.pl"
        print_success "Main settings manager installed"
    fi

    # Install individual modules
    local modules=(
        "cinnamon-themes-manager.pl"
        "cinnamon-application-themes-manager.pl"
        "cinnamon-icon-themes-manager.pl"
        "cinnamon-cursor-themes-manager.pl"
        "cinnamon-backgrounds-manager.pl"
        "cinnamon-font-manager.pl"
    )

    for module in "${modules[@]}"; do
        if [ -f "$module" ]; then
            cp "$module" "$INSTALL_DIR/"
            chmod +x "$INSTALL_DIR/$module"
            print_success "Installed $module"
        else
            print_warning "$module not found, skipping..."
        fi
    done

    # Make sure PATH includes ~/.local/bin
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        print_info "Adding ~/.local/bin to PATH in ~/.bashrc"
        echo "" >> "$HOME/.bashrc"
        echo "# Added by Cinnamon Settings Manager installer" >> "$HOME/.bashrc"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        print_warning "Please run 'source ~/.bashrc' or restart your terminal to update PATH"
    fi
}

# Desktop entry configuration
setup_desktop_entries() {
    # Define all desktop entries with their properties
    declare -A desktop_entries=(
        ["cinnamon-settings-manager"]="Cinnamon Settings Manager|Modern settings manager for Cinnamon desktop|cinnamon-settings-manager|settings;preferences;configuration;"
        ["cinnamon-themes-manager"]="Cinnamon Theme Manager|Manage Cinnamon desktop themes|cs-themes|theme;cinnamon;desktop;appearance;"
        ["cinnamon-application-themes-manager"]="Application Theme Manager|Manage GTK application themes|cs-themes|theme;gtk;application;appearance;"
        ["cinnamon-icon-themes-manager"]="Icon Theme Manager|Manage desktop icon themes|cs-icons|icons;theme;desktop;appearance;"
        ["cinnamon-cursor-themes-manager"]="Cursor Theme Manager|Manage mouse cursor themes|cs-mouse|cursor;mouse;pointer;theme;"
        ["cinnamon-backgrounds-manager"]="Background Manager|Manage desktop wallpapers and backgrounds|cs-backgrounds|wallpaper;background;desktop;"
        ["cinnamon-font-manager"]="Font Manager|Manage system fonts|cs-fonts|font;typography;text;"
    )

    # Export for use in create_desktop_entries function
    for key in "${!desktop_entries[@]}"; do
        export "DESKTOP_${key^^//-/_}"="${desktop_entries[$key]}"
    done
}

# Install application icon if provided
install_application_icon() {
    local icon_file="cinnamon-settings-manager.svg"
    local icon_dir="$HOME/.local/share/icons/hicolor/scalable/apps"

    if [ -f "$icon_file" ]; then
        print_info "Installing custom SVG application icon..."
        mkdir -p "$icon_dir"
        cp "$icon_file" "$icon_dir/"

        # Also check for PNG versions at different sizes (legacy support)
        for size in 16 22 24 32 48 64 128 256; do
            local size_icon="cinnamon-settings-manager-${size}.png"
            local size_dir="$HOME/.local/share/icons/hicolor/${size}x${size}/apps"
            if [ -f "$size_icon" ]; then
                mkdir -p "$size_dir"
                cp "$size_icon" "$size_dir/cinnamon-settings-manager.png"
                print_info "Installed ${size}x${size} PNG icon"
            fi
        done

        # Update icon cache if available
        if command -v gtk-update-icon-cache &> /dev/null; then
            gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
            print_success "Icon cache updated"
        fi

        print_success "Custom SVG application icon installed"
    else
        # Fallback to PNG if SVG not found
        local png_icon="cinnamon-settings-manager.png"
        local png_icon_dir="$HOME/.local/share/icons/hicolor/64x64/apps"

        if [ -f "$png_icon" ]; then
            print_info "Installing custom PNG application icon..."
            mkdir -p "$png_icon_dir"
            cp "$png_icon" "$png_icon_dir/"

            # Update icon cache
            if command -v gtk-update-icon-cache &> /dev/null; then
                gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
            fi

            print_success "Custom PNG application icon installed"
        else
            print_info "No custom icon found (looking for $icon_file or $png_icon), using system icon"
        fi
    fi
}

# Create desktop entries
create_desktop_entries() {
    print_info "Creating desktop entries..."

    # Setup desktop entry configurations
    setup_desktop_entries

    # Install custom application icon
    install_application_icon

    # Create desktop entries for all applications
    local IFS='|'

    # Main Settings Manager (uses custom icon if available)
    local main_icon="cinnamon-settings-manager"
    if [ ! -f "$HOME/.local/share/icons/hicolor/scalable/apps/cinnamon-settings-manager.svg" ] && \
       [ ! -f "$HOME/.local/share/icons/hicolor/64x64/apps/cinnamon-settings-manager.png" ]; then
        main_icon="preferences-system"
    fi
    create_desktop_entry "cinnamon-settings-manager" \
        "Cinnamon Settings Manager" \
        "Modern settings manager for Cinnamon desktop" \
        "$main_icon" \
        "settings;preferences;configuration;"

    # Cinnamon Theme Manager
    create_desktop_entry "cinnamon-themes-manager" \
        "Cinnamon Theme Manager" \
        "Manage Cinnamon desktop themes" \
        "cs-themes" \
        "theme;cinnamon;desktop;appearance;"

    # Application Theme Manager
    create_desktop_entry "cinnamon-application-themes-manager" \
        "Application Theme Manager" \
        "Manage GTK application themes" \
        "cs-themes" \
        "theme;gtk;application;appearance;"

    # Icon Theme Manager
    create_desktop_entry "cinnamon-icon-themes-manager" \
        "Icon Theme Manager" \
        "Manage desktop icon themes" \
        "cs-icons" \
        "icons;theme;desktop;appearance;"

    # Cursor Theme Manager
    create_desktop_entry "cinnamon-cursor-themes-manager" \
        "Cursor Theme Manager" \
        "Manage mouse cursor themes" \
        "cs-mouse" \
        "cursor;mouse;pointer;theme;"

    # Background Manager
    create_desktop_entry "cinnamon-backgrounds-manager" \
        "Background Manager" \
        "Manage desktop wallpapers and backgrounds" \
        "cs-backgrounds" \
        "wallpaper;background;desktop;"

    # Font Manager
    create_desktop_entry "cinnamon-font-manager" \
        "Font Manager" \
        "Manage system fonts" \
        "cs-fonts" \
        "font;typography;text;"

    # Update desktop database
    if command -v update-desktop-database &> /dev/null; then
        update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
        print_success "Desktop entries created and database updated"
    else
        print_success "Desktop entries created"
        print_info "Desktop database will be updated on next login"
    fi
}

# Verify installation
verify_installation() {
    print_info "Verifying installation..."

    local success=true

    # Check xcursor_extractor
    if [ -x "$INSTALL_DIR/xcursor_extractor" ]; then
        print_success "xcursor_extractor installed correctly"
    else
        print_error "xcursor_extractor installation failed"
        success=false
    fi

    # Check main application
    if [ -x "$INSTALL_DIR/cinnamon-settings-manager.pl" ]; then
        print_success "Main application installed correctly"
    else
        print_error "Main application installation failed"
        success=false
    fi

    # Check directory structure
    if [ -d "$DATA_DIR" ]; then
        print_success "Data directory structure created"
    else
        print_error "Data directory structure missing"
        success=false
    fi

    if [ "$success" = true ]; then
        print_success "Installation verification completed successfully"
        return 0
    else
        print_error "Installation verification failed"
        return 1
    fi
}

# Print final instructions
print_final_instructions() {
    echo ""
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}  Installation Complete!${NC}"
    echo -e "${GREEN}================================${NC}"
    echo ""
    echo -e "Applications installed to: ${BLUE}$INSTALL_DIR${NC}"
    echo -e "Data directory: ${BLUE}$DATA_DIR${NC}"
    echo -e "Desktop entries: ${BLUE}$DESKTOP_DIR${NC}"
    echo ""
    echo "Available applications:"
    echo "• cinnamon-settings-manager.pl - Main settings manager"
    echo "• cinnamon-themes-manager.pl - Cinnamon theme manager"
    echo "• cinnamon-application-themes-manager.pl - GTK theme manager"
    echo "• cinnamon-icon-themes-manager.pl - Icon theme manager"
    echo "• cinnamon-cursor-themes-manager.pl - Cursor theme manager"
    echo "• cinnamon-backgrounds-manager.pl - Background manager"
    echo "• cinnamon-font-manager.pl - Font manager"
    echo ""
    echo "Usage:"
    echo "• Run from command line: cinnamon-settings-manager.pl"
    echo "• Or find in your application menu under 'Settings'"
    echo ""
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo -e "${YELLOW}Important:${NC} Run 'source ~/.bashrc' or restart your terminal to update PATH"
    fi
    echo ""
}

# Main installation process
main() {
    print_header

    # Run installation steps
    check_system
    compile_xcursor_extractor
    create_directories
    install_files
    create_desktop_entries

    if verify_installation; then
        print_final_instructions
        exit 0
    else
        print_error "Installation failed during verification"
        exit 1
    fi
}

# Run main function
main "$@"
