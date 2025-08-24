# Installation Guide

This guide provides detailed installation instructions for the Cinnamon Settings Manager suite.

## System Requirements

### Operating System
- **Linux Mint** with Cinnamon desktop environment (recommended)
- **Ubuntu** with Cinnamon session
- **Other Linux distributions** with Cinnamon desktop

### Build Dependencies

**Essential build tools:**
```bash
# Ubuntu/Debian/Linux Mint
sudo apt install build-essential pkg-config

# Fedora/CentOS/RHEL
sudo dnf install gcc pkgconf-devel

# Arch Linux/Manjaro
sudo pacman -S base-devel pkgconf
```

**Required libraries for xcursor_extractor:**
```bash
# Ubuntu/Debian/Linux Mint
sudo apt install libxcursor-dev libpng-dev

# Fedora/CentOS/RHEL
sudo dnf install libXcursor-devel libpng-devel

# Arch Linux/Manjaro
sudo pacman -S libxcursor libpng
```

### Runtime Dependencies

**Perl modules:**
```bash
# Ubuntu/Debian/Linux Mint
sudo apt install libgtk3-perl libjson-perl libmoo-perl

# Fedora/CentOS/RHEL
sudo dnf install perl-Gtk3 perl-JSON perl-Moo

# Arch Linux/Manjaro
sudo pacman -S perl-gtk3 perl-json
# Note: perl-moo is available in AUR

# Via CPAN (universal method)
cpan Gtk3 JSON Moo
```

## Installation Methods

### Method 1: Automated Installation (Recommended)

This is the easiest and most reliable method:

```bash
# 1. Clone the repository
git clone https://github.com/crojack/cinnamon-settings-manager.git
cd cinnamon-settings-manager

# 2. Run the automated installer
chmod +x install.sh
./install.sh
```

The automated installer will:
- ✅ Check all system dependencies
- ✅ Compile xcursor_extractor with proper flags
- ✅ Create all required directory structures
- ✅ Install all files with correct permissions
- ✅ Create desktop menu entries
- ✅ Install custom application icons
- ✅ Update system databases
- ✅ Configure PATH if needed

### Method 2: Using Makefile

If you prefer using make:

```bash
# 1. Clone the repository
git clone https://github.com/crojack/cinnamon-settings-manager.git
cd cinnamon-settings-manager

# 2. Check dependencies (optional)
make check-deps
make check-runtime

# 3. Install everything
make install
```

**Available make targets:**
- `make` or `make build` - Compile xcursor_extractor only
- `make check-deps` - Verify build dependencies
- `make check-runtime` - Check Perl module dependencies
- `make install` - Full installation
- `make uninstall` - Remove all installed files
- `make clean` - Remove build artifacts
- `make test` - Run basic tests

### Method 3: Manual Installation

For users who want full control over the installation process:

#### Step 1: Compile xcursor_extractor

```bash
# Get compiler flags from pkg-config
CFLAGS=$(pkg-config --cflags xcursor libpng)
LIBS=$(pkg-config --libs xcursor libpng)

# Compile with optimization
gcc -O2 -Wall -Wextra $CFLAGS -o xcursor_extractor xcursor_extractor.c $LIBS
```

#### Step 2: Create Directory Structure

```bash
# Main directories
mkdir -p ~/.local/bin
mkdir -p ~/.local/share/applications

# Main application data directory
mkdir -p ~/.local/share/cinnamon-settings-manager/{config,icons,previews,thumbnails}

# Module-specific directories
mkdir -p ~/.local/share/cinnamon-settings-manager/cinnamon-theme-manager/{config,previews}
mkdir -p ~/.local/share/cinnamon-settings-manager/cinnamon-application-themes-manager/{config,previews}
mkdir -p ~/.local/share/cinnamon-settings-manager/cinnamon-icon-themes-manager/{config,previews}
mkdir -p ~/.local/share/cinnamon-settings-manager/cinnamon-cursor-themes-manager/{config,thumbnails}
mkdir -p ~/.local/share/cinnamon-settings-manager/cinnamon-backgrounds-manager/{config,thumbnails}
mkdir -p ~/.local/share/cinnamon-settings-manager/cinnamon-font-manager/config
```

#### Step 3: Install Files

```bash
# Install binary
cp xcursor_extractor ~/.local/bin/
chmod +x ~/.local/bin/xcursor_extractor

# Install Perl scripts
cp *.pl ~/.local/bin/
chmod +x ~/.local/bin/*.pl
```

#### Step 4: Install Custom Icon (Optional)

If you have a custom icon for the main application:

**For SVG icons (recommended):**
```bash
# Install SVG icon (scalable, preferred format)
mkdir -p ~/.local/share/icons/hicolor/scalable/apps
cp cinnamon-settings-manager.svg ~/.local/share/icons/hicolor/scalable/apps/
```

