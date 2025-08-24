# Cinnamon Settings Manager Makefile
# Simple build system for the project

# Compiler and flags
CC = gcc
CFLAGS = -O2 -Wall -Wextra $(shell pkg-config --cflags xcursor libpng)
LIBS = $(shell pkg-config --libs xcursor libpng)

# Installation directories
PREFIX = $(HOME)/.local
BINDIR = $(PREFIX)/bin
DATADIR = $(PREFIX)/share/cinnamon-settings-manager
DESKTOPDIR = $(PREFIX)/share/applications

# Source files
C_SOURCE = xcursor_extractor.c
BINARY = xcursor_extractor
PERL_SCRIPTS = cinnamon-settings-manager.pl \
               cinnamon-themes-manager.pl \
               cinnamon-application-themes-manager.pl \
               cinnamon-icon-themes-manager.pl \
               cinnamon-cursor-themes-manager.pl \
               cinnamon-backgrounds-manager.pl \
               cinnamon-font-manager.pl

.PHONY: all build install uninstall clean check-deps help

# Default target
all: build

# Build the xcursor_extractor
build: $(BINARY)

$(BINARY): $(C_SOURCE)
	@echo "Building xcursor_extractor..."
	$(CC) $(CFLAGS) -o $(BINARY) $(C_SOURCE) $(LIBS)
	@echo "Build complete: $(BINARY)"

# Check system dependencies
check-deps:
	@echo "Checking build dependencies..."
	@command -v gcc >/dev/null 2>&1 || { echo "Error: gcc not found. Install build-essential package."; exit 1; }
	@command -v pkg-config >/dev/null 2>&1 || { echo "Error: pkg-config not found."; exit 1; }
	@pkg-config --exists xcursor || { echo "Error: libXcursor development files not found."; exit 1; }
	@pkg-config --exists libpng || { echo "Error: libpng development files not found."; exit 1; }
	@echo "All build dependencies satisfied."

# Check runtime dependencies
check-runtime:
	@echo "Checking runtime dependencies..."
	@perl -e "use Gtk3;" 2>/dev/null || echo "Warning: Gtk3 Perl module not found."
	@perl -e "use JSON;" 2>/dev/null || echo "Warning: JSON Perl module not found."
	@perl -e "use Moo;" 2>/dev/null || echo "Warning: Moo Perl module not found."
	@echo "Runtime dependency check complete."

# Install everything
install: build install-dirs install-binary install-scripts install-desktop
	@echo ""
	@echo "Installation complete!"
	@echo "Applications installed to: $(BINDIR)"
	@echo "Data directory: $(DATADIR)"
	@echo ""
	@echo "Run 'source ~/.bashrc' or restart terminal if PATH was updated."

# Create installation directories
install-dirs:
	@echo "Creating directory structure..."
	@mkdir -p $(BINDIR)
	@mkdir -p $(DATADIR)/{config,icons,previews,thumbnails}
	@mkdir -p $(DESKTOPDIR)
	@mkdir -p $(DATADIR)/cinnamon-theme-manager/{config,previews}
	@mkdir -p $(DATADIR)/cinnamon-application-themes-manager/{config,previews}
	@mkdir -p $(DATADIR)/cinnamon-icon-themes-manager/{config,previews}
	@mkdir -p $(DATADIR)/cinnamon-cursor-themes-manager/{config,thumbnails}
	@mkdir -p $(DATADIR)/cinnamon-backgrounds-manager/{config,thumbnails}
	@mkdir -p $(DATADIR)/cinnamon-font-manager/config

# Install the compiled binary
install-binary: $(BINARY)
	@echo "Installing xcursor_extractor..."
	@cp $(BINARY) $(BINDIR)/
	@chmod +x $(BINDIR)/$(BINARY)

# Install Perl scripts
install-scripts:
	@echo "Installing Perl scripts..."
	@for script in $(PERL_SCRIPTS); do \
		if [ -f "$script" ]; then \
			cp "$script" $(BINDIR)/; \
			chmod +x $(BINDIR)/$script; \
			echo "  Installed $script"; \
		else \
			echo "  Warning: $script not found, skipping"; \
		fi \
	done

