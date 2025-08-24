#!/usr/bin/perl
use strict;
use warnings;
use utf8;

# Cinnamon Settings Manager
# A modern settings application for Linux Mint Cinnamon
# Written in Perl with GTK3

use Gtk3 -init;
use Glib 'TRUE', 'FALSE';
use File::Spec;
use JSON qw(encode_json decode_json);
use Data::Dumper;
use Digest::MD5 qw(md5_hex);

$SIG{__WARN__} = sub {
    my $warning = shift;
    return if $warning =~ /Theme parsing error/;
    warn $warning;
};

# Main application class
package CinnamonSettingsManager;
    use Moo;

    has 'window' => (is => 'rw');
    has 'sidebar' => (is => 'rw');
    has 'content_area' => (is => 'rw');
    has 'search_entry' => (is => 'rw');
    has 'search_results' => (is => 'rw', default => sub { {} });
    has 'all_modules' => (is => 'rw', default => sub { [] });
    has 'header_bar' => (is => 'rw');
    has 'categories' => (is => 'rw', default => sub { [] });
    has 'current_category' => (is => 'rw');
    has 'settings_widgets' => (is => 'rw', default => sub { {} });
    has 'row_to_category' => (is => 'rw', default => sub { {} });

    sub BUILD {
        my $self = shift;
        $self->_initialize_directory_structure();
        $self->_initialize_categories();
        $self->_setup_ui();
        $self->_load_default_category();
                
        # Debug: Show distribution info
        $self->_show_distribution_info();
    }

    sub run {
        my $self = shift;
        $self->window->show_all();
        Gtk3::main();
    }

    sub _initialize_directory_structure {
        my $self = shift;
        
        # Create main application directory
        my $app_dir = $ENV{HOME} . '/.local/share/cinnamon-settings-manager';
        unless (-d $app_dir) {
            system("mkdir -p '$app_dir'");
            print "Created application directory: $app_dir\n";
        }
        
        # Create config subdirectory
        my $config_dir = "$app_dir/config";
        unless (-d $config_dir) {
            system("mkdir -p '$config_dir'");
            print "Created config directory: $config_dir\n";
        }
        
        # Create icons subdirectory
        my $icons_dir = "$app_dir/icons";
        unless (-d $icons_dir) {
            system("mkdir -p '$icons_dir'");
            print "Created icons directory: $icons_dir\n";
        }
        
        print "Directory structure initialized for Cinnamon Settings Manager\n";
    }
    
    sub _initialize_categories {
        my $self = shift;
        
        # Helper function to get icon name - check for custom first, then fallback
        my $get_icon = sub {
            my $icon_id = shift;
            my $fallback = shift;
            
            my $custom_icon_path = $ENV{HOME} . '/.local/share/cinnamon-settings-manager/icons/' . $icon_id . '.svg';
            if (-f $custom_icon_path) {
                return $custom_icon_path;  # Return full path for custom icons
            } else {
                return $fallback;  # Return icon name for system icons
            }
        };
        
        my $categories = [
            {
                id => 'appearance',
                name => 'Appearance',
                icon => $get_icon->('appearance', 'preferences-desktop-theme'),
                description => 'Themes, wallpapers, icons, and visual effects',
                modules => [
                    { id => 'backgrounds', name => 'Backgrounds', description => 'Wallpapers and background settings' },
                    { id => 'fonts', name => 'Fonts', description => 'System fonts and text rendering' },
                    { id => 'cursors', name => 'Cursors', description => 'Cursor themes' },
                    { id => 'applications', name => 'Applications', description => 'Application themes' },
                    { id => 'icons', name => 'Icons', description => 'Icon themes' },
                    { id => 'cinnamon', name => 'Cinnamon Desktop', description => 'Cinnamon desktop themes' },
                    { id => 'effects', name => 'Effects', description => 'Desktop effects and animations' },
                    { id => 'night_light', name => 'Night Light', description => 'Blue light filter settings' },
                    { id => 'color', name => 'Color', description => 'Color profiles and calibration' }
                ]
            },
            {
                id => 'desktop',
                name => 'Desktop',
                icon => $get_icon->('desktop', 'user-desktop'),
                description => 'Desktop environment and extensions',
                modules => [
                    { id => 'desktop', name => 'Desktop', description => 'Desktop icons and behavior' },
                    { id => 'applets', name => 'Applets', description => 'Manage panel applets' },
                    { id => 'desklets', name => 'Desklets', description => 'Desktop widgets and desklets' },
                    { id => 'extensions', name => 'Extensions', description => 'Cinnamon extensions' },
                    { id => 'screensaver', name => 'Screensaver', description => 'Screen lock and screensaver' },
                    { id => 'hot_corners', name => 'Hot Corners', description => 'Screen edge actions' },
                    { id => 'gestures', name => 'Gestures', description => 'Touchpad and mouse gestures' }
                ]
            },
            {
                id => 'panel',
                name => 'Panel',
                icon => $get_icon->('panel', 'preferences-desktop-panel'),
                description => 'Panel layout and configuration',
                modules => [
                    { id => 'panel', name => 'Panel', description => 'Panel size, position, and behavior' }
                ]
            },
            {
                id => 'windows',
                name => 'Windows',
                icon => $get_icon->('windows', 'preferences-system-windows'),
                description => 'Window management and behavior',
                modules => [
                    { id => 'windows', name => 'Windows', description => 'Window behavior and effects' },
                    { id => 'window_tiling', name => 'Window Tiling', description => 'Window tiling and snapping' },
                    { id => 'workspaces', name => 'Workspaces', description => 'Virtual desktop settings' },
                    { id => 'actions', name => 'Actions', description => 'Window and system actions' }
                ]
            },
            {
                id => 'hardware',
                name => 'Hardware',
                icon => $get_icon->('hardware', 'preferences-desktop-peripherals'),
                description => 'Input devices and hardware settings',
                modules => [
                    { id => 'mouse', name => 'Mouse and Touchpad', description => 'Pointer settings and touchpad' },
                    { id => 'keyboard', name => 'Keyboard', description => 'Keyboard settings and shortcuts' },
                    { id => 'graphics_tablet', name => 'Graphics Tablet', description => 'Graphics tablet and pen settings' },
                    { id => 'input_method', name => 'Input Method', description => 'Input method configuration' },
                    { id => 'disks', name => 'Disks', description => 'Disk drives and storage devices' },
                    { id => 'printers', name => 'Printers', description => 'Printer setup and configuration' }
                ]
            },
            {
                id => 'display',
                name => 'Display &amp; Audio',
                icon => $get_icon->('display_audio', 'preferences-desktop-display'),
                description => 'Display, audio, and multimedia settings',
                modules => [
                    { id => 'display', name => 'Display', description => 'Monitor settings and resolution' },
                    { id => 'sound', name => 'Sound', description => 'Audio devices and volume' }
                ]
            },
            {
                id => 'network',
                name => 'Network &amp; Connectivity',
                icon => $get_icon->('network', 'preferences-system-network'),
                description => 'Network, Bluetooth, and connectivity',
                modules => [
                    { id => 'network', name => 'Network', description => 'Network connections and settings' },
                    { id => 'bluetooth', name => 'Bluetooth', description => 'Bluetooth devices and pairing' }
                ]
            },
            {
                id => 'system',
                name => 'System',
                icon => $get_icon->('system', 'preferences-system'),
                description => 'System settings and preferences',
                modules => [
                    { id => 'general', name => 'General', description => 'General system settings' },
                    { id => 'date_time', name => 'Date and Time', description => 'Date, time, and timezone settings' },
                    { id => 'languages', name => 'Languages', description => 'Language and locale settings' },
                    { id => 'notifications', name => 'Notifications', description => 'System notifications and alerts' },
                    { id => 'preferred_applications', name => 'Preferred Applications', description => 'Default applications for file types' },
                    { id => 'startup_applications', name => 'Startup Applications', description => 'Applications that start automatically' },
                    { id => 'accessibility', name => 'Accessibility', description => 'Accessibility features and aids' },
                    { id => 'privacy', name => 'Privacy', description => 'Privacy and security settings' },
                    { id => 'power_management', name => 'Power Management', description => 'Power and battery settings' }
                ]
            },
            {
                id => 'accounts',
                name => 'Accounts &amp; Security',
                icon => $get_icon->('accounts', 'system-users'),
                description => 'User accounts and system security',
                modules => [
                    { id => 'account', name => 'Account', description => 'User account settings' },
                    { id => 'users_groups', name => 'Users and Groups', description => 'Manage user accounts and groups' },
                    { id => 'login_window', name => 'Login Window', description => 'Login screen settings' }
                ]
            },
            {
                id => 'administration',
                name => 'Administration',
                icon => $get_icon->('administration', 'preferences-system-privacy'),
                description => 'System administration and security',
                modules => [
                    { id => 'driver_manager', name => 'Driver Manager', description => 'Hardware drivers and management' },
                    { id => 'firewall', name => 'Firewall', description => 'System firewall configuration' },
                    { id => 'software_sources', name => 'Software Sources', description => 'Software repositories and sources' }
                ]
            },
            {
                id => 'hardware_info',
                name => 'Hardware Info',
                icon => $get_icon->('hardware_info', 'computer'),
                description => 'System information and hardware details',
                modules => [
                    { id => 'system_info', name => 'System Info', description => 'System and hardware information' }
                ]
            }
        ];
        
        $self->categories($categories);
    }
    
    sub _setup_ui {
        my $self = shift;
        
        # Create main window
        my $window = Gtk3::Window->new('toplevel');
        $window->set_title('Cinnamon Settings Manager');
        $window->set_default_size(1200, 900);
        $window->set_position('center');
        $window->set_icon_name('preferences-system');
        
        # Create header bar
        my $header_bar = Gtk3::HeaderBar->new();
        $header_bar->set_show_close_button(1);
        $header_bar->set_title('Cinnamon Settings Manager');
        $window->set_titlebar($header_bar);
        
        # Create main container
        my $main_box = Gtk3::Box->new('horizontal', 0);
        $window->add($main_box);
        
        # Create sidebar
        my $sidebar_frame = Gtk3::Frame->new();
        $sidebar_frame->set_shadow_type('in');
        $sidebar_frame->set_size_request(280, -1);
        
        my $sidebar_scroll = Gtk3::ScrolledWindow->new();
        $sidebar_scroll->set_policy('never', 'automatic');
        $sidebar_scroll->set_vexpand(1);
        
        my $search_entry = Gtk3::SearchEntry->new();
        $search_entry->set_placeholder_text('Search settings...');
        $search_entry->set_margin_left(6);
        $search_entry->set_margin_right(6);
        $search_entry->set_margin_top(6);
        $search_entry->set_margin_bottom(6);

        my $sidebar_content = Gtk3::Box->new('vertical', 0);
        $sidebar_content->pack_start($search_entry, 0, 0, 0);

        # Create sidebar BEFORE connecting signals that reference it
        my $sidebar = Gtk3::ListBox->new();
        $sidebar->set_selection_mode('single');

        $sidebar_content->pack_start($sidebar, 1, 1, 0);
        $sidebar_scroll->add($sidebar_content);

        $sidebar_frame->add($sidebar_scroll);
        $main_box->pack_start($sidebar_frame, 0, 0, 0);
        
        # NOW connect search signals after $sidebar is declared
        $search_entry->signal_connect('search-changed' => sub {
            $self->_filter_modules();
        });

        $search_entry->signal_connect('activate' => sub {
            $self->_filter_modules();
        });

        $search_entry->signal_connect('stop-search' => sub {
            $self->_cleanup_search_results();
            foreach my $child ($sidebar->get_children()) {
                if (exists $self->row_to_category->{$child + 0}) {
                    $child->show();
                }
            }
        });

        $search_entry->signal_connect('focus-out-event' => sub {
            my $entry = shift;
            if (length($entry->get_text()) == 0) {
                $self->_cleanup_search_results();
                # Show all original categories
                foreach my $child ($sidebar->get_children()) {
                    if (exists $self->row_to_category->{$child + 0}) {
                        $child->show();
                    }
                }
            }
            return 0; # Don't stop other handlers
        });
        
        # Create content area
        my $content_frame = Gtk3::Frame->new();
        $content_frame->set_shadow_type('in');
        
        my $content_scroll = Gtk3::ScrolledWindow->new();
        $content_scroll->set_policy('automatic', 'automatic');
        $content_scroll->set_vexpand(1);
        $content_scroll->set_hexpand(1);
        
        my $content_area = Gtk3::Box->new('vertical', 0);
        $content_area->set_margin_left(20);
        $content_area->set_margin_right(20);
        $content_area->set_margin_top(20);
        $content_area->set_margin_bottom(20);
        
        $content_scroll->add($content_area);
        $content_frame->add($content_scroll);
        $main_box->pack_start($content_frame, 1, 1, 0);
        
        # Populate sidebar
        $self->_populate_sidebar($sidebar);
        
        # Connect signals
        $sidebar->signal_connect('row-selected' => sub {
            my ($widget, $row) = @_;
            return unless $row;
            
            # Check if this is a search result or category
            my $module_data = $self->search_results->{$row + 0};
            if ($module_data) {
                # This is a search result - launch the module directly
                $self->_launch_module($module_data);
            } else {
                # This is a category - show category content
                my $category_id = $self->row_to_category->{$row + 0};
                $self->_show_category_by_id($category_id) if $category_id;
            }
        });

        $window->signal_connect('destroy' => sub { Gtk3::main_quit() });
        
        # Store references
        $self->window($window);
        $self->sidebar($sidebar);
        $self->search_entry($search_entry);
        $self->content_area($content_area);
        $self->header_bar($header_bar);
    }

    sub _cleanup_search_results {
        my $self = shift;
        
        my $sidebar = $self->sidebar;
        
        # Remove all search result rows (rows that are NOT in row_to_category)
        my @children_to_remove;
        foreach my $child ($sidebar->get_children()) {
            # If this row is not in our original category mapping, it's a search result
            if (!exists $self->row_to_category->{$child + 0}) {
                push @children_to_remove, $child;
            }
        }
        
        # Remove the search result rows
        foreach my $child (@children_to_remove) {
            $sidebar->remove($child);
            # Clean up any references
            delete $self->search_results->{$child + 0} if exists $self->search_results->{$child + 0};
        }
        
        print "Cleaned up " . @children_to_remove . " search result rows\n" if @children_to_remove;
    }
    
    sub _filter_modules {
        my $self = shift;
        
        my $search_text = $self->search_entry->get_text();
        my $sidebar = $self->sidebar;
        
        # Clean up any existing search result rows first
        $self->_cleanup_search_results();
        
        # Clear search results hash
        $self->search_results({});
        
        if (length($search_text) == 0) {
            # Show all original category rows
            foreach my $child ($sidebar->get_children()) {
                # Only show rows that are in our row_to_category mapping (original categories)
                if (exists $self->row_to_category->{$child + 0}) {
                    $child->show();
                }
            }
            return;
        }
        
        # Hide all category rows when searching
        foreach my $child ($sidebar->get_children()) {
            $child->hide();
        }
        
        # Search through all modules
        my @matching_modules;
        foreach my $category (@{$self->categories}) {
            foreach my $module (@{$category->{modules}}) {
                if ($module->{name} =~ /\Q$search_text\E/i || 
                    $module->{description} =~ /\Q$search_text\E/i) {
                    push @matching_modules, $module;
                }
            }
        }
        
        # Create temporary rows for search results
        foreach my $module (@matching_modules) {
            my $row = $self->_create_search_result_row($module);
            # Mark this as a search result row
            $self->search_results->{$row + 0} = $module;
            $sidebar->add($row);
            $row->show_all();
        }
    }

    sub _populate_sidebar {
        my ($self, $sidebar) = @_;
        
        foreach my $category (@{$self->categories}) {
            my $row = $self->_create_category_row($category);
            # Store category ID in our hash using the row address as key
            $self->row_to_category->{$row + 0} = $category->{id};
            $sidebar->add($row);
        }
    }
    
    sub _create_category_row {
        my ($self, $category) = @_;
        
        my $row = Gtk3::ListBoxRow->new();
        $row->set_size_request(-1, 64);
        
        my $box = Gtk3::Box->new('horizontal', 12);
        $box->set_margin_left(12);
        $box->set_margin_right(12);
        $box->set_margin_top(8);
        $box->set_margin_bottom(8);
        
        # Icon - handle both custom file paths and system icon names
        my $icon;
        if ($category->{icon} =~ /\.svg$/) {
            # This is a file path to a custom icon
            $icon = Gtk3::Image->new_from_file($category->{icon});
            $icon->set_pixel_size(32);
        } else {
            # This is a system icon name
            $icon = Gtk3::Image->new_from_icon_name($category->{icon}, 'dialog');
            $icon->set_pixel_size(32);
        }
        
        $box->pack_start($icon, 0, 0, 0);
        
        # Text box
        my $text_box = Gtk3::Box->new('vertical', 2);
        
        my $title = Gtk3::Label->new($category->{name});
        $title->set_halign('start');
        $title->set_markup("<b>" . $category->{name} . "</b>");
        
        my $description = Gtk3::Label->new($category->{description});
        $description->set_halign('start');
        $description->set_ellipsize('end');
        $description->set_max_width_chars(25);
        
        $text_box->pack_start($title, 0, 0, 0);
        $text_box->pack_start($description, 0, 0, 0);
        
        $box->pack_start($text_box, 1, 1, 0);
        $row->add($box);
        
        return $row;
    }
    
    sub _show_category_by_id {
        my ($self, $category_id) = @_;
        
        my ($category) = grep { $_->{id} eq $category_id } @{$self->categories};
        return unless $category;
        
        $self->_show_category($category);
    }
   
    sub _show_category {
        my ($self, $category) = @_;
        
        $self->current_category($category);
        
        # Clear content area
        my $content_area = $self->content_area;
        foreach my $child ($content_area->get_children()) {
            $content_area->remove($child);
        }
        
        # Create category header
        my $header = $self->_create_category_header($category);
        $content_area->pack_start($header, 0, 0, 0);
        
        # Add separator
        my $separator = Gtk3::Separator->new('horizontal');
        $separator->set_margin_top(10);
        $separator->set_margin_bottom(20);
        $content_area->pack_start($separator, 0, 0, 0);
        
        # Create modules grid
        my $modules_box = $self->_create_modules_box($category->{modules});
        $content_area->pack_start($modules_box, 1, 1, 0);
        
        $content_area->show_all();
    }
    
    sub _create_category_header {
        my ($self, $category) = @_;
        
        my $header_box = Gtk3::Box->new('horizontal', 12);
        
        # Large icon - handle both custom file paths and system icon names
        my $icon;
        if ($category->{icon} =~ /\.svg$/) {
            # This is a file path to a custom icon
            $icon = Gtk3::Image->new_from_file($category->{icon});
            $icon->set_pixel_size(48);
        } else {
            # This is a system icon name
            $icon = Gtk3::Image->new_from_icon_name($category->{icon}, 'dialog');
            $icon->set_pixel_size(48);
        }
        
        $header_box->pack_start($icon, 0, 0, 0);
        
        # Title and description
        my $text_box = Gtk3::Box->new('vertical', 4);
        
        my $title = Gtk3::Label->new();
        $title->set_markup("<span font='18' weight='bold'>" . $category->{name} . "</span>");
        $title->set_halign('start');
        
        my $description = Gtk3::Label->new($category->{description});
        $description->set_halign('start');
        
        $text_box->pack_start($title, 0, 0, 0);
        $text_box->pack_start($description, 0, 0, 0);
        
        $header_box->pack_start($text_box, 1, 1, 0);
        
        return $header_box;
    }
    
    sub _create_modules_box {
        my ($self, $modules) = @_;
        
        my $modules_box = Gtk3::Box->new('vertical', 6);
        
        foreach my $module (@$modules) {
            my $module_widget = $self->_create_module_widget($module);
            $modules_box->pack_start($module_widget, 0, 0, 0);
        }
        
        return $modules_box;
    }
    
    sub _create_module_widget {
        my ($self, $module) = @_;
        
        my $button = Gtk3::Button->new();
        $button->set_relief('none');
        
        my $box = Gtk3::Box->new('horizontal', 12);
        $box->set_margin_left(12);
        $box->set_margin_right(12);
        $box->set_margin_top(8);
        $box->set_margin_bottom(8);
        
        # Module icon - check for custom icon first, then fall back to system icons
        my %module_icons = (
            # Appearance
            'themes' => 'preferences-desktop-theme',
            'backgrounds' => 'preferences-desktop-wallpaper',
            'fonts' => 'preferences-desktop-font',
            'effects' => 'preferences-desktop-effects',
            'night_light' => 'night-light-symbolic',
            'color' => 'preferences-color',
            
            # Desktop
            'desktop' => 'user-desktop',
            'applets' => 'preferences-system',
            'desklets' => 'preferences-desktop',
            'extensions' => 'application-x-addon',
            'screensaver' => 'preferences-desktop-screensaver',
            'hot_corners' => 'preferences-desktop',
            'gestures' => 'input-touchpad',
            
            # Panel
            'panel' => 'preferences-desktop-panel',
            
            # Windows
            'windows' => 'preferences-system-windows',
            'window_tiling' => 'preferences-system-windows',
            'workspaces' => 'preferences-desktop-workspaces',
            'actions' => 'preferences-desktop-keyboard-shortcuts',
            
            # Hardware
            'mouse' => 'input-mouse',
            'keyboard' => 'input-keyboard',
            'graphics_tablet' => 'input-tablet',
            'input_method' => 'input-keyboard',
            'disks' => 'drive-harddisk',
            'printers' => 'printer',
            
            # Display & Audio
            'display' => 'preferences-desktop-display',
            'sound' => 'preferences-desktop-sound',
            
            # Network & Connectivity
            'network' => 'preferences-system-network',
            'bluetooth' => 'bluetooth',
            
            # System
            'general' => 'preferences-system',
            'date_time' => 'preferences-system-time',
            'languages' => 'preferences-desktop-locale',
            'notifications' => 'preferences-system-notifications',
            'preferred_applications' => 'preferences-desktop-default-applications',
            'startup_applications' => 'preferences-desktop-startup-applications',
            'accessibility' => 'preferences-desktop-accessibility',
            'privacy' => 'preferences-system-privacy',
            'power_management' => 'preferences-system-power',
            
            # Accounts & Security
            'account' => 'system-users',
            'users_groups' => 'system-users',
            'login_window' => 'system-log-out',
            
            # Administration
            'driver_manager' => 'jockey',
            'firewall' => 'network-wired',
            'software_sources' => 'software-properties',
            
            # Hardware Info
            'system_info' => 'computer'
        );
        
        # Check for custom icon in ~/.local/share/cinnamon-settings-manager/icons/
        my $custom_icon_path = $ENV{HOME} . '/.local/share/cinnamon-settings-manager/icons/' . $module->{id} . '.svg';
        my $icon;
        
        if (-f $custom_icon_path) {
            # Use custom SVG icon
            print "Using custom icon: $custom_icon_path\n";
            $icon = Gtk3::Image->new_from_file($custom_icon_path);
            $icon->set_pixel_size(24);  # Set appropriate size for SVG
        } else {
            # Fall back to system icon theme
            my $icon_name = $module_icons{$module->{id}} || 'preferences-other';
            $icon = Gtk3::Image->new_from_icon_name($icon_name, 'large-toolbar');
        }
        
        $box->pack_start($icon, 0, 0, 0);
        
        # Text content
        my $text_box = Gtk3::Box->new('vertical', 2);
        
        my $name_label = Gtk3::Label->new();
        $name_label->set_markup("<b>" . $module->{name} . "</b>");
        $name_label->set_halign('start');
        
        my $desc_label = Gtk3::Label->new($module->{description});
        $desc_label->set_halign('start');
        
        $text_box->pack_start($name_label, 0, 0, 0);
        $text_box->pack_start($desc_label, 0, 0, 0);
        
        $box->pack_start($text_box, 1, 1, 0);
        
        # Arrow icon
        my $arrow = Gtk3::Image->new_from_icon_name('go-next-symbolic', 'button');
        $box->pack_start($arrow, 0, 0, 0);
        
        $button->add($box);
        
        # Connect click signal
        $button->signal_connect('clicked' => sub {
            $self->_launch_module($module);
        });
        
        return $button;
    }
    
    sub _launch_module {
        my ($self, $module) = @_;

        print "Launching module: " . $module->{name} . "\n";

        # Special handling for backgrounds - use standalone application
        if ($module->{id} eq 'backgrounds') {
            $self->_launch_custom_module('cinnamon-backgrounds-manager.pl');
            return;
        }

        # Special handling for custom theme manager modules
        if ($module->{id} eq 'fonts') {
            $self->_launch_custom_module('cinnamon-font-manager.pl');
            return;
        }

        if ($module->{id} eq 'cursors') {
            $self->_launch_custom_module('cinnamon-cursor-themes-manager.pl');
            return;
        }

        if ($module->{id} eq 'applications') {
            $self->_launch_custom_module('cinnamon-application-themes-manager.pl');
            return;
        }

        if ($module->{id} eq 'icons') {
            $self->_launch_custom_module('cinnamon-icon-themes-manager.pl');
            return;
        }

        # Special handling for Cinnamon desktop themes
        if ($module->{id} eq 'cinnamon') {
            $self->_launch_custom_module('cinnamon-themes-manager.pl');
            return;
        }

        # Map module IDs to actual Cinnamon settings commands
        my %module_commands = (
                    
            # Distribution-aware commands
            'input_method' => $self->_get_input_method_command(),
            'languages' => $self->_get_languages_command(),
            'driver_manager' => $self->_get_driver_manager_command(),
            'software_sources' => $self->_get_software_sources_command(),
            'firewall' => $self->_get_firewall_command(),
            'login_window' => $self->_get_login_window_command(),
                        
            # Appearance
            'themes' => 'cinnamon-settings themes',
            'effects' => 'cinnamon-settings effects',
            'night_light' => 'cinnamon-settings nightlight',
            'color' => 'cinnamon-settings color',

            # Desktop
            'desktop' => 'cinnamon-settings desktop',
            'applets' => 'cinnamon-settings applets',
            'desklets' => 'cinnamon-settings desklets',
            'extensions' => 'cinnamon-settings extensions',
            'screensaver' => 'cinnamon-settings screensaver',
            'hot_corners' => 'cinnamon-settings hotcorner',
            'gestures' => 'cinnamon-settings gestures',

            # Panel
            'panel' => 'cinnamon-settings panel',

            # Windows
            'windows' => 'cinnamon-settings windows',
            'window_tiling' => 'cinnamon-settings tiling',
            'workspaces' => 'cinnamon-settings workspaces',
            'actions' => 'cinnamon-settings actions',

            # Hardware
            'mouse' => 'cinnamon-settings mouse',
            'keyboard' => 'cinnamon-settings keyboard',
            'graphics_tablet' => 'cinnamon-settings tablet',
            'input_method' => 'im-config',
            'disks' => 'gnome-disks',
            'printers' => 'system-config-printer',

            # Display & Audio
            'display' => 'cinnamon-settings display',
            'sound' => 'cinnamon-settings sound',

            # Network & Connectivity
            'network' => 'nm-connection-editor',
            'bluetooth' => 'blueman-manager',

            # System
            'general' => 'cinnamon-settings general',
            'date_time' => 'cinnamon-settings calendar',
            'languages' => 'gnome-language-selector',
            'notifications' => 'cinnamon-settings notifications',
            'preferred_applications' => 'cinnamon-settings default',
            'startup_applications' => 'cinnamon-settings startup',
            'accessibility' => 'cinnamon-settings accessibility',
            'privacy' => 'cinnamon-settings privacy',
            'power_management' => 'cinnamon-settings power',

            # Accounts & Security
            'account' => 'cinnamon-settings user',
            'users_groups' => 'cinnamon-settings-users',
            'login_window' => 'pkexec lightdm-settings',

            # Administration
            'driver_manager' => 'driver-manager',
            'firewall' => 'gufw',
            'software_sources' => 'software-sources',

            # Hardware Info
            'system_info' => 'cinnamon-settings info'
        );

    my $command = $module_commands{$module->{id}};

    if ($command) {
        print "Executing: $command\n";
        
        # Special handling for pkexec commands
        if ($command =~ /^pkexec\s/) {
            my $shell_command = "sh -c '$command' &";
            system($shell_command);
        } else {
            system("$command &");
        }
    } else {
        # Show dialog for unavailable modules
        my $distro = $self->_detect_distribution();
        my $distro_name = ucfirst($distro);
        
        my $dialog = Gtk3::MessageDialog->new(
            $self->window,
            'modal',
            'info',
            'ok',
            "Module not available: " . $module->{name} . "\n\n" .
            "This module is not available on $distro_name or the required " .
            "application is not installed on your system.\n\n" .
            "Some modules are distribution-specific and may not work " .
            "on all Linux distributions."
        );
        $dialog->run();
        $dialog->destroy();
        }
    }

    sub _launch_custom_module {
        my ($self, $module_name) = @_;

        # First try to launch from ~/.local/bin
        my $home = $ENV{HOME};
        my $local_path = "$home/.local/bin/$module_name";

        if (-f $local_path && -x $local_path) {
            print "Launching custom module from ~/.local/bin: $module_name\n";
            system("$local_path &");
            return;
        }

        # Try to find it in PATH
        if (system("which $module_name >/dev/null 2>&1") == 0) {
            print "Launching custom module from PATH: $module_name\n";
            system("$module_name &");
            return;
        }

        # Try current directory as fallback
        if (-f "./$module_name" && -x "./$module_name") {
            print "Launching custom module from current directory: $module_name\n";
            system("./$module_name &");
            return;
        }

        # Module not found - show error dialog
        my $dialog = Gtk3::MessageDialog->new(
            $self->window,
            'modal',
            'error',
            'ok',
            "Custom Module Not Found: $module_name\n\n" .
            "The module could not be found in any of these locations:\n" .
            "• ~/.local/bin/$module_name\n" .
            "• System PATH\n" .
            "• Current directory\n\n" .
            "Please ensure the module is installed and executable."
        );
        $dialog->run();
        $dialog->destroy();
    }
    
    # Load default category on startup
    sub _load_default_category {
        my $self = shift;
        
        if (@{$self->categories}) {
            # Select first category by default
            my $first_row = $self->sidebar->get_row_at_index(0);
            $self->sidebar->select_row($first_row);
            $self->_show_category($self->categories->[0]);
        }
    }
    
    sub _create_search_result_row {
        my ($self, $module) = @_;
        
        my $row = Gtk3::ListBoxRow->new();
        $row->set_size_request(-1, 48);
        
        my $box = Gtk3::Box->new('horizontal', 8);
        $box->set_margin_left(8);
        $box->set_margin_right(8);
        $box->set_margin_top(6);
        $box->set_margin_bottom(6);
        
        # Module icon - check for custom icon first
        my $custom_icon_path = $ENV{HOME} . '/.local/share/cinnamon-settings-manager/icons/' . $module->{id} . '.svg';
        my $icon;
        
        if (-f $custom_icon_path) {
            # Use custom SVG icon
            $icon = Gtk3::Image->new_from_file($custom_icon_path);
            $icon->set_pixel_size(20);  # Slightly smaller for search results
        } else {
            # Fall back to system icon
            $icon = Gtk3::Image->new_from_icon_name('preferences-other', 'large-toolbar');
        }
        
        $box->pack_start($icon, 0, 0, 0);
        
        # Text content
        my $text_box = Gtk3::Box->new('vertical', 2);
        
        my $name_label = Gtk3::Label->new($module->{name});
        $name_label->set_halign('start');
        $name_label->set_markup("<b>" . $module->{name} . "</b>");
        
        my $desc_label = Gtk3::Label->new($module->{description});
        $desc_label->set_halign('start');
        $desc_label->set_ellipsize('end');
        $desc_label->set_max_width_chars(25);
        
        $text_box->pack_start($name_label, 0, 0, 0);
        $text_box->pack_start($desc_label, 0, 0, 0);
        
        $box->pack_start($text_box, 1, 1, 0);
        $row->add($box);
        
        return $row;
    }
        
    sub _detect_distribution {
        my $self = shift;
        
        # Check for distribution-specific files
        if (-f '/etc/fedora-release') {
            return 'fedora';
        } elsif (-f '/etc/redhat-release') {
            return 'redhat';
        } elsif (-f '/etc/centos-release') {
            return 'centos';
        } elsif (-f '/etc/debian_version') {
            if (-f '/etc/lsb-release') {
                # Could be Ubuntu or Linux Mint
                my $lsb_content = `cat /etc/lsb-release 2>/dev/null`;
                if ($lsb_content =~ /Ubuntu/i) {
                    return 'ubuntu';
                } elsif ($lsb_content =~ /LinuxMint/i) {
                    return 'linuxmint';
                }
            }
            return 'debian';
        } elsif (-f '/etc/arch-release') {
            return 'arch';
        } elsif (-f '/etc/opensuse-release' || -f '/etc/SUSE-release') {
            return 'suse';
        } else {
            return 'unknown';
        }
    }
        
    sub _get_input_method_command {
        my $self = shift;
        my $distro = $self->_detect_distribution();
        
        if ($distro eq 'fedora' || $distro eq 'redhat' || $distro eq 'centos') {
            # Check which input method system is available
            if (system("which ibus-setup >/dev/null 2>&1") == 0) {
                return 'ibus-setup';
            } elsif (system("which im-chooser >/dev/null 2>&1") == 0) {
                return 'im-chooser';
            }
        } elsif ($distro eq 'ubuntu' || $distro eq 'linuxmint' || $distro eq 'debian') {
            if (system("which im-config >/dev/null 2>&1") == 0) {
                return 'im-config';
            }
        } elsif ($distro eq 'arch') {
            return 'ibus-setup';
        }
        
        return undef; # Command not available
    }

    sub _get_languages_command {
        my $self = shift;
        my $distro = $self->_detect_distribution();
        
        if ($distro eq 'fedora' || $distro eq 'redhat' || $distro eq 'centos') {
            if (system("which gnome-control-center >/dev/null 2>&1") == 0) {
                return 'gnome-control-center region';
            }
        } elsif ($distro eq 'ubuntu' || $distro eq 'linuxmint' || $distro eq 'debian') {
            if (system("which gnome-language-selector >/dev/null 2>&1") == 0) {
                return 'gnome-language-selector';
            }
        } elsif ($distro eq 'arch') {
            return 'gnome-control-center region';
        }
        
        return undef;
    }

    sub _get_driver_manager_command {
        my $self = shift;
        my $distro = $self->_detect_distribution();
        
        if ($distro eq 'linuxmint') {
            return 'driver-manager';
        } elsif ($distro eq 'ubuntu') {
            if (system("which software-properties-gtk >/dev/null 2>&1") == 0) {
                return 'software-properties-gtk --open-tab=4';  # Opens Additional Drivers tab
            }
        } elsif ($distro eq 'fedora' || $distro eq 'redhat' || $distro eq 'centos') {
            # Fedora doesn't have a dedicated driver manager GUI like Ubuntu
            # Users typically handle this through dnf or GNOME Software
            return undef;
        }
        
        return undef;
    }

    sub _get_software_sources_command {
        my $self = shift;
        my $distro = $self->_detect_distribution();
        
        if ($distro eq 'ubuntu' || $distro eq 'linuxmint' || $distro eq 'debian') {
            if (system("which software-properties-gtk >/dev/null 2>&1") == 0) {
                return 'software-properties-gtk';
            }
        } elsif ($distro eq 'fedora' || $distro eq 'redhat' || $distro eq 'centos') {
            # Fedora uses yum.repos.d files, no GUI equivalent
            # Could open the directory in file manager
            return 'nautilus /etc/yum.repos.d';
        } elsif ($distro eq 'arch') {
            return 'nautilus /etc/pacman.conf';
        }
        
        return undef;
    }

    sub _get_firewall_command {
        my $self = shift;
        my $distro = $self->_detect_distribution();
        
        if ($distro eq 'fedora' || $distro eq 'redhat' || $distro eq 'centos') {
            if (system("which firewall-config >/dev/null 2>&1") == 0) {
                return 'firewall-config';
            }
        } elsif ($distro eq 'ubuntu' || $distro eq 'linuxmint' || $distro eq 'debian') {
            if (system("which gufw >/dev/null 2>&1") == 0) {
                return 'gufw';
            }
        } elsif ($distro eq 'arch') {
            if (system("which gufw >/dev/null 2>&1") == 0) {
                return 'gufw';
            }
        }
        
        return undef;
    }

    sub _get_login_window_command {
        my $self = shift;
        my $distro = $self->_detect_distribution();
        
        if ($distro eq 'linuxmint') {
            return 'pkexec lightdm-settings';
        } elsif ($distro eq 'ubuntu' || $distro eq 'debian') {
            if (system("which lightdm-gtk-greeter-settings >/dev/null 2>&1") == 0) {
                return 'pkexec lightdm-gtk-greeter-settings';
            }
        } elsif ($distro eq 'fedora' || $distro eq 'redhat' || $distro eq 'centos') {
            # Fedora typically uses GDM, which has limited customization options
            if (system("which gnome-control-center >/dev/null 2>&1") == 0) {
                return 'gnome-control-center user-accounts';
            }
        }
        
        return undef;
    }

    sub _show_distribution_info {
        my $self = shift;
        
        my $distro = $self->_detect_distribution();
        print "Detected distribution: $distro\n";
        
        # Show available commands for debugging
        my %commands = (
            'input_method' => $self->_get_input_method_command(),
            'languages' => $self->_get_languages_command(),
            'driver_manager' => $self->_get_driver_manager_command(),
            'software_sources' => $self->_get_software_sources_command(),
            'firewall' => $self->_get_firewall_command(),
            'login_window' => $self->_get_login_window_command(),
        );
        
        print "Available distribution-specific commands:\n";
        foreach my $module (keys %commands) {
            my $cmd = $commands{$module} || 'NOT AVAILABLE';
            print "  $module: $cmd\n";
        }
    }

# Main execution
if (!caller) {
    my $app = CinnamonSettingsManager->new();
    $app->run();
}

1;