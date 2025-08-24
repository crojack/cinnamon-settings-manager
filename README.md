# Cinnamon Settings Manager

A modern, comprehensive settings management suite for Linux Mint Cinnamon desktop environment, written in Perl with GTK3.

![Cinnamon Settings Manager](https://img.shields.io/badge/Platform-Linux%20Mint%20Cinnamon-green)
![Language](https://img.shields.io/badge/Language-Perl-blue)
![GUI](https://img.shields.io/badge/GUI-GTK3-orange)
![License](https://img.shields.io/badge/License-MIT-yellow)

## Overview

Cinnamon Settings Manager is a collection of specialized configuration tools that provide an interface for managing various aspects of your Cinnamon desktop environment. It has a little bit different module organisation than the original Linux Mint Cinnamon system settings.  

## Features

- **Cinnamon Theme Manager** - Preview and apply Cinnamon desktop themes 
- **Application Theme Manager** - Preview and apply GTK themes for applications
- **Icon Theme Manager** - Browse and switch between icon themes with comprehensive previews
- **Cursor Theme Manager** - Advanced cursor theme management with extracted cursor previews
- **Background Manager** - Wallpaper management with thumbnail previews
- **Font Manager** - System font management with live preview capabilities

### **Main Settings Manager**
- Unified interface for all main appearance system settings
- Search functionality
- Organized category-based navigation
- Integration with system configuration tools

## Screenshots

*Screenshots will be added in future releases*

## Installation

### Quick Install

The easiest way to install Cinnamon Settings Manager is using the automated installation script:

```bash
# Clone the repository
git clone https://github.com/yourusername/cinnamon-settings-manager.git
cd cinnamon-settings-manager

# Make the install script executable
chmod +x install.sh

# Run the installation
./install.sh
```

The installation script automatically:
- **Compiles** the xcursor_extractor utility
- **Creates** all necessary directory structures
- **Installs** all applications and the binary to ~/.local/bin
- **Creates** desktop entries for menu integration
- **Installs** custom application icon if provided
- **Updates** icon and desktop databases
- **Configures** PATH if needed

### Custom Application Icon

I have created a svg application icon but if you don't like it and if you have created a custom icon for the main Cinnamon Settings Manager application:

1. **Place your SVG icon file** as `cinnamon-settings-manager.svg` in the project root directory (recommended)
2. **Alternative PNG format**: Use `cinnamon-settings-manager.png` for a 64x64 pixel icon
3. **For multiple PNG sizes** (optional legacy support), use the naming convention:
   - `cinnamon-settings-manager-16.png` (16x16)
   - `cinnamon-settings-manager-22.png` (22x22)
   - `cinnamon-settings-manager-24.png` (24x24)
   - `cinnamon-settings-manager-32.png` (32x32)
   - `cinnamon-settings-manager-48.png` (48x48)
   - `cinnamon-settings-manager-64.png` (64x64)
   - `cinnamon-settings-manager-128.png` (128x128)
   - `cinnamon-settings-manager-256.png` (256x256)

The installation script will automatically detect and install these icons to the appropriate system directories:
- **SVG icons** → `~/.local/share/icons/hicolor/scalable/apps/`
- **PNG icons** → `~/.local/share/icons/hicolor/[size]x[size]/apps/`

**SVG format is preferred** because it provides perfect scaling at any size and smaller file size. If no custom icon is found, the system falls back to the standard `preferences-system` icon.

**Individual module icons** use the same icons as Cinnamon's built-in settings modules:
- **Theme Manager**: `cs-themes`
- **Application Themes**: `cs-themes`
- **Icon Themes**: `cs-icons`
- **Cursor Themes**: `cs-mouse`
- **Backgrounds**: `cs-backgrounds`
- **Fonts**: `cs-fonts`

### Manual Installation

If you prefer to install manually, follow these steps:

#### Prerequisites

**System Requirements:**
- Linux Mint with Cinnamon desktop environment
- GCC compiler
- pkg-config
- libXcursor development files
- libpng development files

**Install system dependencies:**

```bash
# Ubuntu/Debian/Linux Mint
sudo apt install build-essential pkg-config libxcursor-dev libpng-dev

# Fedora
sudo dnf install gcc pkgconf-devel libXcursor-devel libpng-devel

# Arch Linux
sudo pacman -S base-devel pkgconf libxcursor libpng
```

**Install Perl modules:**

```bash
# Ubuntu/Debian/Linux Mint
sudo apt install libgtk3-perl libjson-perl libmoo-perl cpanminus

# Fedora
sudo dnf install perl-Gtk3 perl-JSON perl-Moo

# Arch Linux
sudo pacman -S perl-gtk3 perl-json
# For Moo: install from AUR or CPAN

# Via CPANM (universal)
sudo cpanm Gtk3 JSON Moo
```

#### Manual Compilation and Installation

1. **Compile the xcursor_extractor:**

```bash
# Compile with proper flags
gcc -O2 -Wall -Wextra $(pkg-config --cflags xcursor libpng) \
    -o xcursor_extractor xcursor_extractor.c \
    $(pkg-config --libs xcursor libpng)
```

2. **Create directory structure:**

```bash
# Create installation directories
mkdir -p ~/.local/bin
mkdir -p ~/.local/share/cinnamon-settings-manager/{config,icons,previews,thumbnails}
mkdir -p ~/.local/share/applications

# Create module-specific directories
mkdir -p ~/.local/share/cinnamon-settings-manager/cinnamon-theme-manager/config
mkdir -p ~/.local/share/cinnamon-settings-manager/cinnamon-application-themes-manager/config
mkdir -p ~/.local/share/cinnamon-settings-manager/cinnamon-icon-themes-manager/config
mkdir -p ~/.local/share/cinnamon-settings-manager/cinnamon-cursor-themes-manager/config
mkdir -p ~/.local/share/cinnamon-settings-manager/cinnamon-backgrounds-manager/config
mkdir -p ~/.local/share/cinnamon-settings-manager/cinnamon-font-manager/config
```

3. **Install files:**

```bash
# Install binary and scripts
cp xcursor_extractor ~/.local/bin/
cp *.pl ~/.local/bin/
chmod +x ~/.local/bin/*.pl ~/.local/bin/xcursor_extractor
```

4. **Update PATH (if needed):**

```bash
# Add to ~/.bashrc if not already present
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

## Usage

### Running the Applications

After installation, you can run the applications in several ways:

**From Command Line:**
```bash
# Main settings manager
cinnamon-settings-manager.pl

# Individual managers
cinnamon-themes-manager.pl
cinnamon-application-themes-manager.pl
cinnamon-icon-themes-manager.pl
cinnamon-cursor-themes-manager.pl
cinnamon-backgrounds-manager.pl
cinnamon-font-manager.pl
```

**From Application Menu:**
Look for the applications in your system's application menu under the "Settings" category.

### Application Features

#### Main Settings Manager
- **Unified Interface**: Access all Cinnamon settings from one place
- **Advanced Search**: Quickly find specific settings
- **Category Organization**: Logical grouping of related settings
- **Custom Module Integration**: Launches specialized theme managers

#### Theme Managers
- **Live Previews**: See themes before applying them
- **Multiple Sources**: Scan system and user theme directories
- **Theme Information**: View theme details and metadata
- **Zoom Control**: Adjustable preview sizes

#### Cursor Theme Manager
- **Advanced Preview**: Extract and display actual cursor shapes
- **Multiple Cursors**: Preview different cursor types (arrow, hand, text, etc.)
- **Cache Management**: Efficient thumbnail caching system
- **Zoom Control**: Adjustable preview sizes

#### Background Manager
- **Thumbnail Grid**: Visual browsing of wallpapers
- **Multiple Formats**: Support for various image formats
- **Custom Directories**: Add your own wallpaper folders
- **Zoom Control**: Adjustable preview sizes

#### Font Manager
- **Live Preview**: See fonts rendered with sample text
- **System Integration**: Works with system font configuration
- **Custom Sample Text**: Use your own preview text
- **Font Information**: Display font family and style details
- **Zoom Control**: Adjustable preview sizes

## Configuration

Each application maintains its configuration in `~/.local/share/cinnamon-settings-manager/`. Configuration files are automatically created and managed by the applications.

### Common Configuration Options

- **Preview Sizes**: Adjustable thumbnail and preview sizes
- **Custom Directories**: Add additional search paths
- **Cache Settings**: Control caching behavior
- **Interface Preferences**: UI customization options

## Technical Details

### Architecture

The suite is built using:
- **Language**: Perl 5 with modern object-oriented features (Moo)
- **GUI Toolkit**: GTK3 via Perl bindings
- **Configuration**: JSON-based configuration files
- **Caching**: MD5-based cache system for performance
- **Binary Component**: C-based xcursor_extractor for cursor preview

### xcursor_extractor

The `xcursor_extractor` is a custom C utility that:
- Reads X11 cursor files using libXcursor
- Extracts individual cursor frames
- Converts to PNG format using libpng
- Handles pre-multiplied alpha transparency
- Provides metadata about cursor animations

### File Structure

```
~/.local/bin/
├── xcursor_extractor                    # Binary cursor extractor
├── cinnamon-settings-manager.pl         # Main settings application
├── cinnamon-themes-manager.pl           # Cinnamon theme manager
├── cinnamon-application-themes-manager.pl # GTK theme manager
├── cinnamon-icon-themes-manager.pl      # Icon theme manager
├── cinnamon-cursor-themes-manager.pl    # Cursor theme manager
├── cinnamon-backgrounds-manager.pl      # Background manager
└── cinnamon-font-manager.pl             # Font manager

~/.local/share/cinnamon-settings-manager/
├── config/                              # Global configuration
├── icons/                               # Custom icons
├── previews/                            # Generated previews
├── thumbnails/                          # Thumbnail cache
└── [module-name]/                       # Module-specific data
    ├── config/                          # Module configuration
    ├── previews/                        # Module previews
    └── thumbnails/                      # Module thumbnails
```

## Development

### Requirements for Development

- Perl 5.14 or later
- GTK3 development libraries
- libXcursor and libpng development libraries
- GCC compiler
- cpanminus for fetching Perl modules

### Building from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/cinnamon-settings-manager.git
cd cinnamon-settings-manager

# Install dependencies (see Installation section)

# Compile xcursor_extractor
make xcursor_extractor

# Run without installing
./cinnamon-settings-manager.pl
```

### Contributing

Contributions are welcome! Please feel free to submit pull requests, report bugs, or suggest features.

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Troubleshooting

### Common Issues

**xcursor_extractor compilation fails:**
- Ensure libXcursor-dev and libpng-dev are installed
- Check that pkg-config can find the libraries: `pkg-config --libs xcursor libpng`

**Perl module missing:**
- Install missing modules using your distribution's package manager
- Alternatively, use CPAN: `cpanm Module::Name`

**Applications don't appear in menu:**
- Run `update-desktop-database ~/.local/share/applications`
- Log out and back in

**Permission errors:**
- Ensure ~/.local/bin is in your PATH
- Check file permissions: `chmod +x ~/.local/bin/*.pl`

### Debug Mode

Run applications with debug output:
```bash
# Enable verbose output
PERL_DEBUG=1 cinnamon-settings-manager.pl
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Linux Mint team for the Cinnamon desktop environment
- GTK team for the excellent toolkit
- X.Org foundation for the Xcursor library
- libpng developers for PNG support

## Changelog

### Version 1.0.0 (Initial Release)
- Complete Cinnamon Settings Manager suite
- All theme managers (Cinnamon, GTK, Icons, Cursors)
- Background and Font managers
- Custom xcursor_extractor utility
- Automated installation script
- Desktop integration

## Support

For support, please:
1. Check the troubleshooting section
2. Search existing issues on GitHub
3. Create a new issue with detailed information about your problem

---

**Made for the Linux Mint Cinnamon community**