# Install desktop entries using the same system as install.sh
install-desktop:
	@echo "Creating desktop entries..."
	@# Install custom icon if available
	@if [ -f "cinnamon-settings-manager.png" ]; then \
		echo "Installing custom application icon..."; \
		mkdir -p $(HOME)/.local/share/icons/hicolor/64x64/apps; \
		cp cinnamon-settings-manager.png $(HOME)/.local/share/icons/hicolor/64x64/apps/; \
		for size in 16 22 24 32 48 64 128 256; do \
			if [ -f "cinnamon-settings-manager-$size.png" ]; then \
				mkdir -p $(HOME)/.local/share/icons/hicolor/${size}x${size}/apps; \
				cp cinnamon-settings-manager-$size.png $(HOME)/.local/share/icons/hicolor/${size}x${size}/apps/cinnamon-settings-manager.png; \
			fi \
		done; \
		command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f -t $(HOME)/.local/share/icons/hicolor 2>/dev/null || true; \
	fi
	@# Determine which icon to use for main app
	@MAIN_ICON="preferences-system"; \
	if [ -f "$(HOME)/.local/share/icons/hicolor/64x64/apps/cinnamon-settings-manager.png" ]; then \
		MAIN_ICON="cinnamon-settings-manager"; \
	fi; \
	echo "[Desktop Entry]" > $(DESKTOPDIR)/cinnamon-settings-manager.desktop; \
	echo "Version=1.0" >> $(DESKTOPDIR)/cinnamon-settings-manager.desktop; \
	echo "Type=Application" >> $(DESKTOPDIR)/cinnamon-settings-manager.desktop; \
	echo "Name=Cinnamon Settings Manager" >> $(DESKTOPDIR)/cinnamon-settings-manager.desktop; \
	echo "Comment=Modern settings manager for Cinnamon desktop" >> $(DESKTOPDIR)/cinnamon-settings-manager.desktop; \
	echo "Exec=$(BINDIR)/cinnamon-settings-manager.pl" >> $(DESKTOPDIR)/cinnamon-settings-manager.desktop; \
	echo "Icon=$MAIN_ICON" >> $(DESKTOPDIR)/cinnamon-settings-manager.desktop; \
	echo "Terminal=false" >> $(DESKTOPDIR)/cinnamon-settings-manager.desktop; \
	echo "StartupNotify=true" >> $(DESKTOPDIR)/cinnamon-settings-manager.desktop; \
	echo "Categories=Settings;DesktopSettings;GTK;" >> $(DESKTOPDIR)/cinnamon-settings-manager.desktop; \
	echo "Keywords=settings;preferences;configuration;" >> $(DESKTOPDIR)/cinnamon-settings-manager.desktop
	@echo "  Created cinnamon-settings-manager.desktop"
	@# Cinnamon Theme Manager
	@echo "[Desktop Entry]" > $(DESKTOPDIR)/cinnamon-themes-manager.desktop
	@echo "Version=1.0" >> $(DESKTOPDIR)/cinnamon-themes-manager.desktop
	@echo "Type=Application" >> $(DESKTOPDIR)/cinnamon-themes-manager.desktop
	@echo "Name=Cinnamon Theme Manager" >> $(DESKTOPDIR)/cinnamon-themes-manager.desktop
	@echo "Comment=Manage Cinnamon desktop themes" >> $(DESKTOPDIR)/cinnamon-themes-manager.desktop
	@echo "Exec=$(BINDIR)/cinnamon-themes-manager.pl" >> $(DESKTOPDIR)/cinnamon-themes-manager.desktop
	@echo "Icon=cs-themes" >> $(DESKTOPDIR)/cinnamon-themes-manager.desktop
	@echo "Terminal=false" >> $(DESKTOPDIR)/cinnamon-themes-manager.desktop
	@echo "StartupNotify=true" >> $(DESKTOPDIR)/cinnamon-themes-manager.desktop
	@echo "Categories=Settings;DesktopSettings;GTK;" >> $(DESKTOPDIR)/cinnamon-themes-manager.desktop
	@echo "Keywords=theme;cinnamon;desktop;appearance;" >> $(DESKTOPDIR)/cinnamon-themes-manager.desktop
	@echo "  Created cinnamon-themes-manager.desktop"
	@# Application Theme Manager
	@echo "[Desktop Entry]" > $(DESKTOPDIR)/cinnamon-application-themes-manager.desktop
	@echo "Version=1.0" >> $(DESKTOPDIR)/cinnamon-application-themes-manager.desktop
	@echo "Type=Application" >> $(DESKTOPDIR)/cinnamon-application-themes-manager.desktop
	@echo "Name=Application Theme Manager" >> $(DESKTOPDIR)/cinnamon-application-themes-manager.desktop
	@echo "Comment=Manage GTK application themes" >> $(DESKTOPDIR)/cinnamon-application-themes-manager.desktop
	@echo "Exec=$(BINDIR)/cinnamon-application-themes-manager.pl" >> $(DESKTOPDIR)/cinnamon-application-themes-manager.desktop
	@echo "Icon=cs-themes" >> $(DESKTOPDIR)/cinnamon-application-themes-manager.desktop
	@echo "Terminal=false" >> $(DESKTOPDIR)/cinnamon-application-themes-manager.desktop
	@echo "StartupNotify=true" >> $(DESKTOPDIR)/cinnamon-application-themes-manager.desktop
	@echo "Categories=Settings;DesktopSettings;GTK;" >> $(DESKTOPDIR)/cinnamon-application-themes-manager.desktop
	@echo "Keywords=theme;gtk;application;appearance;" >> $(DESKTOPDIR)/cinnamon-application-themes-manager.desktop
	@echo "  Created cinnamon-application-themes-manager.desktop"
	@# Icon Theme Manager
	@echo "[Desktop Entry]" > $(DESKTOPDIR)/cinnamon-icon-themes-manager.desktop
	@echo "Version=1.0" >> $(DESKTOPDIR)/cinnamon-icon-themes-manager.desktop
	@echo "Type=Application" >> $(DESKTOPDIR)/cinnamon-icon-themes-manager.desktop
	@echo "Name=Icon Theme Manager" >> $(DESKTOPDIR)/cinnamon-icon-themes-manager.desktop
	@echo "Comment=Manage desktop icon themes" >> $(DESKTOPDIR)/cinnamon-icon-themes-manager.desktop
	@echo "Exec=$(BINDIR)/cinnamon-icon-themes-manager.pl" >> $(DESKTOPDIR)/cinnamon-icon-themes-manager.desktop
	@echo "Icon=cs-icons" >> $(DESKTOPDIR)/cinnamon-icon-themes-manager.desktop
	@echo "Terminal=false" >> $(DESKTOPDIR)/cinnamon-icon-themes-manager.desktop
	@echo "StartupNotify=true" >> $(DESKTOPDIR)/cinnamon-icon-themes-manager.desktop
	@echo "Categories=Settings;DesktopSettings;GTK;" >> $(DESKTOPDIR)/cinnamon-icon-themes-manager.desktop
	@echo "Keywords=icons;theme;desktop;appearance;" >> $(DESKTOPDIR)/cinnamon-icon-themes-manager.desktop
	@echo "  Created cinnamon-icon-themes-manager.desktop"
	@# Cursor Theme Manager
	@echo "[Desktop Entry]" > $(DESKTOPDIR)/cinnamon-cursor-themes-manager.desktop
	@echo "Version=1.0" >> $(DESKTOPDIR)/cinnamon-cursor-themes-manager.desktop
	@echo "Type=Application" >> $(DESKTOPDIR)/cinnamon-cursor-themes-manager.desktop
	@echo "Name=Cursor Theme Manager" >> $(DESKTOPDIR)/cinnamon-cursor-themes-manager.desktop
	@echo "Comment=Manage mouse cursor themes" >> $(DESKTOPDIR)/cinnamon-cursor-themes-manager.desktop
	@echo "Exec=$(BINDIR)/cinnamon-cursor-themes-manager.pl" >> $(DESKTOPDIR)/cinnamon-cursor-themes-manager.desktop
	@echo "Icon=cs-mouse" >> $(DESKTOPDIR)/cinnamon-cursor-themes-manager.desktop
	@echo "Terminal=false" >> $(DESKTOPDIR)/cinnamon-cursor-themes-manager.desktop
	@echo "StartupNotify=true" >> $(DESKTOPDIR)/cinnamon-cursor-themes-manager.desktop
	@echo "Categories=Settings;DesktopSettings;GTK;" >> $(DESKTOPDIR)/cinnamon-cursor-themes-manager.desktop
	@echo "Keywords=cursor;mouse;pointer;theme;" >> $(DESKTOPDIR)/cinnamon-cursor-themes-manager.desktop
	@echo "  Created cinnamon-cursor-themes-manager.desktop"
	@# Background Manager
	@echo "[Desktop Entry]" > $(DESKTOPDIR)/cinnamon-backgrounds-manager.desktop
	@echo "Version=1.0" >> $(DESKTOPDIR)/cinnamon-backgrounds-manager.desktop
	@echo "Type=Application" >> $(DESKTOPDIR)/cinnamon-backgrounds-manager.desktop
	@echo "Name=Background Manager" >> $(DESKTOPDIR)/cinnamon-backgrounds-manager.desktop
	@echo "Comment=Manage desktop wallpapers and backgrounds" >> $(DESKTOPDIR)/cinnamon-backgrounds-manager.desktop
	@echo "Exec=$(BINDIR)/cinnamon-backgrounds-manager.pl" >> $(DESKTOPDIR)/cinnamon-backgrounds-manager.desktop
	@echo "Icon=cs-backgrounds" >> $(DESKTOPDIR)/cinnamon-backgrounds-manager.desktop
	@echo "Terminal=false" >> $(DESKTOPDIR)/cinnamon-backgrounds-manager.desktop
	@echo "StartupNotify=true" >> $(DESKTOPDIR)/cinnamon-backgrounds-manager.desktop
	@echo "Categories=Settings;DesktopSettings;GTK;" >> $(DESKTOPDIR)/cinnamon-backgrounds-manager.desktop
	@echo "Keywords=wallpaper;background;desktop;" >> $(DESKTOPDIR)/cinnamon-backgrounds-manager.desktop
	@echo "  Created cinnamon-backgrounds-manager.desktop"
	@# Font Manager
	@echo "[Desktop Entry]" > $(DESKTOPDIR)/cinnamon-font-manager.desktop
	@echo "Version=1.0" >> $(DESKTOPDIR)/cinnamon-font-manager.desktop
	@echo "Type=Application" >> $(DESKTOPDIR)/cinnamon-font-manager.desktop
	@echo "Name=Font Manager" >> $(DESKTOPDIR)/cinnamon-font-manager.desktop
	@echo "Comment=Manage system fonts" >> $(DESKTOPDIR)/cinnamon-font-manager.desktop
	@echo "Exec=$(BINDIR)/cinnamon-font-manager.pl" >> $(DESKTOPDIR)/cinnamon-font-manager.desktop
	@echo "Icon=cs-fonts" >> $(DESKTOPDIR)/cinnamon-font-manager.desktop
	@echo "Terminal=false" >> $(DESKTOPDIR)/cinnamon-font-manager.desktop
	@echo "StartupNotify=true" >> $(DESKTOPDIR)/cinnamon-font-manager.desktop
	@echo "Categories=Settings;DesktopSettings;GTK;" >> $(DESKTOPDIR)/cinnamon-font-manager.desktop
	@echo "Keywords=font;typography;text;" >> $(DESKTOPDIR)/cinnamon-font-manager.desktop
	@echo "  Created cinnamon-font-manager.desktop"
	@# Update desktop database
	@command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database $(DESKTOPDIR) 2>/dev/null || true

