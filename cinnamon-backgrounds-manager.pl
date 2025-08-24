#!/usr/bin/perl
use strict;
use warnings;
use utf8;

# Desktop Backgrounds Manager - Standalone Application
# A dedicated wallpaper and background management application for Linux Mint Cinnamon
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
package DesktopBackgroundsManager {
    use Moo;

    has 'window' => (is => 'rw');
    has 'directory_list' => (is => 'rw');
    has 'wallpaper_grid' => (is => 'rw');
    has 'content_switcher' => (is => 'rw');
    has 'wallpaper_mode' => (is => 'rw');
    has 'settings_mode' => (is => 'rw');
    has 'zoom_level' => (is => 'rw', default => sub { 200 });
    has 'directory_paths' => (is => 'rw', default => sub { {} });
    has 'image_paths' => (is => 'rw', default => sub { {} });
    has 'image_widgets' => (is => 'rw', default => sub { {} });
    has 'loading_spinner' => (is => 'rw');
    has 'loading_label' => (is => 'rw');
    has 'loading_box' => (is => 'rw');
    has 'current_directory' => (is => 'rw');
    has 'cached_file_lists' => (is => 'rw', default => sub { {} });
    has 'config' => (is => 'rw');
    has 'last_selected_directory_path' => (is => 'rw');
    has 'thumbnail_cache' => (is => 'rw', default => sub { {} });

    sub BUILD {
        my $self = shift;
        $self->_initialize_configuration();
        $self->_setup_ui();
        $self->_initialize_thumbnail_cache();
        $self->_populate_background_directories();
        $self->_restore_last_selected_directory();
    }

    sub _initialize_configuration {
        my $self = shift;

        # Initialize directory structure first
        $self->_initialize_directory_structure();

        # Initialize configuration system
        $self->_init_config_system();

        # Load configuration
        my $config = $self->_load_config();
        $self->config($config);

        # Set zoom level from config
        $self->zoom_level($config->{thumbnail_size} || 200);
        $self->last_selected_directory_path($config->{last_selected_directory});

        print "Configuration initialized\n";
        print "  Thumbnail size: " . $self->zoom_level . "\n";
        print "  Custom directories: " . @{$config->{custom_directories} || []} . "\n";
        print "  Last directory: " . ($self->last_selected_directory_path || 'none') . "\n";
    }

    sub _initialize_directory_structure {
        my $self = shift;

        # Create main application directory for Desktop Backgrounds Manager
        my $app_dir = $ENV{HOME} . '/.local/share/cinnamon-backgrounds-manager';
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

        # Create thumbnails subdirectory
        my $thumbnails_dir = "$app_dir/thumbnails";
        unless (-d $thumbnails_dir) {
            system("mkdir -p '$thumbnails_dir'");
            print "Created thumbnails directory: $thumbnails_dir\n";
        }

        print "Directory structure initialized for Desktop Backgrounds Manager\n";
    }

    sub _setup_ui {
        my $self = shift;

        # Create main window
        my $window = Gtk3::Window->new('toplevel');
        $window->set_title('Desktop Backgrounds & Wallpapers');
        $window->set_default_size(1200, 900);
        $window->set_position('center');
        $window->set_icon_name('preferences-desktop-wallpaper');

        # Create header bar
        my $header = Gtk3::HeaderBar->new();
        $header->set_show_close_button(1);
        $header->set_title('Desktop Backgrounds & Wallpapers');
        $window->set_titlebar($header);

        # Main horizontal container
        my $main_container = Gtk3::Box->new('horizontal', 0);
        $window->add($main_container);

        # Left panel - Directory tree
        my $left_panel = Gtk3::Frame->new();
        $left_panel->set_shadow_type('in');
        $left_panel->set_size_request(280, -1);

        my $left_container = Gtk3::Box->new('vertical', 0);

        # Directory list
        my $dir_scroll_window = Gtk3::ScrolledWindow->new();
        $dir_scroll_window->set_policy('never', 'automatic');
        $dir_scroll_window->set_vexpand(1);

        my $directory_list = Gtk3::ListBox->new();
        $directory_list->set_selection_mode('single');

        $dir_scroll_window->add($directory_list);
        $left_container->pack_start($dir_scroll_window, 1, 1, 0);

        # Add/Remove buttons at bottom of left panel - using standard styling
        my $control_container = Gtk3::Box->new('horizontal', 6);
        $control_container->set_margin_left(6);
        $control_container->set_margin_right(6);
        $control_container->set_margin_top(6);
        $control_container->set_margin_bottom(6);

        my ($add_dir_button, $remove_dir_button) = $self->_create_directory_buttons();

        $control_container->pack_start($add_dir_button, 1, 1, 0);
        $control_container->pack_start($remove_dir_button, 1, 1, 0);

        $left_container->pack_start($control_container, 0, 0, 0);

        $left_panel->add($left_container);
        $main_container->pack_start($left_panel, 0, 0, 0);

        # Right panel - Wallpaper display and settings
        my $right_panel = Gtk3::Frame->new();
        $right_panel->set_shadow_type('in');

        my $right_container = Gtk3::Box->new('vertical', 0);

        # Top buttons (Wallpapers/Settings)
        my $mode_buttons = Gtk3::Box->new('horizontal', 0);
        $mode_buttons->set_margin_left(12);
        $mode_buttons->set_margin_right(12);
        $mode_buttons->set_margin_top(12);
        $mode_buttons->set_margin_bottom(6);

        my ($wallpaper_mode, $settings_mode) = $self->_create_mode_buttons();

        $mode_buttons->pack_start($wallpaper_mode, 1, 1, 0);
        $mode_buttons->pack_start($settings_mode, 1, 1, 0);

        $right_container->pack_start($mode_buttons, 0, 0, 0);

        # Content area (wallpapers or settings)
        my $content_switcher = Gtk3::Stack->new();
        $content_switcher->set_transition_type('slide-left-right');

        # Wallpapers content
        my $wallpaper_view = Gtk3::ScrolledWindow->new();
        $wallpaper_view->set_policy('automatic', 'automatic');
        $wallpaper_view->set_vexpand(1);

        my $wallpaper_grid = Gtk3::FlowBox->new();
        $wallpaper_grid->set_valign('start');
        $wallpaper_grid->set_max_children_per_line(8);
        $wallpaper_grid->set_min_children_per_line(2);
        $wallpaper_grid->set_selection_mode('single');
        $wallpaper_grid->set_margin_left(12);
        $wallpaper_grid->set_margin_right(12);
        $wallpaper_grid->set_margin_top(12);
        $wallpaper_grid->set_margin_bottom(12);
        $wallpaper_grid->set_row_spacing(12);
        $wallpaper_grid->set_column_spacing(12);

        $wallpaper_view->add($wallpaper_grid);
        $content_switcher->add_named($wallpaper_view, 'wallpapers');

        # Settings content
        my $settings_view = Gtk3::ScrolledWindow->new();
        $settings_view->set_policy('automatic', 'automatic');
        my $settings_content = $self->_create_background_settings();
        $settings_view->add($settings_content);
        $content_switcher->add_named($settings_view, 'settings');

        $right_container->pack_start($content_switcher, 1, 1, 0);

        # Bottom zoom controls and loading indicator - using standard styling
        my $bottom_container = Gtk3::Box->new('horizontal', 6);
        $bottom_container->set_margin_left(6);
        $bottom_container->set_margin_right(6);
        $bottom_container->set_margin_top(6);
        $bottom_container->set_margin_bottom(6);

        # Loading indicator
        my $loading_box = Gtk3::Box->new('horizontal', 6);
        my $loading_spinner = Gtk3::Spinner->new();
        my $loading_label = Gtk3::Label->new('Loading...');
        $loading_box->pack_start($loading_spinner, 0, 0, 0);
        $loading_box->pack_start($loading_label, 0, 0, 0);
        $loading_box->set_no_show_all(1); # Hide by default

        $bottom_container->pack_start($loading_box, 1, 1, 0);

        # Zoom controls (centered)
        my $zoom_controls = Gtk3::Box->new('horizontal', 6);
        $zoom_controls->set_halign('center');

        my ($zoom_out, $zoom_in) = $self->_create_zoom_buttons();

        $zoom_controls->pack_start($zoom_out, 0, 0, 0);
        $zoom_controls->pack_start($zoom_in, 0, 0, 0);

        $bottom_container->pack_start($zoom_controls, 1, 1, 0);
        $right_container->pack_start($bottom_container, 0, 0, 0);

        $right_panel->add($right_container);
        $main_container->pack_start($right_panel, 1, 1, 0);

        # Store references
        $self->window($window);
        $self->directory_list($directory_list);
        $self->wallpaper_grid($wallpaper_grid);
        $self->content_switcher($content_switcher);
        $self->wallpaper_mode($wallpaper_mode);
        $self->settings_mode($settings_mode);
        $self->loading_spinner($loading_spinner);
        $self->loading_label($loading_label);
        $self->loading_box($loading_box);

        # Connect signals
        $self->_connect_signals($add_dir_button, $remove_dir_button, $zoom_in, $zoom_out);

        print "UI setup completed\n";
    }

    sub _connect_signals {
        my ($self, $add_dir_button, $remove_dir_button, $zoom_in, $zoom_out) = @_;

        # Connect signals for mode buttons
        $self->_connect_mode_button_signals($self->wallpaper_mode, $self->settings_mode, $self->content_switcher);

        $self->directory_list->signal_connect('row-selected' => sub {
            my ($widget, $row) = @_;
            return unless $row;

            # Save the selected directory to config
            my $dir_path = $self->directory_paths->{$row + 0};
            if ($dir_path) {
                $self->config->{last_selected_directory} = $dir_path;
                $self->_save_config($self->config);
            }

            $self->_load_wallpapers_from_directory_async($row);
        });

        $add_dir_button->signal_connect('clicked' => sub {
            $self->_add_wallpaper_directory();
        });

        $remove_dir_button->signal_connect('clicked' => sub {
            $self->_remove_wallpaper_directory();
        });

        $zoom_in->signal_connect('clicked' => sub {
            my $new_zoom = ($self->zoom_level < 400) ? $self->zoom_level + 100 : 400;
            $self->zoom_level($new_zoom);
            $self->_update_wallpaper_zoom_async();
            # Save zoom level to config
            $self->config->{thumbnail_size} = $self->zoom_level;
            $self->_save_config($self->config);
        });

        $zoom_out->signal_connect('clicked' => sub {
            my $new_zoom = ($self->zoom_level > 200) ? $self->zoom_level - 100 : 200;
            $self->zoom_level($new_zoom);
            $self->_update_wallpaper_zoom_async();
            # Save zoom level to config
            $self->config->{thumbnail_size} = $self->zoom_level;
            $self->_save_config($self->config);
        });

        $self->wallpaper_grid->signal_connect('child-activated' => sub {
            my ($widget, $child) = @_;
            $self->_set_wallpaper($child);
        });

        $self->window->signal_connect('destroy' => sub {
            # Save configuration before closing
            $self->_save_config($self->config);
            # Clean up any running background processes
            $self->_cleanup_background_processes();
            Gtk3::main_quit();
        });

        print "Signal connections completed\n";
    }

    sub _create_background_settings {
        my $self = shift;

        my $settings_box = Gtk3::Box->new('vertical', 12);
        $settings_box->set_margin_left(20);
        $settings_box->set_margin_right(20);
        $settings_box->set_margin_top(20);
        $settings_box->set_margin_bottom(20);

        # Background Options section
        my $bg_frame = Gtk3::Frame->new();
        $bg_frame->set_label('Background Options');
        $bg_frame->set_label_align(0.02, 0.5);

        # Use horizontal box instead of grid for better control
        my $bg_container = Gtk3::Box->new('horizontal', 0);
        $bg_container->set_margin_left(12);
        $bg_container->set_margin_right(12);
        $bg_container->set_margin_top(12);
        $bg_container->set_margin_bottom(12);

        # Left section - Wallpaper options
        my $wallpaper_section = Gtk3::Box->new('vertical', 12);
        $wallpaper_section->set_hexpand(1); # Equal expansion

        my $wallpaper_check = Gtk3::CheckButton->new_with_label('Wallpaper');
        $wallpaper_check->set_active(1); # Default to enabled
        $wallpaper_section->pack_start($wallpaper_check, 0, 0, 0);

        # Aspect Ratio under Wallpaper
        my $aspect_label = Gtk3::Label->new('Aspect Ratio:');
        $aspect_label->set_halign('start');
        $aspect_label->set_margin_left(20); # Indent under wallpaper checkbox
        $wallpaper_section->pack_start($aspect_label, 0, 0, 0);

        my $aspect_combo = Gtk3::ComboBoxText->new();
        $aspect_combo->append_text('Mosaic');
        $aspect_combo->append_text('Centered');
        $aspect_combo->append_text('Scaled');
        $aspect_combo->append_text('Stretched');
        $aspect_combo->append_text('Zoomed');
        $aspect_combo->append_text('Spanned');
        $aspect_combo->set_active(2); # Scaled by default
        $aspect_combo->set_margin_left(20); # Indent under wallpaper checkbox
        $aspect_combo->set_halign('start');
        $wallpaper_section->pack_start($aspect_combo, 0, 0, 0);

        $bg_container->pack_start($wallpaper_section, 1, 1, 0); # Equal expansion

        # Vertical separator
        my $separator = Gtk3::Separator->new('vertical');
        $separator->set_margin_left(20);
        $separator->set_margin_right(20);
        $bg_container->pack_start($separator, 0, 0, 0);

        # Right section - Background Color
        my $color_section = Gtk3::Box->new('vertical', 12);
        $color_section->set_hexpand(1); # Equal expansion

        my $color_check = Gtk3::CheckButton->new_with_label('Background Color');
        $color_check->set_active(0); # Default to disabled
        $color_check->set_halign('start');
        $color_section->pack_start($color_check, 0, 0, 0);

        # Color picker under Background Color
        my $color_button = Gtk3::ColorButton->new();
        $color_button->set_use_alpha(0);
        $color_button->set_halign('start');
        $color_button->set_size_request(120, 32); # Make wider

        # Set default color to #134336
        my $default_color = Gtk3::Gdk::RGBA->new();
        $default_color->parse('#134336');
        $color_button->set_rgba($default_color);

        $color_section->pack_start($color_button, 0, 0, 0);

        $bg_container->pack_start($color_section, 1, 1, 0); # Equal expansion

        $bg_frame->add($bg_container);
        $settings_box->pack_start($bg_frame, 0, 0, 0);

        # Slideshow Options section (under Wallpaper)
        my $slideshow_frame = Gtk3::Frame->new();
        $slideshow_frame->set_label('Slideshow Options');
        $slideshow_frame->set_label_align(0.02, 0.5);

        my $slideshow_grid = Gtk3::Grid->new();
        $slideshow_grid->set_row_spacing(8);
        $slideshow_grid->set_column_spacing(12);
        $slideshow_grid->set_margin_left(12);
        $slideshow_grid->set_margin_right(12);
        $slideshow_grid->set_margin_top(12);
        $slideshow_grid->set_margin_bottom(12);

        # Enable slideshow
        my $slideshow_check = Gtk3::CheckButton->new_with_label('Enable slideshow');
        $slideshow_grid->attach($slideshow_check, 0, 0, 2, 1);

        # Change interval
        my $interval_label = Gtk3::Label->new('Change interval:');
        $interval_label->set_halign('start');
        my $interval_spin = Gtk3::SpinButton->new_with_range(1, 1440, 1);
        $interval_spin->set_value(30);
        my $interval_unit = Gtk3::Label->new('minutes');

        my $interval_box = Gtk3::Box->new('horizontal', 6);
        $interval_box->pack_start($interval_spin, 0, 0, 0);
        $interval_box->pack_start($interval_unit, 0, 0, 0);

        $slideshow_grid->attach($interval_label, 0, 1, 1, 1);
        $slideshow_grid->attach($interval_box, 1, 1, 1, 1);

        # Random order
        my $random_check = Gtk3::CheckButton->new_with_label('Random order');
        $slideshow_grid->attach($random_check, 0, 2, 2, 1);

        $slideshow_frame->add($slideshow_grid);
        $settings_box->pack_start($slideshow_frame, 0, 0, 0);

        # Set up widget state dependencies
        my $update_widget_states = sub {
            my $wallpaper_enabled = $wallpaper_check->get_active();
            my $color_enabled = $color_check->get_active();

            # Enable/disable aspect ratio based on wallpaper checkbox
            $aspect_label->set_sensitive($wallpaper_enabled);
            $aspect_combo->set_sensitive($wallpaper_enabled);

            # Enable/disable slideshow based on wallpaper checkbox
            $slideshow_frame->set_sensitive($wallpaper_enabled);

            # Enable/disable color picker based on background color checkbox
            $color_button->set_sensitive($color_enabled);
        };

        # Connect checkbox signals to update widget states and handle mutual exclusivity
        $wallpaper_check->signal_connect('toggled' => sub {
            if ($wallpaper_check->get_active() && $color_check->get_active()) {
                # If wallpaper is being enabled and color is already enabled, disable color
                $color_check->set_active(0);
            }
            $update_widget_states->();
        });

        $color_check->signal_connect('toggled' => sub {
            if ($color_check->get_active() && $wallpaper_check->get_active()) {
                # If color is being enabled and wallpaper is already enabled, disable wallpaper
                $wallpaper_check->set_active(0);
            }
            $update_widget_states->();
        });

        # Apply button
        my $apply_button = Gtk3::Button->new_with_label('Apply Settings');
        $apply_button->set_halign('center');

        # Connect apply button signal
        $apply_button->signal_connect('clicked' => sub {
            my $wallpaper_enabled = $wallpaper_check->get_active();
            my $color_enabled = $color_check->get_active();
            my $slideshow_enabled = $slideshow_check->get_active();

            if ($wallpaper_enabled) {
                my $aspect_mode = $aspect_combo->get_active_text();
                print "Applying wallpaper settings with aspect ratio: $aspect_mode\n";

                # Map aspect ratio to gsettings values
                my %aspect_mapping = (
                    'Mosaic' => 'wallpaper',
                    'Centered' => 'centered',
                    'Scaled' => 'scaled',
                    'Stretched' => 'stretched',
                    'Zoomed' => 'zoom',
                    'Spanned' => 'spanned'
                );

                my $picture_options = $aspect_mapping{$aspect_mode} || 'scaled';

                # Set the aspect ratio
                system("gsettings set org.cinnamon.desktop.background picture-options '$picture_options'");

                # Get current wallpaper and re-set it to trigger refresh
                my $current_uri = `gsettings get org.cinnamon.desktop.background picture-uri`;
                chomp($current_uri);
                $current_uri =~ s/^'|'$//g; # Remove quotes

                if ($current_uri && $current_uri ne '') {
                    print "Refreshing wallpaper to apply new aspect ratio\n";
                    system("gsettings set org.cinnamon.desktop.background picture-uri '$current_uri'");
                }

                if ($slideshow_enabled) {
                    my $interval = $interval_spin->get_value();
                    my $random = $random_check->get_active();
                    print "Enabling slideshow: interval=${interval}min, random=$random\n";
                    # Apply slideshow settings here
                }
            }

            if ($color_enabled) {
                my $color = $color_button->get_rgba();
                my $color_string = sprintf("#%02x%02x%02x",
                                         int($color->red * 255),
                                         int($color->green * 255),
                                         int($color->blue * 255));
                print "Applying background color: $color_string\n";
                system("gsettings set org.cinnamon.desktop.background primary-color '$color_string'");

                if (!$wallpaper_enabled) {
                    # Set to solid color mode when no wallpaper
                    system("gsettings set org.cinnamon.desktop.background picture-options 'none'");
                }
            }

        });

        $settings_box->pack_start($apply_button, 0, 0, 12);

        # Initialize widget states
        $update_widget_states->();

        return $settings_box;
    }

    sub _create_directory_buttons {
        my $self = shift;

        my $add_button = Gtk3::Button->new();
        $add_button->set_relief('none');
        $add_button->set_size_request(32, 32);
        $add_button->set_tooltip_text('Add wallpaper directory');

        my $add_icon = Gtk3::Image->new_from_icon_name('list-add-symbolic', 1);
        $add_button->add($add_icon);

        my $remove_button = Gtk3::Button->new();
        $remove_button->set_relief('none');
        $remove_button->set_size_request(32, 32);
        $remove_button->set_tooltip_text('Remove selected directory');

        my $remove_icon = Gtk3::Image->new_from_icon_name('list-remove-symbolic', 1);
        $remove_button->add($remove_icon);

        return ($add_button, $remove_button);
    }

    sub _create_zoom_buttons {
        my $self = shift;

        my $zoom_out = Gtk3::Button->new();
        $zoom_out->set_relief('none');
        $zoom_out->set_size_request(32, 32);
        $zoom_out->set_tooltip_text('Decrease wallpaper preview size');

        my $zoom_in = Gtk3::Button->new();
        $zoom_in->set_relief('none');
        $zoom_in->set_size_request(32, 32);
        $zoom_in->set_tooltip_text('Increase wallpaper preview size');

        # Try to use custom icons first, fallback to system icons
        my $icon_dir = $ENV{HOME} . '/.local/share/cinnamon-settings-manager/icons';

        # Zoom out icon
        my $zoom_out_icon_added = 0;
        if (-f "$icon_dir/zoom-out.svg") {
            eval {
                my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale("$icon_dir/zoom-out.svg", 32, 32, 1);
                if ($pixbuf) {
                    my $icon = Gtk3::Image->new_from_pixbuf($pixbuf);
                    $zoom_out->add($icon);
                    $zoom_out_icon_added = 1;
                }
            };
        }
        if (!$zoom_out_icon_added) {
            my $icon = Gtk3::Image->new_from_icon_name('zoom-out-symbolic', 1);
            $zoom_out->add($icon);
        }

        # Zoom in icon
        my $zoom_in_icon_added = 0;
        if (-f "$icon_dir/zoom-in.svg") {
            eval {
                my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale("$icon_dir/zoom-in.svg", 32, 32, 1);
                if ($pixbuf) {
                    my $icon = Gtk3::Image->new_from_pixbuf($pixbuf);
                    $zoom_in->add($icon);
                    $zoom_in_icon_added = 1;
                }
            };
        }
        if (!$zoom_in_icon_added) {
            my $icon = Gtk3::Image->new_from_icon_name('zoom-in-symbolic', 1);
            $zoom_in->add($icon);
        }

        return ($zoom_out, $zoom_in);
    }

    sub _create_mode_buttons {
        my $self = shift;

        my $wallpaper_mode = Gtk3::ToggleButton->new_with_label('Wallpapers');
        my $settings_mode = Gtk3::ToggleButton->new_with_label('Settings');

        $wallpaper_mode->set_active(1); # Active by default

        return ($wallpaper_mode, $settings_mode);
    }

    sub _connect_mode_button_signals {
        my ($self, $wallpaper_mode, $settings_mode, $content_switcher) = @_;

        # Handle clicks for wallpaper mode button
        $wallpaper_mode->signal_connect('toggled' => sub {
            my $widget = shift;
            if ($widget->get_active()) {
                $settings_mode->set_active(0);
                $content_switcher->set_visible_child_name('wallpapers');
            }
        });

        # Handle clicks for settings mode button
        $settings_mode->signal_connect('toggled' => sub {
            my $widget = shift;
            if ($widget->get_active()) {
                $wallpaper_mode->set_active(0);
                $content_switcher->set_visible_child_name('settings');
            }
        });
    }

    sub _initialize_thumbnail_cache {
        my $self = shift;

        # Create cache directory structure
        my $cache_dir = $ENV{HOME} . '/.local/share/cinnamon-backgrounds-manager';
        my $thumb_dir = "$cache_dir/thumbnails";

        unless (-d $cache_dir) {
            system("mkdir -p '$cache_dir'");
        }
        unless (-d $thumb_dir) {
            system("mkdir -p '$thumb_dir'");
        }

        # Initialize cache hash
        $self->thumbnail_cache({});

        print "Thumbnail cache initialized at: $thumb_dir\n";
    }

    sub _populate_background_directories {
        my $self = shift;

        # Default wallpaper directories - only directories that actually contain wallpapers
        my @default_dirs = (
            { name => 'Pictures', path => $ENV{HOME} . '/Pictures' },
            { name => 'Linux Mint', path => '/usr/share/backgrounds/linuxmint' },
            { name => 'Linux Mint Wallpapers', path => '/usr/share/backgrounds/linuxmint-wallpapers' },
        );

        # Add default directories
        foreach my $dir_info (@default_dirs) {
            next unless -d $dir_info->{path};

            my $row = $self->_create_directory_row($dir_info->{name}, $dir_info->{path});
            $self->directory_paths->{$row + 0} = $dir_info->{path};
            $self->directory_list->add($row);
        }

        # Add custom directories from config
        if ($self->config->{custom_directories}) {
            foreach my $custom_dir (@{$self->config->{custom_directories}}) {
                next unless -d $custom_dir->{path};

                my $row = $self->_create_directory_row($custom_dir->{name}, $custom_dir->{path});
                $self->directory_paths->{$row + 0} = $custom_dir->{path};
                $self->directory_list->add($row);
            }
        }

        print "Populated background directories\n";
    }

    sub _create_directory_row {
        my ($self, $name, $path) = @_;

        my $row = Gtk3::ListBoxRow->new();
        $row->set_size_request(-1, 48);

        my $box = Gtk3::Box->new('horizontal', 8);
        $box->set_margin_left(8);
        $box->set_margin_right(8);
        $box->set_margin_top(6);
        $box->set_margin_bottom(6);

        # Folder icon
        my $icon = Gtk3::Image->new_from_icon_name('folder', 'large-toolbar');
        $box->pack_start($icon, 0, 0, 0);

        # Text content
        my $text_box = Gtk3::Box->new('vertical', 2);

        my $name_label = Gtk3::Label->new($name);
        $name_label->set_halign('start');
        $name_label->set_markup("<b>$name</b>");

        my $path_label = Gtk3::Label->new($path);
        $path_label->set_halign('start');
        $path_label->set_ellipsize('middle');
        $path_label->set_max_width_chars(30);

        $text_box->pack_start($name_label, 0, 0, 0);
        $text_box->pack_start($path_label, 0, 0, 0);

        $box->pack_start($text_box, 1, 1, 0);
        $row->add($box);

        return $row;
    }

    sub _restore_last_selected_directory {
        my $self = shift;

        my $target_row = undef;
        my $target_path = $self->last_selected_directory_path;

        if ($target_path) {
            # Find the row that matches the saved directory path
            my $row_index = 0;
            foreach my $child ($self->directory_list->get_children()) {
                my $path = $self->directory_paths->{$child + 0};
                if ($path && $path eq $target_path) {
                    $target_row = $child;
                    last;
                }
                $row_index++;
            }

            if ($target_row) {
                print "Restoring last selected directory: $target_path\n";
            } else {
                print "Last selected directory not found: $target_path (selecting first)\n";
            }
        }

        # If no target row found, use first row
        if (!$target_row) {
            $target_row = $self->directory_list->get_row_at_index(0);
        }

        if ($target_row) {
            $self->directory_list->select_row($target_row);
            # The row-selected signal will automatically trigger _load_wallpapers_from_directory_async
        }
    }

    sub _load_wallpapers_from_directory_async {
        my ($self, $row) = @_;

        return unless $row;

        my $dir_path = $self->directory_paths->{$row + 0};
        return unless $dir_path && -d $dir_path;

        # Guard against duplicate loading of the same directory in quick succession
        my $current_time = time();
        if ($self->{last_loaded_directory} &&
            $self->{last_loaded_directory} eq $dir_path &&
            $self->{last_load_time} &&
            ($current_time - $self->{last_load_time}) < 2) {
            print "DEBUG: Preventing duplicate load of $dir_path (loaded " . ($current_time - $self->{last_load_time}) . " seconds ago)\n";
            return;
        }

        # Update guard variables
        $self->{last_loaded_directory} = $dir_path;
        $self->{last_load_time} = $current_time;

        print "DEBUG: Loading directory: $dir_path\n";

        # Show loading indicator
        $self->loading_box->show_all();
        $self->loading_spinner->start();
        $self->loading_label->set_text('Scanning directory...');

        # Clear existing wallpapers immediately - this prevents duplicates
        my $flowbox = $self->wallpaper_grid;
        foreach my $child ($flowbox->get_children()) {
            $flowbox->remove($child);
        }

        # Clear the image references to prevent memory leaks
        $self->image_paths({});
        $self->image_widgets({});

        # Store current directory for reference
        $self->current_directory($dir_path);

        # Use cached file list if available
        my $files_ref;
        if (exists $self->cached_file_lists->{$dir_path}) {
            $files_ref = $self->cached_file_lists->{$dir_path};
            print "Using cached file list for $dir_path (" . @$files_ref . " files)\n";
        } else {
            # Scan directory for image files
            opendir(my $dh, $dir_path) or return;
            my @files = grep { /\.(jpg|jpeg|png|bmp|gif|webp|tiff|tif)$/i } readdir($dh);
            closedir($dh);

            # Sort files naturally
            @files = sort {
                my ($a_name, $a_num);
                if ($a =~ /^(.*?)(\d+)/) {
                    ($a_name, $a_num) = ($1, $2);
                } else {
                    ($a_name, $a_num) = ($a, 0);
                }

                my ($b_name, $b_num);
                if ($b =~ /^(.*?)(\d+)/) {
                    ($b_name, $b_num) = ($1, $2);
                } else {
                    ($b_name, $b_num) = ($b, 0);
                }

                $a_name cmp $b_name || $a_num <=> $b_num;
            } @files;

            $files_ref = \@files;
            $self->cached_file_lists->{$dir_path} = $files_ref;
            print "Scanned $dir_path: " . @files . " image files found\n";
        }

        # Update loading label
        $self->loading_label->set_text("Loading " . @$files_ref . " wallpapers...");

        # Load wallpapers in batches to prevent UI freezing
        my $batch_size = 8;
        my $loaded_count = 0;
        my $total_files = @$files_ref;

        my $load_batch;
        $load_batch = sub {
            my $batch_start = $loaded_count;
            my $batch_end = ($loaded_count + $batch_size - 1 < $total_files - 1)
                           ? $loaded_count + $batch_size - 1
                           : $total_files - 1;

            # Check if directory changed while loading
            return if $self->current_directory ne $dir_path;

            for my $i ($batch_start..$batch_end) {
                my $file = $files_ref->[$i];
                my $full_path = "$dir_path/$file";

                my $wallpaper_widget = $self->_create_wallpaper_widget_fast($full_path, $self->zoom_level);
                $flowbox->add($wallpaper_widget);
            }

            $loaded_count = $batch_end + 1;

            # Update progress
            my $progress = int(($loaded_count / $total_files) * 100);
            $self->loading_label->set_text("Loading wallpapers... ${progress}%");

            $flowbox->show_all();

            if ($loaded_count < $total_files) {
                # Schedule next batch
                Glib::Timeout->add(10, $load_batch);
                return 0; # Don't repeat this timeout
            } else {
                # Loading complete
                $self->loading_spinner->stop();
                $self->loading_box->hide();
                print "Finished loading $total_files wallpapers from $dir_path\n";
                return 0;
            }
        };

        # Start loading first batch
        Glib::Timeout->add(10, $load_batch);
    }

    sub _create_wallpaper_widget_fast {
        my ($self, $image_path, $size) = @_;

        my $frame = Gtk3::Frame->new();
        $frame->set_shadow_type('in');

        my $box = Gtk3::Box->new('vertical', 6);
        $box->set_margin_left(6);
        $box->set_margin_right(6);
        $box->set_margin_top(6);
        $box->set_margin_bottom(6);

        # Create placeholder image initially with the SAVED size from config
        my $image = Gtk3::Image->new_from_icon_name('image-loading-symbolic', 6);
        $image->set_size_request($size, $size);

        $box->pack_start($image, 1, 1, 0);

        # Filename label
        my $filename = $image_path;
        $filename =~ s/.*\///;
        my $label = Gtk3::Label->new($filename);
        $label->set_ellipsize('middle');
        $label->set_max_width_chars(15);

        $box->pack_start($label, 0, 0, 0);
        $frame->add($box);

        # Store image path and widget reference
        $self->image_paths->{$frame + 0} = $image_path;
        $self->image_widgets->{$frame + 0} = $image;

        # Load thumbnail immediately but asynchronously using the SIZE from app_data
        Glib::Timeout->add(50, sub {
            $self->_load_thumbnail_async($image_path, $self->zoom_level, $image);
            return 0; # Don't repeat
        });

        return $frame;
    }

    sub _load_thumbnail_async {
        my ($self, $image_path, $size, $image_widget) = @_;

        print "DEBUG: Loading thumbnail for $image_path (size: $size)\n";

        # Generate cache key
        my $cache_key = $image_path . '_' . $size;

        # Check memory cache first
        if (exists $self->thumbnail_cache->{$cache_key}) {
            print "DEBUG: Found in memory cache\n";
            my $pixbuf = $self->thumbnail_cache->{$cache_key};
            $image_widget->set_from_pixbuf($pixbuf);
            return;
        }

        # Check disk cache
        my $cache_file = $self->_get_cache_filename($image_path, $size);
        print "DEBUG: Checking cache file: $cache_file\n";

        if (-f $cache_file && (stat($cache_file))[9] > (stat($image_path))[9]) {
            print "DEBUG: Loading from disk cache\n";
            # Load from disk cache in background
            Glib::Timeout->add(1, sub {
                eval {
                    my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($cache_file);
                    $self->thumbnail_cache->{$cache_key} = $pixbuf;
                    $image_widget->set_from_pixbuf($pixbuf);
                    print "DEBUG: Successfully loaded from cache\n";
                };
                if ($@) {
                    print "Error loading cached thumbnail: $@\n";
                    # Fall back to creating new thumbnail
                    $self->_create_thumbnail_async($image_path, $size, $image_widget, $cache_key);
                }
                return 0; # Don't repeat
            });
        } else {
            print "DEBUG: Creating new thumbnail\n";
            # Create new thumbnail
            $self->_create_thumbnail_async($image_path, $size, $image_widget, $cache_key);
        }
    }

    sub _create_thumbnail_async {
        my ($self, $image_path, $size, $image_widget, $cache_key) = @_;

        print "DEBUG: Creating thumbnail async for $image_path\n";

        Glib::Timeout->add(1, sub {
            eval {
                print "DEBUG: Actually creating pixbuf for $image_path\n";
                # Create thumbnail with proper scaling
                my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale($image_path, $size, $size, 1);

                # Cache in memory
                $self->thumbnail_cache->{$cache_key} = $pixbuf;

                # Manage cache size to prevent memory bloat
                $self->_manage_thumbnail_cache();

                # Update widget
                $image_widget->set_from_pixbuf($pixbuf);
                print "DEBUG: Successfully set pixbuf on widget\n";

                # Save to disk cache
                my $cache_file = $self->_get_cache_filename($image_path, $size);
                $pixbuf->savev($cache_file, 'png', [], []);
                print "DEBUG: Saved to cache: $cache_file\n";

            };
            if ($@) {
                print "Error creating thumbnail for $image_path: $@\n";
                # Set fallback icon
                $image_widget->set_from_icon_name('image-x-generic', 6);
            }
            return 0; # Don't repeat
        });
    }

    sub _get_cache_filename {
        my ($self, $image_path, $size) = @_;

        # Create hash of the full path for unique identification
        my $path_hash = Digest::MD5::md5_hex($image_path);
        my $cache_dir = $ENV{HOME} . '/.local/share/cinnamon-backgrounds-manager/thumbnails';

        return "$cache_dir/${path_hash}_${size}.png";
    }

    sub _update_wallpaper_zoom_async {
        my $self = shift;

        my $flowbox = $self->wallpaper_grid;
        my $size = $self->zoom_level;

        # Show loading indicator
        $self->loading_box->show_all();
        $self->loading_spinner->start();
        $self->loading_label->set_text('Updating zoom level...');

        # Get all children and process in batches
        my @children = $flowbox->get_children();
        my $total_children = @children;
        my $processed = 0;
        my $batch_size = 6;

        my $process_batch;
        $process_batch = sub {
            my $batch_start = $processed;
            my $batch_end = ($processed + $batch_size - 1 < $total_children - 1)
                           ? $processed + $batch_size - 1
                           : $total_children - 1;

            for my $i ($batch_start..$batch_end) {
                my $child = $children[$i];
                my $frame = $child->get_child();  # FlowBoxChild -> Frame

                my $image_widget = $self->image_widgets->{$frame + 0};
                my $image_path = $self->image_paths->{$frame + 0};

                if ($image_widget && $image_path) {
                    # Update image size request immediately for responsive UI
                    $image_widget->set_size_request($size, $size);

                    # Load new thumbnail asynchronously
                    $self->_load_thumbnail_async($image_path, $size, $image_widget);
                }
            }

            $processed = $batch_end + 1;

            # Update progress
            my $progress = int(($processed / $total_children) * 100);
            $self->loading_label->set_text("Updating zoom... ${progress}%");

            if ($processed < $total_children) {
                # Schedule next batch
                Glib::Timeout->add(50, $process_batch);
                return 0;
            } else {
                # Zoom update complete
                $self->loading_spinner->stop();
                $self->loading_box->hide();
                print "Zoom update completed for $total_children items\n";
                return 0;
            }
        };

        # Start processing first batch
        Glib::Timeout->add(10, $process_batch);
    }

    sub _cleanup_background_processes {
        my $self = shift;

        # Clear thumbnail cache to free memory
        $self->thumbnail_cache({});

        print "Background processes cleaned up\n";
    }

    sub _manage_thumbnail_cache {
        my $self = shift;

        my $cache = $self->thumbnail_cache;
        my $max_cache_items = 500;  # Limit memory usage

        if (keys %$cache > $max_cache_items) {
            # Remove oldest entries (simple FIFO, could be improved with LRU)
            my @keys = keys %$cache;
            my $to_remove = @keys - $max_cache_items;

            # Only run loop if there are actually items to remove
            if ($to_remove > 0) {
                for my $i (0..$to_remove-1) {
                    delete $cache->{$keys[$i]};
                }

                print "Trimmed thumbnail cache: removed $to_remove items\n";
            }
        }
    }

    sub _add_wallpaper_directory {
        my $self = shift;

        my $dialog = Gtk3::FileChooserDialog->new(
            'Select Wallpaper Directory',
            $self->window,
            'select-folder',
            'gtk-cancel' => 'cancel',
            'gtk-open' => 'accept'
        );

        if ($dialog->run() eq 'accept') {
            my $folder = $dialog->get_filename();
            my $name = $folder;
            $name =~ s/.*\///;

            # Check if directory already exists
            my $already_exists = 0;
            if ($self->config->{custom_directories}) {
                foreach my $existing_dir (@{$self->config->{custom_directories}}) {
                    if ($existing_dir->{path} eq $folder) {
                        $already_exists = 1;
                        last;
                    }
                }
            }

            if (!$already_exists) {
                my $row = $self->_create_directory_row($name, $folder);
                $self->directory_paths->{$row + 0} = $folder;
                $self->directory_list->add($row);
                $self->directory_list->show_all();

                # Save to config IMMEDIATELY
                if (!$self->config->{custom_directories}) {
                    $self->config->{custom_directories} = [];
                }
                push @{$self->config->{custom_directories}}, {
                    name => $name,
                    path => $folder
                };
                $self->_save_config($self->config);

                print "Added custom directory: $name ($folder)\n";

                # Auto-select the newly added directory
                $self->directory_list->select_row($row);
            } else {
                print "Directory already exists: $folder\n";
            }
        }

        $dialog->destroy();
    }

    sub _remove_wallpaper_directory {
        my $self = shift;

        my $selected_row = $self->directory_list->get_selected_row();
        return unless $selected_row;

        # Don't remove if it's one of the first 3 default directories
        my $row_index = $selected_row->get_index();
        if ($row_index < 3) {
            my $dialog = Gtk3::MessageDialog->new(
                $self->window,
                'modal',
                'warning',
                'ok',
                'Cannot remove default directories.'
            );
            $dialog->run();
            $dialog->destroy();
            return;
        }

        # Get the directory path being removed
        my $removed_path = $self->directory_paths->{$selected_row + 0};

        # Remove from config IMMEDIATELY
        if ($self->config->{custom_directories}) {
            $self->config->{custom_directories} = [
                grep { $_->{path} ne $removed_path } @{$self->config->{custom_directories}}
            ];

            # If this was the last selected directory, clear it
            if ($self->config->{last_selected_directory} &&
                $self->config->{last_selected_directory} eq $removed_path) {
                $self->config->{last_selected_directory} = undef;
            }

            $self->_save_config($self->config);
        }

        # Remove the directory
        delete $self->directory_paths->{$selected_row + 0};
        $self->directory_list->remove($selected_row);

        # Select the first directory after removal
        my $first_row = $self->directory_list->get_row_at_index(0);
        if ($first_row) {
            $self->directory_list->select_row($first_row);
        }

        print "Removed custom directory: $removed_path\n";
    }

    sub _set_wallpaper {
        my ($self, $child) = @_;

        my $frame = $child->get_child();
        my $image_path = $self->image_paths->{$frame + 0};

        return unless $image_path && -f $image_path;

        print "Setting wallpaper: $image_path\n";

        # Use gsettings to set the wallpaper
        system("gsettings set org.cinnamon.desktop.background picture-uri 'file://$image_path'");
    }

    sub _init_config_system {
        my $self = shift;

        # Create config directory structure
        my $config_dir = $ENV{HOME} . '/.local/share/cinnamon-backgrounds-manager/config';

        unless (-d $config_dir) {
            system("mkdir -p '$config_dir'");
            print "Created config directory: $config_dir\n";
        }
    }

    sub _get_config_file_path {
        my $self = shift;
        return $ENV{HOME} . '/.local/share/cinnamon-backgrounds-manager/config/settings.json';
    }

    sub _load_config {
        my $self = shift;

        my $config_file = $self->_get_config_file_path();
        my $config = {
            thumbnail_size => 200,
            custom_directories => [],
            last_selected_directory => undef,
        };

        if (-f $config_file) {
            eval {
                open my $fh, '<:encoding(UTF-8)', $config_file or die "Cannot open config file: $!";
                my $json_text = do { local $/; <$fh> };
                close $fh;

                if ($json_text && length($json_text) > 0) {
                    my $loaded_config = JSON->new->decode($json_text);
                    # Merge loaded config with defaults
                    foreach my $key (keys %$loaded_config) {
                        $config->{$key} = $loaded_config->{$key};
                    }

                    # Validate thumbnail_size range
                    if ($config->{thumbnail_size} < 200 || $config->{thumbnail_size} > 400) {
                        print "Invalid thumbnail size in config, using default\n";
                        $config->{thumbnail_size} = 200;
                    }

                    # Ensure custom_directories is an array ref
                    if (!ref($config->{custom_directories}) || ref($config->{custom_directories}) ne 'ARRAY') {
                        $config->{custom_directories} = [];
                    }

                    print "Loaded configuration from $config_file\n";
                    print "  Thumbnail size: " . $config->{thumbnail_size} . "\n";
                    print "  Custom directories: " . @{$config->{custom_directories}} . "\n";
                    print "  Last directory: " . ($config->{last_selected_directory} || 'none') . "\n";
                } else {
                    print "Config file is empty, using defaults\n";
                }
            };
            if ($@) {
                print "Error loading config: $@\n";
                print "Using default configuration\n";
            }
        } else {
            print "Config file not found, using defaults\n";
        }

        return $config;
    }

    sub _save_config {
        my ($self, $config) = @_;

        my $config_file = $self->_get_config_file_path();
        my $temp_file = "$config_file.tmp";

        print "DEBUG: Attempting to save config to: $config_file\n";
        print "DEBUG: Saving thumbnail_size: " . ($config->{thumbnail_size} || 'undef') . "\n";
        print "DEBUG: Saving custom_directories count: " . (@{$config->{custom_directories} || []}) . "\n";
        print "DEBUG: Saving last_selected_directory: " . ($config->{last_selected_directory} || 'undef') . "\n";

        eval {
            # Ensure config directory exists
            my $config_dir = $config_file;
            $config_dir =~ s/\/[^\/]+$//;
            unless (-d $config_dir) {
                system("mkdir -p '$config_dir'");
                print "DEBUG: Created config directory: $config_dir\n";
            }

            # Write to temporary file first (atomic operation)
            open my $fh, '>:encoding(UTF-8)', $temp_file or die "Cannot write temp config file: $!";
            print $fh JSON->new->pretty->encode($config);
            close $fh;

            # Verify the temp file was written and has content
            unless (-f $temp_file && -s $temp_file) {
                die "Temporary config file was not created or is empty";
            }

            # Move temporary file to final location
            rename($temp_file, $config_file) or die "Cannot move temp file to final location: $!";

            # Verify the final file exists and has content
            unless (-f $config_file && -s $config_file) {
                die "Final config file was not created or is empty";
            }

            print "DEBUG: Successfully saved configuration to $config_file\n";
            print "DEBUG: File size: " . (-s $config_file) . " bytes\n";
            print "  Thumbnail size: " . $config->{thumbnail_size} . "\n";
            print "  Custom directories: " . @{$config->{custom_directories}} . "\n";
            print "  Last directory: " . ($config->{last_selected_directory} || 'none') . "\n";

            # Verify by reading back the file
            open my $verify_fh, '<:encoding(UTF-8)', $config_file or die "Cannot read back config file for verification: $!";
            my $verify_content = do { local $/; <$verify_fh> };
            close $verify_fh;

            if ($verify_content && length($verify_content) > 0) {
                print "DEBUG: Config file verification successful\n";
            } else {
                die "Config file verification failed - file is empty";
            }

        };
        if ($@) {
            print "ERROR: Failed to save config: $@\n";
            # Clean up temp file if it exists
            unlink($temp_file) if -f $temp_file;
        }
    }

    sub run {
        my $self = shift;
        $self->window->show_all();
        print "Desktop Backgrounds Manager started\n";
        Gtk3::main();
    }
}

# Main execution
if (!caller) {
    my $app = DesktopBackgroundsManager->new();
    $app->run();
}

1;