**For PNG icons:**
```bash
# Install main PNG icon
mkdir -p ~/.local/share/icons/hicolor/64x64/apps
cp cinnamon-settings-manager.png ~/.local/share/icons/hicolor/64x64/apps/

# Install additional sizes (if available)
for size in 16 22 24 32 48 64 128 256; do
    if [ -f "cinnamon-settings-manager-${size}.png" ]; then
        mkdir -p ~/.local/share/icons/hicolor/${size}x${size}/apps
        cp cinnamon-settings-manager-${size}.png ~/.local/share/icons/hicolor/${size}x${size}/apps/cinnamon-settings-manager.png
    fi
done
```

**Update icon cache:**
```bash
# Update icon cache for immediate recognition
gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor
```

**Icon file priority:**
1. `cinnamon-settings-manager.svg` (preferred - scalable)
2. `cinnamon-settings-manager.png` (fallback - 64x64)
3. System `preferences-system` icon (default fallback)

#### Step 5: Create Desktop Entries

Create desktop files in `~/.local/share/applications/`:

**Main Settings Manager:**
```bash
cat > ~/.local/share/applications/cinnamon-settings-manager.desktop << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Cinnamon Settings Manager
Comment=Modern settings manager for Cinnamon desktop
Exec=$HOME/.local/bin/cinnamon-settings-manager.pl
Icon=cinnamon-settings-manager
Terminal=false
StartupNotify=true
Categories=Settings;DesktopSettings;GTK;
Keywords=settings;preferences;configuration;
EOF
```

**Other Modules:** (repeat for each .pl file)
```bash
# Example for Theme Manager
cat > ~/.local/share/applications/cinnamon-themes-manager.desktop << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Cinnamon Theme Manager
Comment=Manage Cinnamon desktop themes
Exec=$HOME/.local/bin/cinnamon-themes-manager.pl
Icon=cs-themes
Terminal=false
StartupNotify=true
Categories=Settings;DesktopSettings;GTK;
Keywords=theme;cinnamon;desktop;appearance;
EOF
```

#### Step 6: Update System Databases

```bash
# Update desktop database
update-desktop-database ~/.local/share/applications

# Update icon cache (if custom icon was installed)
gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor
```

#### Step 7: Configure PATH

Add `~/.local/bin` to your PATH if not already present:

```bash
# Check if already in PATH
echo $PATH | grep -q "$HOME/.local/bin" || {
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    echo "Added ~/.local/bin to PATH. Run: source ~/.bashrc"
}
```

## Post-Installation

### Verify Installation

Check that everything is installed correctly:

```bash
# Check if binary works
xcursor_extractor
# Should show usage information

# Check if scripts are executable
ls -la ~/.local/bin/*.pl
# All should have execute permissions

# Test a script (replace with actual script name)
cinnamon-settings-manager.pl --version 2>/dev/null || echo "Script can be executed"
```

### Launch Applications

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

**From Desktop Menu:**
Look for the applications in your system menu under **Settings** or **Preferences**.

## Troubleshooting

### Common Issues

**"Command not found" errors:**
```bash
# Ensure PATH includes ~/.local/bin
source ~/.bashrc
# Or add manually:
export PATH="$HOME/.local/bin:$PATH"
```

**xcursor_extractor compilation fails:**
```bash
# Check if development libraries are installed
pkg-config --libs xcursor libpng
# Should output library flags, not error
```

**Perl module errors:**
```bash
# Test individual modules
perl -e "use Gtk3; print 'GTK3 OK\n';"
perl -e "use JSON; print 'JSON OK\n';"
perl -e "use Moo; print 'Moo OK\n';"
```

**Applications don't appear in menu:**
```bash
# Update desktop database
update-desktop-database ~/.local/share/applications/
# Then log out and back in
```

**Permission denied errors:**
```bash
# Fix permissions
chmod +x ~/.local/bin/xcursor_extractor
chmod +x ~/.local/bin/*.pl
```

### Getting Help

1. **Check the main README.md** for general information
2. **Search existing issues** on GitHub
3. **Create a new issue** with:
   - Your Linux distribution and version
   - Error messages (full output)
   - Steps you tried
   - Output of `perl --version` and `gcc --version`

## Uninstalling

To completely remove the installation:

**Using the installer:**
```bash
# The install script doesn't include uninstall, use make or manual method
```

**Using Makefile:**
```bash
make uninstall
```

**Manual removal:**
```bash
# Remove installed files
rm -f ~/.local/bin/xcursor_extractor
rm -f ~/.local/bin/*cinnamon-*-manager.pl
rm -f ~/.local/share/applications/*cinnamon-*-manager.desktop

# Remove data directories
rm -rf ~/.local/share/cinnamon-settings-manager

# Remove custom icons (if installed)
rm -f ~/.local/share/icons/hicolor/*/apps/cinnamon-settings-manager.png

# Update databases
update-desktop-database ~/.local/share/applications/
gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor
```

**Note:** PATH modifications in `~/.bashrc` are not automatically removed.

---

**For additional help, see the main [README.md](README.md) file.**