# Update PATH in ~/.bashrc if needed
update-path:
	@if ! echo ":$(PATH):" | grep -q ":$(HOME)/.local/bin:"; then \
		echo "Adding ~/.local/bin to PATH..."; \
		echo "" >> $(HOME)/.bashrc; \
		echo "# Added by Cinnamon Settings Manager" >> $(HOME)/.bashrc; \
		echo 'export PATH="$HOME/.local/bin:$PATH"' >> $(HOME)/.bashrc; \
		echo "PATH updated. Run 'source ~/.bashrc' to apply changes."; \
	else \
		echo "PATH already includes ~/.local/bin"; \
	fi

# Uninstall everything
uninstall:
	@echo "Removing installed files..."
	@rm -f $(BINDIR)/$(BINARY)
	@for script in $(PERL_SCRIPTS); do \
		rm -f $(BINDIR)/$script; \
	done
	@rm -f $(DESKTOPDIR)/cinnamon-*-manager.desktop
	@echo "Removing data directories..."
	@rm -rf $(DATADIR)
	@echo "Uninstallation complete."
	@echo "Note: PATH modifications in ~/.bashrc were not removed."

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -f $(BINARY)
	@rm -f *.o
	@echo "Clean complete."

# Run tests (placeholder for future test implementation)
test:
	@echo "Running tests..."
	@echo "Testing xcursor_extractor compilation..."
	@$(MAKE) clean
	@$(MAKE) build
	@echo "Build test passed."
	@echo "Testing Perl syntax..."
	@for script in $(PERL_SCRIPTS); do \
		if [ -f "$script" ]; then \
			perl -c "$script" || exit 1; \
			echo "  $script: OK"; \
		fi \
	done
	@echo "All tests passed."

# Show help
help:
	@echo "Cinnamon Settings Manager Build System"
	@echo ""
	@echo "Available targets:"
	@echo "  all          - Build xcursor_extractor (default)"
	@echo "  build        - Build xcursor_extractor"
	@echo "  check-deps   - Check build dependencies"
	@echo "  check-runtime - Check runtime dependencies"
	@echo "  install      - Build and install everything"
	@echo "  install-dirs - Create installation directories"
	@echo "  install-binary - Install xcursor_extractor binary"
	@echo "  install-scripts - Install Perl scripts"
	@echo "  install-desktop - Install desktop entries"
	@echo "  update-path  - Add ~/.local/bin to PATH"
	@echo "  uninstall    - Remove all installed files"
	@echo "  clean        - Remove build artifacts"
	@echo "  test         - Run basic tests"
	@echo "  help         - Show this help"
	@echo ""
	@echo "Installation directories:"
	@echo "  BINDIR  = $(BINDIR)"
	@echo "  DATADIR = $(DATADIR)"
	@echo "  DESKTOPDIR = $(DESKTOPDIR)"
