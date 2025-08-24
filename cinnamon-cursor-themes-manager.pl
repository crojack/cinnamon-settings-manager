#!/usr/bin/perl
use strict;
use warnings;
use utf8;

# Cursor Themes Manager - Standalone Application
# A dedicated cursor theme management application for Linux Mint Cinnamon
# Written in Perl with GTK3

use Gtk3 -init;
use Glib 'TRUE', 'FALSE';
use File::Spec;
use File::Basename qw(basename dirname);
use JSON qw(encode_json decode_json);
use Data::Dumper;
use Digest::MD5 qw(md5_hex);

$SIG{__WARN__} = sub {
    my $warning = shift;
    return if $warning =~ /Theme parsing error/;
    warn $warning;
};

# Main application class
package CursorThemesManager {
    use Moo;

    has 'window' => (is => 'rw');
    has 'directory_list' => (is => 'rw');
    has 'cursor_grid' => (is => 'rw');
    has 'content_switcher' => (is => 'rw');
    has 'cursor_mode' => (is => 'rw');
    has 'settings_mode' => (is => 'rw');
    has 'zoom_level' => (is => 'rw', default => sub { 200 });
    has 'directory_paths' => (is => 'rw', default => sub { {} });
    has 'theme_paths' => (is => 'rw', default => sub { {} });
    has 'loading_spinner' => (is => 'rw');
    has 'loading_label' => (is => 'rw');
    has 'loading_box' => (is => 'rw');
    has 'current_directory' => (is => 'rw');
    has 'cached_theme_lists' => (is => 'rw', default => sub { {} });
    has 'config' => (is => 'rw');
    has 'last_selected_directory_path' => (is => 'rw');
    has 'cursor_cache' => (is => 'rw', default => sub { {} });
    has 'cursor_preview_size' => (is => 'rw', default => sub { 40 });

    # Cursor types for preview extraction
    has 'cursor_types' => (is => 'ro', default => sub { [
        { name => 'left_ptr', desc => 'Default Arrow', aliases => ['default', 'arrow'] },
        { name => 'hand2', desc => 'Hand Pointer', aliases => ['hand1', 'hand', 'pointer'] },
        { name => 'xterm', desc => 'Text Input', aliases => ['text', 'ibeam'] },
        { name => 'watch', desc => 'Loading/Wait', aliases => ['wait', 'progress'] },
        { name => 'cross', desc => 'Crosshair', aliases => ['crosshair', 'tcross'] },
        { name => 'fleur', desc => 'Move/Drag', aliases => ['size_all', 'move'] },
        { name => 'sb_h_double_arrow', desc => 'Resize Horizontal', aliases => ['h_resize', 'col-resize', 'ew-resize'] },
        { name => 'sb_v_double_arrow', desc => 'Resize Vertical', aliases => ['v_resize', 'row-resize', 'ns-resize'] },
        { name => 'top_left_corner', desc => 'Resize NW', aliases => ['nw-resize', 'size_fdiag'] },
        { name => 'top_right_corner', desc => 'Resize NE', aliases => ['ne-resize', 'size_bdiag'] },
        { name => 'bottom_left_corner', desc => 'Resize SW', aliases => ['sw-resize'] },
        { name => 'bottom_right_corner', desc => 'Resize SE', aliases => ['se-resize'] },
        { name => 'question_arrow', desc => 'Help/Question', aliases => ['help', 'whats_this'] },
        { name => 'pirate', desc => 'Forbidden/No', aliases => ['forbidden', 'not-allowed', 'no-drop'] },
        { name => 'plus', desc => 'Add/Create', aliases => ['copy', 'dnd-copy'] },
        { name => 'grabbing', desc => 'Grabbing', aliases => ['closedhand', 'dnd-move'] },
        { name => 'bd_double_arrow', desc => 'Resize Diagonal', aliases => ['size_bdiag', 'nesw-resize'] },
        { name => 'fd_double_arrow', desc => 'Resize Anti-Diagonal', aliases => ['size_fdiag', 'nwse-resize'] }
    ] });

    sub BUILD {
        my $self = shift;
        $self->_initialize_configuration();
        $self->_setup_ui();
        $self->_populate_cursor_directories();
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

        # Set zoom level from config (for UI layout)
        $self->zoom_level($config->{thumbnail_size} || 200);

        # Set cursor preview size from config
        $self->cursor_preview_size($config->{cursor_preview_size} || 40);

        $self->last_selected_directory_path($config->{last_selected_directory});

        print "Configuration initialized\n";
        print "  Thumbnail size: " . $self->zoom_level . "\n";
        print "  Cursor preview size: " . $self->cursor_preview_size . "\n";
        print "  Custom directories: " . @{$config->{custom_directories} || []} . "\n";
        print "  Last directory: " . ($self->last_selected_directory_path || 'none') . "\n";
    }

    sub _initialize_directory_structure {
        my $self = shift;

        # Create main application directory for Cursor Themes Manager
        my $app_dir = $ENV{HOME} . '/.local/share/cinnamon-cursor-theme-manager';
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

        print "Directory structure initialized for Cinnamon Cursor Themes Manager\n";
    }

    sub _init_config_system {
        my $self = shift;

        # Create config directory structure
        my $config_dir = $ENV{HOME} . '/.local/share/cinnamon-cursor-theme-manager/config';

        unless (-d $config_dir) {
            system("mkdir -p '$config_dir'");
            print "Created config directory: $config_dir\n";
        }
    }

    sub _get_config_file_path {
        my $self = shift;
        return $ENV{HOME} . '/.local/share/cinnamon-cursor-theme-manager/config/settings.json';
    }

    sub _get_cache_filename {
        my ($self, $theme_name, $cursor_type) = @_;

        # Use the dynamic cursor preview size
        my $target_size = $self->cursor_preview_size;

        # Create hash of the theme name, cursor type, and size for unique identification
        my $cache_key = "${theme_name}_${cursor_type}_${target_size}";
        my $cache_hash = Digest::MD5::md5_hex($cache_key);
        my $cache_dir = $ENV{HOME} . '/.local/share/cinnamon-cursor-theme-manager/thumbnails';

        return "$cache_dir/${cache_hash}_${target_size}.png";
    }

    sub _setup_ui {
        my $self = shift;

        # Create main window
        my $window = Gtk3::Window->new('toplevel');
        $window->set_title('Cinnamon Cursor Themes Manager');
        $window->set_default_size(1200, 900);
        $window->set_position('center');
        $window->set_icon_name('preferences-desktop-theme');

        # Create header bar
        my $header = Gtk3::HeaderBar->new();
        $header->set_show_close_button(1);
        $header->set_title('Cinnamon Cursor Themes Manager');
        $window->set_titlebar($header);

        # Main horizontal container
        my $main_container = Gtk3::Box->new('horizontal', 0);
        $window->add($main_container);

        # Left panel - Directory tree
        my $left_panel = Gtk3::Frame->new();
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

        # Add/Remove buttons at bottom of left panel
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

        # Right panel - Cursor display and settings
        my $right_panel = Gtk3::Frame->new();

        my $right_container = Gtk3::Box->new('vertical', 0);

        # Top buttons (Cursor Themes/Settings)
        my $mode_buttons = Gtk3::Box->new('horizontal', 0);
        $mode_buttons->set_margin_left(12);
        $mode_buttons->set_margin_right(12);
        $mode_buttons->set_margin_top(12);
        $mode_buttons->set_margin_bottom(6);

        my ($cursor_mode, $settings_mode) = $self->_create_mode_buttons();

        $mode_buttons->pack_start($cursor_mode, 1, 1, 0);
        $mode_buttons->pack_start($settings_mode, 1, 1, 0);

        $right_container->pack_start($mode_buttons, 0, 0, 0);

        # Content area (cursor themes or settings)
        my $content_switcher = Gtk3::Stack->new();
        $content_switcher->set_transition_type('slide-left-right');
        $content_switcher->set_transition_duration(200);

        # Cursor themes content
        my $cursor_view = Gtk3::ScrolledWindow->new();
        $cursor_view->set_policy('automatic', 'automatic');
        $cursor_view->set_vexpand(1);

        my $cursor_grid = Gtk3::FlowBox->new();
        $cursor_grid->set_valign('start');
        $cursor_grid->set_halign('center');
        $cursor_grid->set_max_children_per_line(8);
        $cursor_grid->set_min_children_per_line(2);
        $cursor_grid->set_selection_mode('single');
        $cursor_grid->set_margin_left(12);
        $cursor_grid->set_margin_right(12);
        $cursor_grid->set_margin_top(12);
        $cursor_grid->set_margin_bottom(12);
        $cursor_grid->set_row_spacing(12);
        $cursor_grid->set_column_spacing(12);
        $cursor_grid->set_homogeneous(1);

        # Remove default selection background
        my $css_provider = Gtk3::CssProvider->new();
        $css_provider->load_from_data('
            flowboxchild {
                background: transparent;
            }
            flowboxchild:selected {
                background: transparent;
            }
        ');

        my $style_context = $cursor_grid->get_style_context();
        $style_context->add_provider($css_provider, 600); # GTK_STYLE_PROVIDER_PRIORITY_APPLICATION

        $cursor_view->add($cursor_grid);
        $content_switcher->add_named($cursor_view, 'cursor_themes');

        # Settings content
        my $settings_view = Gtk3::ScrolledWindow->new();
        $settings_view->set_policy('automatic', 'automatic');
        my $settings_content = $self->_create_cursor_settings();
        $settings_view->add($settings_content);
        $content_switcher->add_named($settings_view, 'settings');

        $right_container->pack_start($content_switcher, 1, 1, 0);

        # Bottom zoom controls and loading indicator
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

        # Zoom controls (centered) - now includes size label
        my $zoom_controls = Gtk3::Box->new('horizontal', 6);
        $zoom_controls->set_halign('center');

        my ($zoom_out, $zoom_in, $size_label) = $self->_create_custom_zoom_buttons();

        $zoom_controls->pack_start($zoom_out, 0, 0, 0);
        $zoom_controls->pack_start($size_label, 0, 0, 0);
        $zoom_controls->pack_start($zoom_in, 0, 0, 0);

        $bottom_container->pack_start($zoom_controls, 1, 1, 0);
        $right_container->pack_start($bottom_container, 0, 0, 0);

        $right_panel->add($right_container);
        $main_container->pack_start($right_panel, 1, 1, 0);

        # Store references
        $self->window($window);
        $self->directory_list($directory_list);
        $self->cursor_grid($cursor_grid);
        $self->content_switcher($content_switcher);
        $self->cursor_mode($cursor_mode);
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
        $self->_connect_mode_button_signals($self->cursor_mode, $self->settings_mode, $self->content_switcher);

        $self->directory_list->signal_connect('row-selected' => sub {
            my ($widget, $row) = @_;
            return unless $row;

            # Save the selected directory to config
            my $dir_path = $self->directory_paths->{$row + 0};
            if ($dir_path) {
                $self->config->{last_selected_directory} = $dir_path;
                $self->_save_config($self->config);
            }

            $self->_load_cursor_themes_from_directory($row);
        });

        $add_dir_button->signal_connect('clicked' => sub {
            $self->_add_cursor_directory();
        });

        $remove_dir_button->signal_connect('clicked' => sub {
            $self->_remove_cursor_directory();
        });

        # Updated zoom button functionality - DON'T force refresh, use cache
        $zoom_in->signal_connect('clicked' => sub {
            my $current_size = $self->cursor_preview_size;
            my $new_size = ($current_size < 64) ? $current_size + 8 : 64;  # Increment by 8px, max 64px

            $self->cursor_preview_size($new_size);
            $self->{size_label}->set_text($new_size . 'px');

            # Save cursor preview size to config
            $self->config->{cursor_preview_size} = $new_size;
            $self->_save_config($self->config);

            # Clear cursor cache since size changed, then refresh current directory
            $self->cursor_cache({});  # Clear memory cache
            my $selected_row = $self->directory_list->get_selected_row();
            if ($selected_row) {
                $self->_load_cursor_themes_from_directory($selected_row, 1); # Force refresh due to size change
            }

            print "Cursor preview size increased to ${new_size}px\n";
        });

        $zoom_out->signal_connect('clicked' => sub {
            my $current_size = $self->cursor_preview_size;
            my $new_size = ($current_size > 24) ? $current_size - 8 : 24;  # Decrement by 8px, min 24px

            $self->cursor_preview_size($new_size);
            $self->{size_label}->set_text($new_size . 'px');

            # Save cursor preview size to config
            $self->config->{cursor_preview_size} = $new_size;
            $self->_save_config($self->config);

            # Clear cursor cache since size changed, then refresh current directory
            $self->cursor_cache({});  # Clear memory cache
            my $selected_row = $self->directory_list->get_selected_row();
            if ($selected_row) {
                $self->_load_cursor_themes_from_directory($selected_row, 1); # Force refresh due to size change
            }

            print "Cursor preview size decreased to ${new_size}px\n";
        });

        # Connect FlowBox selection signal
        $self->cursor_grid->signal_connect('child-activated' => sub {
            my ($widget, $child) = @_;
            $self->_set_cursor_theme($child);
        });

        # Connect FlowBox selection changed signal to trigger redraws for selection frames
        $self->cursor_grid->signal_connect('selected-children-changed' => sub {
            my $widget = shift;
            # Queue redraw of all children to update selection frames
            foreach my $child ($widget->get_children()) {
                $child->queue_draw();
            }
        });

        $self->window->signal_connect('destroy' => sub {
            # Save configuration before closing
            $self->_save_config($self->config);
            Gtk3::main_quit();
        });

        print "Signal connections completed\n";
    }

    sub _create_cursor_settings {
        my $self = shift;

        my $settings_box = Gtk3::Box->new('vertical', 12);
        $settings_box->set_margin_left(20);
        $settings_box->set_margin_right(20);
        $settings_box->set_margin_top(20);
        $settings_box->set_margin_bottom(20);

        # Cursor Options section
        my $cursor_frame = Gtk3::Frame->new('Cursor Options');
        $cursor_frame->set_label_align(0.02, 0.5);

        my $cursor_grid = Gtk3::Grid->new();
        $cursor_grid->set_row_spacing(12);
        $cursor_grid->set_column_spacing(12);
        $cursor_grid->set_margin_left(12);
        $cursor_grid->set_margin_right(12);
        $cursor_grid->set_margin_top(12);
        $cursor_grid->set_margin_bottom(12);

        # Cursor Size
        my $size_label = Gtk3::Label->new('Cursor Size:');
        $size_label->set_halign('start');

        my $size_scale;
        eval {
            print "DEBUG: Creating size scale with integer step\n";
            $size_scale = Gtk3::Scale->new_with_range('horizontal', 24, 48, 8);
            print "DEBUG: Size scale created successfully\n" if $size_scale;
        };
        if ($@ || !$size_scale) {
            print "ERROR: Failed to create size scale: $@\n";
            # Use ComboBox as fallback
            $size_scale = Gtk3::ComboBoxText->new();
            $size_scale->append_text('24');
            $size_scale->append_text('32');
            $size_scale->append_text('40');
            $size_scale->append_text('48');
            $size_scale->set_active(0); # Default to 24
        } else {
            $size_scale->set_value(24);
            $size_scale->set_hexpand(1);
            $size_scale->set_draw_value(0);  # Changed from 1 to 0 to hide values

            # Add marks for supported cursor sizes
            eval {
                $size_scale->add_mark(24, 'bottom', '24');
                $size_scale->add_mark(32, 'bottom', '32');
                $size_scale->add_mark(40, 'bottom', '40');
                $size_scale->add_mark(48, 'bottom', '48');
            };
            if ($@) {
                print "Warning: Could not add marks to size scale: $@\n";
            }
        }

        $cursor_grid->attach($size_label, 0, 0, 1, 1);
        $cursor_grid->attach($size_scale, 1, 0, 1, 1);

        # Cursor Speed
        my $speed_label = Gtk3::Label->new('Cursor Speed:');
        $speed_label->set_halign('start');

        my $speed_scale;
        eval {
            print "DEBUG: Creating speed scale with integer range 5-50, step 1\n";
            # Use range 5-50 (representing 0.5-5.0) to avoid decimals entirely
            $speed_scale = Gtk3::Scale->new_with_range('horizontal', 5, 50, 1);
            print "DEBUG: Speed scale created successfully\n" if $speed_scale;
        };
        if ($@ || !$speed_scale) {
            print "ERROR: Failed to create speed scale: $@\n";
            # Use ComboBox as fallback
            $speed_scale = Gtk3::ComboBoxText->new();
            $speed_scale->append_text('0.5 (Slow)');
            $speed_scale->append_text('1.0 (Normal)');
            $speed_scale->append_text('2.0 (Fast)');
            $speed_scale->append_text('3.0 (Very Fast)');
            $speed_scale->append_text('5.0 (Maximum)');
            $speed_scale->set_active(1); # Default to Normal (1.0)
        } else {
            $speed_scale->set_value(10); # Default to 10 (representing 1.0)
            $speed_scale->set_hexpand(1);
            $speed_scale->set_draw_value(0);  # Changed from 1 to 0 to hide values

            # Add marks for speed (using integer positions)
            eval {
                $speed_scale->add_mark(5, 'bottom', 'Slow');     # 0.5
                $speed_scale->add_mark(10, 'bottom', 'Normal');  # 1.0
                $speed_scale->add_mark(20, 'bottom', 'Fast');    # 2.0
                $speed_scale->add_mark(50, 'bottom', 'Max');     # 5.0
            };
            if ($@) {
                print "Warning: Could not add marks to speed scale: $@\n";
            }
        }

        $cursor_grid->attach($speed_label, 0, 1, 1, 1);
        $cursor_grid->attach($speed_scale, 1, 1, 1, 1);

        # Left-handed mode
        my $left_handed_check = Gtk3::CheckButton->new_with_label('Left-handed mode');
        $cursor_grid->attach($left_handed_check, 0, 2, 2, 1);

        $cursor_frame->add($cursor_grid);
        $settings_box->pack_start($cursor_frame, 0, 0, 0);

        # Theme Information section
        my $info_frame = Gtk3::Frame->new('Current Theme Information');
        $info_frame->set_label_align(0.02, 0.5);

        my $info_box = Gtk3::Box->new('vertical', 8);
        $info_box->set_margin_left(12);
        $info_box->set_margin_right(12);
        $info_box->set_margin_top(12);
        $info_box->set_margin_bottom(12);

        # Current theme name
        my $current_theme = $self->_get_current_cursor_theme();
        my $theme_label = Gtk3::Label->new("Current Theme: $current_theme");
        $theme_label->set_halign('start');

        $info_box->pack_start($theme_label, 0, 0, 0);

        # Reset to default button
        my $reset_button = Gtk3::Button->new_with_label('Reset to Default Theme');
        $reset_button->set_halign('start');

        $info_box->pack_start($reset_button, 0, 0, 0);

        $info_frame->add($info_box);
        $settings_box->pack_start($info_frame, 0, 0, 0);

        # Apply button
        my $apply_button = Gtk3::Button->new_with_label('Apply Settings');
        $apply_button->set_halign('center');

        # Helper functions to get values from widgets
        my $get_size_value = sub {
            if (ref($size_scale) =~ /Scale/) {
                return int($size_scale->get_value());
            } elsif (ref($size_scale) =~ /ComboBox/) {
                my $text = $size_scale->get_active_text();
                return $text =~ /(\d+)/ ? $1 : 24;
            }
            return 24;
        };

        my $get_speed_value = sub {
            if (ref($speed_scale) =~ /Scale/) {
                return $speed_scale->get_value() / 10.0; # Convert back to decimal
            } elsif (ref($speed_scale) =~ /ComboBox/) {
                my $text = $speed_scale->get_active_text();
                return $text =~ /([\d.]+)/ ? $1 : 1.0;
            }
            return 1.0;
        };

    # Connect signals
    $apply_button->signal_connect('clicked' => sub {
        eval {
            my $size = $get_size_value->();
            my $speed = $get_speed_value->();
            my $left_handed = $left_handed_check->get_active();

            print "Applying cursor settings:\n";
            print "  Size: $size\n";
            print "  Speed: $speed\n";
            print "  Left-handed: " . ($left_handed ? 'true' : 'false') . "\n";

            # Apply cursor size
            system("gsettings set org.cinnamon.desktop.interface cursor-size $size");

            # Apply mouse settings
            my $acceleration = sprintf("%.1f", $speed);
            system("gsettings set org.cinnamon.desktop.peripherals.mouse speed $acceleration");

            # Apply left-handed mode with proper boolean formatting
            my $left_handed_value = $left_handed ? 'true' : 'false';
            system("gsettings set org.cinnamon.desktop.peripherals.mouse left-handed $left_handed_value");

            print "Settings applied successfully!\n";
        };
        if ($@) {
            print "ERROR applying settings: $@\n";
        }
    });

        $reset_button->signal_connect('clicked' => sub {
            eval {
                print "Resetting cursor theme to default\n";
                system("gsettings reset org.cinnamon.desktop.interface cursor-theme");
                system("gsettings reset org.cinnamon.desktop.interface cursor-size");

                # Update theme label
                my $new_theme = $self->_get_current_cursor_theme();
                $theme_label->set_text("Current Theme: $new_theme");
            };
            if ($@) {
                print "ERROR resetting theme: $@\n";
            }
        });

        $settings_box->pack_start($apply_button, 0, 0, 12);

        # Load current settings
        print "DEBUG: About to load current cursor settings\n";
        eval {
            $self->_load_current_cursor_settings($size_scale, $speed_scale, $left_handed_check, $get_size_value, $get_speed_value);
        };
        if ($@) {
            print "ERROR loading current settings: $@\n";
        }

        return $settings_box;
    }

    sub _create_directory_buttons {
        my $self = shift;

        my $add_button = Gtk3::Button->new();
        $add_button->set_relief('none');
        $add_button->set_size_request(32, 32);
        $add_button->set_tooltip_text('Add cursor theme directory');

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

    sub _create_custom_zoom_buttons {
        my $self = shift;

        my $icon_dir = $ENV{HOME} . '/.local/share/cinnamon-settings-manager/icons';
        my $zoom_out = $self->_create_styled_button_with_custom_icon("$icon_dir/zoom-out.svg", 'Decrease cursors preview size');
        my $zoom_in = $self->_create_styled_button_with_custom_icon("$icon_dir/zoom-in.svg", 'Increase cursors preview size');

        # Create size label to show current cursor preview size
        my $size_label = Gtk3::Label->new($self->cursor_preview_size . 'px');
        $size_label->set_margin_left(8);
        $size_label->set_margin_right(8);

        # Store reference for later updates
        $self->{size_label} = $size_label;

        return ($zoom_out, $zoom_in, $size_label);
    }

    sub _create_styled_button_with_custom_icon {
        my ($self, $icon_path, $tooltip) = @_;

        my $button = Gtk3::Button->new();
        $button->set_relief('none');
        $button->set_size_request(32, 32);
        $button->set_tooltip_text($tooltip);

        my $icon_added = 0;

        # Check if the custom icon file exists
        if (-f $icon_path) {
            eval {
                # Load SVG icon with proper scaling
                my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale($icon_path, 32, 32, 1);
                if ($pixbuf) {
                    my $icon = Gtk3::Image->new_from_pixbuf($pixbuf);
                    if ($icon) {
                        $button->add($icon);
                        $icon_added = 1;
                        print "Successfully loaded custom icon: $icon_path\n";
                    }
                }
            };
            if ($@) {
                print "Warning: Could not load custom icon $icon_path: $@\n";
            }
        } else {
            print "Warning: Custom icon not found at $icon_path\n";
        }

        # If custom icon failed, use system icon fallback
        if (!$icon_added) {
            eval {
                my $fallback_name = ($icon_path =~ /zoom-in/) ? 'zoom-in-symbolic' : 'zoom-out-symbolic';
                my $icon = Gtk3::Image->new_from_icon_name($fallback_name, 1);
                if ($icon) {
                    $button->add($icon);
                    $icon_added = 1;
                    print "Using system icon fallback: $fallback_name\n";
                }
            };
            if ($@) {
                print "Warning: Could not load system icon fallback: $@\n";
            }
        }

        # If both custom and system icons failed, use text fallback
        if (!$icon_added) {
            my $text = ($icon_path =~ /zoom-in/) ? '+' : '−';
            my $label = Gtk3::Label->new($text);
            $label->set_markup("<b>$text</b>");
            $button->add($label);
            print "Using text fallback: $text\n";
        }

        return $button;
    }

    sub _create_mode_buttons {
        my $self = shift;

        my $cursor_mode = Gtk3::ToggleButton->new_with_label('Cursor Themes');
        $cursor_mode->set_active(1); # active by default

        my $settings_mode = Gtk3::ToggleButton->new_with_label('Settings');

        return ($cursor_mode, $settings_mode);
    }

    sub _connect_mode_button_signals {
        my ($self, $cursor_mode, $settings_mode, $content_switcher) = @_;

        # Handle cursor mode button
        $cursor_mode->signal_connect('toggled' => sub {
            my $widget = shift;
            if ($widget->get_active()) {
                $settings_mode->set_active(0);
                $content_switcher->set_visible_child_name('cursor_themes');
            } elsif (!$settings_mode->get_active()) {
                # Ensure at least one button is active
                $widget->set_active(1);
            }
        });

        # Handle settings mode button
        $settings_mode->signal_connect('toggled' => sub {
            my $widget = shift;
            if ($widget->get_active()) {
                $cursor_mode->set_active(0);
                $content_switcher->set_visible_child_name('settings');
            } elsif (!$cursor_mode->get_active()) {
                # Ensure at least one button is active
                $widget->set_active(1);
            }
        });
    }

    sub _load_current_cursor_settings {
        my ($self, $size_scale, $speed_scale, $left_handed_check, $get_size_value, $get_speed_value) = @_;

        # Validate that all widgets are defined before trying to use them
        unless ($size_scale && ref($size_scale)) {
            print "ERROR: size_scale is not defined or not a valid widget\n";
            return;
        }

        unless ($speed_scale && ref($speed_scale)) {
            print "ERROR: speed_scale is not defined or not a valid widget\n";
            return;
        }

        unless ($left_handed_check && ref($left_handed_check)) {
            print "ERROR: left_handed_check is not defined or not a valid widget\n";
            return;
        }

        # Load current cursor size
        my $current_size = `gsettings get org.cinnamon.desktop.interface cursor-size 2>/dev/null`;
        chomp $current_size;
        if ($current_size && $current_size =~ /^\d+$/) {
            # Ensure the size is within the valid range (24-48)
            if ($current_size >= 24 && $current_size <= 48) {
                eval {
                    if (ref($size_scale) =~ /Scale/) {
                        $size_scale->set_value($current_size);
                    } elsif (ref($size_scale) =~ /ComboBox/) {
                        # Find the matching text in ComboBox
                        my $found_index = -1;
                        for my $i (0..3) {
                            $size_scale->set_active($i);
                            my $text = $size_scale->get_active_text();
                            if ($text eq $current_size) {
                                $found_index = $i;
                                last;
                            }
                        }
                        if ($found_index >= 0) {
                            $size_scale->set_active($found_index);
                        } else {
                            $size_scale->set_active(0); # Default to first option
                        }
                    }
                    print "Loaded cursor size: $current_size\n";
                };
                if ($@) {
                    print "ERROR setting cursor size: $@\n";
                    if (ref($size_scale) =~ /Scale/) {
                        $size_scale->set_value(24);
                    } elsif (ref($size_scale) =~ /ComboBox/) {
                        $size_scale->set_active(0);
                    }
                }
            } else {
                print "Cursor size $current_size out of range, using default\n";
                if (ref($size_scale) =~ /Scale/) {
                    $size_scale->set_value(24);
                } elsif (ref($size_scale) =~ /ComboBox/) {
                    $size_scale->set_active(0);
                }
            }
        } else {
            print "No valid cursor size found, using default\n";
            if (ref($size_scale) =~ /Scale/) {
                $size_scale->set_value(24);
            } elsif (ref($size_scale) =~ /ComboBox/) {
                $size_scale->set_active(0);
            }
        }

        # Load current mouse speed
        my $current_speed = `gsettings get org.cinnamon.desktop.peripherals.mouse speed 2>/dev/null`;
        chomp $current_speed;
        if ($current_speed && $current_speed =~ /^[\d.]+$/) {
            # Ensure the speed is within the valid range (0.5-5.0)
            my $speed_val = $current_speed + 0; # Convert to number
            if ($speed_val >= 0.5 && $speed_val <= 5.0) {
                eval {
                    if (ref($speed_scale) =~ /Scale/) {
                        # Convert decimal to integer scale (multiply by 10)
                        my $integer_value = int($speed_val * 10);
                        $speed_scale->set_value($integer_value);
                    } elsif (ref($speed_scale) =~ /ComboBox/) {
                        # Find closest match in ComboBox
                        my $best_index = 1; # Default to Normal
                        my @speed_values = (0.5, 1.0, 2.0, 3.0, 5.0);
                        my $min_diff = abs($speed_val - $speed_values[1]);

                        for my $i (0..$#speed_values) {
                            my $diff = abs($speed_val - $speed_values[$i]);
                            if ($diff < $min_diff) {
                                $min_diff = $diff;
                                $best_index = $i;
                            }
                        }
                        $speed_scale->set_active($best_index);
                    }
                    print "Loaded mouse speed: $speed_val\n";
                };
                if ($@) {
                    print "ERROR setting mouse speed: $@\n";
                    if (ref($speed_scale) =~ /Scale/) {
                        $speed_scale->set_value(10); # Default to 1.0
                    } elsif (ref($speed_scale) =~ /ComboBox/) {
                        $speed_scale->set_active(1); # Default to Normal
                    }
                }
            } else {
                print "Mouse speed $speed_val out of range, using default\n";
                if (ref($speed_scale) =~ /Scale/) {
                    $speed_scale->set_value(10);
                } elsif (ref($speed_scale) =~ /ComboBox/) {
                    $speed_scale->set_active(1);
                }
            }
        } else {
            print "No valid mouse speed found, using default\n";
            if (ref($speed_scale) =~ /Scale/) {
                $speed_scale->set_value(10);
            } elsif (ref($speed_scale) =~ /ComboBox/) {
                $speed_scale->set_active(1);
            }
        }

        # Load left-handed setting - fixed to handle boolean values properly
        my $left_handed = `gsettings get org.cinnamon.desktop.peripherals.mouse left-handed 2>/dev/null`;
        chomp $left_handed;
        # Remove any quotes and normalize the boolean value
        $left_handed =~ s/^'|'$//g;  # Remove single quotes if present
        $left_handed = lc($left_handed);  # Convert to lowercase

        eval {
            my $is_left_handed = ($left_handed eq 'true' || $left_handed eq '1');
            $left_handed_check->set_active($is_left_handed);
            print "Loaded left-handed setting: " . ($is_left_handed ? 'enabled' : 'disabled') . "\n";
        };
        if ($@) {
            print "ERROR setting left-handed option: $@\n";
            $left_handed_check->set_active(0); # Fallback to default
        }
    }

    sub _get_current_cursor_theme {
        my $self = shift;

        my $current_theme = `gsettings get org.cinnamon.desktop.interface cursor-theme 2>/dev/null`;
        chomp $current_theme;

        # Remove quotes if present
        $current_theme =~ s/^'|'$//g;

        return $current_theme || 'default';
    }

    sub _populate_cursor_directories {
        my $self = shift;

        # Clear existing entries first to prevent duplicates
        foreach my $child ($self->directory_list->get_children()) {
            $self->directory_list->remove($child);
        }
        $self->directory_paths({});  # Clear path mappings

        # Default cursor directories - ONLY the ones that actually work for cursor themes
        my @default_dirs = (
            { name => 'User Cursors', path => $ENV{HOME} . '/.icons' },
            { name => 'System Cursors', path => '/usr/share/icons' },
            { name => 'Local System Cursors', path => '/usr/local/share/icons' },
        );

        # Track added paths to prevent duplicates
        my %added_paths;

        # Add default directories
        foreach my $dir_info (@default_dirs) {
            next unless -d $dir_info->{path};
            next if $added_paths{$dir_info->{path}};  # Skip if already added

            my $row = $self->_create_directory_row($dir_info->{name}, $dir_info->{path});
            $self->directory_paths->{$row + 0} = $dir_info->{path};
            $self->directory_list->add($row);
            $added_paths{$dir_info->{path}} = 1;
        }

        # Add custom directories from config
        if ($self->config->{custom_directories}) {
            foreach my $custom_dir (@{$self->config->{custom_directories}}) {
                next unless -d $custom_dir->{path};
                next if $added_paths{$custom_dir->{path}};  # Skip if already added

                my $row = $self->_create_directory_row($custom_dir->{name}, $custom_dir->{path});
                $self->directory_paths->{$row + 0} = $custom_dir->{path};
                $self->directory_list->add($row);
                $added_paths{$custom_dir->{path}} = 1;
            }
        }

        print "Populated cursor directories without duplicates\n";
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

        my $name_label = Gtk3::Label->new();
        $name_label->set_markup("<b>$name</b>");
        $name_label->set_halign('start');

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
            # The row-selected signal will automatically trigger _load_cursor_themes_from_directory
        }
    }

    sub _load_cursor_themes_from_directory {
        my ($self, $row, $force_refresh) = @_;

        return unless $row;

        my $dir_path = $self->directory_paths->{$row + 0};
        return unless $dir_path && -d $dir_path;

        print "DEBUG: Loading cursor themes from directory: $dir_path\n";

        # Show loading indicator
        $self->loading_label->set_text('Scanning directory...');
        $self->loading_box->show_all();
        $self->loading_spinner->start();

        # Clear existing cursor themes immediately and completely
        my $flowbox = $self->cursor_grid;
        foreach my $child ($flowbox->get_children()) {
            $flowbox->remove($child);
            $child->destroy();  # Properly destroy widgets
        }

        # Clear the theme references completely
        $self->theme_paths({});

        # Store current directory for reference
        $self->current_directory($dir_path);

        # Process UI updates immediately
        while (Gtk3::events_pending()) {
            Gtk3::main_iteration();
        }

        # Use timeout to allow UI to update before scanning
        Glib::Timeout->add(50, sub {
            # Double-check we're still loading the same directory
            return 0 if !$self->current_directory || $self->current_directory ne $dir_path;

            # Check if we have cached theme list for this directory (unless force refresh)
            my @themes;
            if (!$force_refresh && exists $self->cached_theme_lists->{$dir_path}) {
                @themes = @{$self->cached_theme_lists->{$dir_path}};
                print "Using cached theme list for $dir_path (" . @themes . " themes)\n";
                $self->loading_label->set_text('Loading cached themes...');
            } else {
                # Show scanning progress
                $self->loading_label->set_text('Scanning for cursor themes...');
                while (Gtk3::events_pending()) {
                    Gtk3::main_iteration();
                }

                # Scan directory for cursor themes
                @themes = $self->_scan_cursor_themes_with_progress($dir_path);
                $self->cached_theme_lists->{$dir_path} = \@themes;
                print "Scanned $dir_path: " . @themes . " cursor themes found\n";
            }

            # Quick load - just create the widgets without processing cursors again
            my $loaded_count = 0;
            my $total_themes = @themes;

            # Track loaded theme names to prevent duplicates within this directory
            my %loaded_themes;

            foreach my $theme_info (@themes) {
                # Skip if we've already loaded this theme name
                if ($loaded_themes{$theme_info->{name}}) {
                    print "Skipping duplicate theme: " . $theme_info->{name} . "\n";
                    next;
                }

                # Quick widget creation - check if all cursors are already cached
                my $theme_widget = $self->_create_cursor_preview_widget_cached($theme_info);
                if ($theme_widget) {
                    $flowbox->add($theme_widget);
                    $loaded_themes{$theme_info->{name}} = 1;  # Mark as loaded
                }

                $loaded_count++;

                # Update progress every 5 themes
                if ($loaded_count % 5 == 0 || $loaded_count == $total_themes) {
                    my $progress = $total_themes > 0 ? int(($loaded_count / $total_themes) * 100) : 100;
                    $self->loading_label->set_text("Loading themes... ${progress}% (${loaded_count}/${total_themes})");

                    # Process UI updates
                    while (Gtk3::events_pending()) {
                        Gtk3::main_iteration();
                    }
                }
            }

            # Show all widgets at once
            $flowbox->show_all();

            # Loading complete - manage cache only ONCE at the end
            $self->_manage_cursor_cache();

            $self->loading_spinner->stop();
            $self->loading_box->hide();
            my $unique_count = keys %loaded_themes;
            print "Finished loading $unique_count unique cursor themes from $dir_path\n";

            return 0; # Don't repeat this timeout
        });
    }

    sub _create_cursor_preview_widget_cached {
        my ($self, $theme_info) = @_;

        # Check if we already have a widget for this theme path to prevent duplicates
        foreach my $existing_key (keys %{$self->theme_paths}) {
            my $existing_info = $self->theme_paths->{$existing_key};
            if ($existing_info && $existing_info->{path} eq $theme_info->{path}) {
                print "Warning: Widget already exists for theme path: " . $theme_info->{path} . "\n";
                return undef;  # Don't create duplicate
            }
        }

        # Check if all cursor files exist in cache before processing
        my $cursors_path = "$theme_info->{path}/cursors";
        return undef unless -d $cursors_path;

        my @cached_cursors;
        my $all_cached = 1;

        # Quick check - see if all cursors are already cached on disk
        foreach my $cursor_type (@{$self->cursor_types}) {
            my $cursor_file = $self->_find_cursor_file($cursors_path, $cursor_type);
            if ($cursor_file) {
                my $cache_file = $self->_get_cache_filename($theme_info->{name}, $cursor_type->{name});
                if (-f $cache_file && (stat($cache_file))[9] > (stat($cursor_file))[9]) {
                    # Cache exists and is newer than source
                    eval {
                        my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($cache_file);
                        if ($pixbuf) {
                            push @cached_cursors, {
                                pixbuf => $pixbuf,
                                name => $cursor_type->{desc}
                            };
                        } else {
                            $all_cached = 0;
                            last;
                        }
                    };
                    if ($@) {
                        $all_cached = 0;
                        last;
                    }
                } else {
                    $all_cached = 0;
                    last;
                }
            }
        }

        # If all cursors are cached, create widget quickly
        if ($all_cached && @cached_cursors > 0) {
            print "All cursors cached for theme: " . $theme_info->{display_name} . " - quick load\n";
            return $self->_create_cursor_widget_from_cached_pixbufs($theme_info, \@cached_cursors);
        } else {
            # Fall back to full processing (this will happen on first run or cache miss)
            print "Cache miss for theme: " . $theme_info->{display_name} . " - full processing\n";
            return $self->_create_cursor_preview_widget($theme_info);
        }
    }

    sub _create_cursor_widget_from_cached_pixbufs {
        my ($self, $theme_info, $cached_cursors) = @_;

        # Create main container with proper alignment
        my $container = Gtk3::Box->new('vertical', 4);
        $container->set_size_request(300, 450); # Width 300, height for dual panels + label
        $container->set_halign('center');  # Center the container horizontally
        $container->set_valign('start');   # Align to top vertically

        # Create light panel (top)
        my $light_panel = Gtk3::DrawingArea->new();
        $light_panel->set_size_request(300, 200);
        $light_panel->set_halign('center');  # Center the drawing area

        # Create dark panel (bottom)
        my $dark_panel = Gtk3::DrawingArea->new();
        $dark_panel->set_size_request(300, 200);
        $dark_panel->set_halign('center');   # Center the drawing area

        # Light panel draw handler
        $light_panel->signal_connect('draw' => sub {
            my ($widget, $cr) = @_;

            # Draw rounded rectangle with light background
            $self->_draw_rounded_rect($cr, 0, 0, 300, 200, 0);
            $cr->set_source_rgb(1.00, 1.00, 1.00);
            $cr->fill_preserve();
            $cr->set_source_rgb(0.8, 0.8, 0.8);
            $cr->set_line_width(2);
            $cr->stroke();

            # Draw cursors in grid
            $self->_draw_cursor_grid($cr, $cached_cursors, 300, 200);

            return 0;
        });

        # Dark panel draw handler
        $dark_panel->signal_connect('draw' => sub {
            my ($widget, $cr) = @_;

            # Draw rounded rectangle with dark background
            $self->_draw_rounded_rect($cr, 0, 0, 300, 200, 0);
            $cr->set_source_rgb(0.30, 0.30, 0.30);
            $cr->fill_preserve();
            $cr->set_source_rgb(0.5, 0.5, 0.5);
            $cr->set_line_width(2);
            $cr->stroke();

            # Draw cursors in grid
            $self->_draw_cursor_grid($cr, $cached_cursors, 300, 200);

            return 0;
        });

        # Theme name label
        my $label = Gtk3::Label->new($theme_info->{display_name});
        $label->set_ellipsize('middle');
        $label->set_max_width_chars(30);
        $label->set_margin_top(8);
        $label->set_halign('center');  # Center the label

        # Pack everything with proper alignment
        $container->pack_start($light_panel, 0, 0, 0);
        $container->pack_start($dark_panel, 0, 0, 0);
        $container->pack_start($label, 0, 0, 0);

        # Store theme info for later retrieval - use unique key
        my $widget_key = $container + 0;
        $self->theme_paths->{$widget_key} = $theme_info;

        return $container;
    }

    sub _scan_cursor_themes_with_progress {
        my ($self, $dir_path) = @_;

        my @themes;
        my %seen_themes;  # Track themes by name to prevent duplicates

        # Open directory
        opendir(my $dh, $dir_path) or return @themes;
        my @entries = readdir($dh);
        closedir($dh);

        my $total_entries = @entries;
        my $processed = 0;

        foreach my $entry (@entries) {
            next if $entry =~ /^\.\.?$/; # Skip . and ..

            $processed++;

            # Update progress every few entries
            if ($processed % 10 == 0 || $processed == $total_entries) {
                my $progress = int(($processed / $total_entries) * 100);
                $self->loading_label->set_text("Scanning... ${progress}% (${processed}/${total_entries})");
                while (Gtk3::events_pending()) {
                    Gtk3::main_iteration();
                }
            }

            my $theme_path = "$dir_path/$entry";
            next unless -d $theme_path; # Only directories

            # Skip if we've already seen this theme name
            next if $seen_themes{$entry};

            # Check if this is a cursor theme directory
            my $cursor_dir = "$theme_path/cursors";

            # Must have cursors directory with actual cursor files
            next unless -d $cursor_dir;

            # Verify the cursors directory contains actual cursor files
            opendir(my $cdh, $cursor_dir) or next;
            my @cursor_files = grep { -f "$cursor_dir/$_" && $_ !~ /^\./ } readdir($cdh);
            closedir($cdh);

            # Skip if no cursor files found
            next unless @cursor_files > 0;

            # Create theme info
            my $theme_info = {
                name => $entry,
                path => $theme_path,
                display_name => $self->_get_cursor_theme_display_name($theme_path, $entry)
            };

            push @themes, $theme_info;
            $seen_themes{$entry} = 1;  # Mark as seen
        }

        # Sort themes by display name
        @themes = sort { $a->{display_name} cmp $b->{display_name} } @themes;

        print "Scanned $dir_path: found " . @themes . " unique cursor themes\n";
        return @themes;
    }


    sub _scan_cursor_themes {
        my ($self, $dir_path) = @_;

        my @themes;

        # Open directory
        opendir(my $dh, $dir_path) or return @themes;
        my @entries = readdir($dh);
        closedir($dh);

        foreach my $entry (@entries) {
            next if $entry =~ /^\.\.?$/; # Skip . and ..

            my $theme_path = "$dir_path/$entry";
            next unless -d $theme_path; # Only directories

            # Check if this is a cursor theme directory
            my $cursor_dir = "$theme_path/cursors";

            # Must have cursors directory with actual cursor files
            next unless -d $cursor_dir;

            # Verify the cursors directory contains actual cursor files
            opendir(my $cdh, $cursor_dir) or next;
            my @cursor_files = grep { -f "$cursor_dir/$_" && $_ !~ /^\./ } readdir($cdh);
            closedir($cdh);

            # Skip if no cursor files found
            next unless @cursor_files > 0;

            # Create theme info
            my $theme_info = {
                name => $entry,
                path => $theme_path,
                display_name => $self->_get_cursor_theme_display_name($theme_path, $entry)
            };

            push @themes, $theme_info;
        }

        # Sort themes by display name
        @themes = sort { $a->{display_name} cmp $b->{display_name} } @themes;

        return @themes;
    }

    sub _get_cursor_theme_display_name {
        my ($self, $theme_path, $fallback_name) = @_;

        my $index_file = "$theme_path/index.theme";
        return $fallback_name unless -f $index_file;

        # Try to read display name from index.theme
        open my $fh, '<', $index_file or return $fallback_name;

        while (my $line = <$fh>) {
            chomp $line;
            if ($line =~ /^Name\s*=\s*(.+)$/) {
                close $fh;
                return $1;
            }
        }

        close $fh;
        return $fallback_name;
    }

    sub _create_cursor_preview_widget {
        my ($self, $theme_info) = @_;

        # Check if we already have a widget for this theme path to prevent duplicates
        foreach my $existing_key (keys %{$self->theme_paths}) {
            my $existing_info = $self->theme_paths->{$existing_key};
            if ($existing_info && $existing_info->{path} eq $theme_info->{path}) {
                print "Warning: Widget already exists for theme path: " . $theme_info->{path} . "\n";
                return undef;  # Don't create duplicate
            }
        }

        # Create main container with proper alignment
        my $container = Gtk3::Box->new('vertical', 4);
        $container->set_size_request(300, 450); # Width 300, height for dual panels + label
        $container->set_halign('center');  # Center the container horizontally
        $container->set_valign('start');   # Align to top vertically

        # Load cursor pixbufs for this theme
        my @cursor_pixbufs = $self->_load_cursor_pixbufs_for_theme($theme_info);

        # Only create the widget if we have cursors to display
        if (@cursor_pixbufs == 0) {
            print "Warning: No cursor pixbufs loaded for theme: " . $theme_info->{display_name} . "\n";
            return undef;
        }

        # Create light panel (top)
        my $light_panel = Gtk3::DrawingArea->new();
        $light_panel->set_size_request(300, 200);
        $light_panel->set_halign('center');  # Center the drawing area

        # Create dark panel (bottom)
        my $dark_panel = Gtk3::DrawingArea->new();
        $dark_panel->set_size_request(300, 200);
        $dark_panel->set_halign('center');   # Center the drawing area

        # Light panel draw handler
        $light_panel->signal_connect('draw' => sub {
            my ($widget, $cr) = @_;

            # Draw rounded rectangle with light background
            $self->_draw_rounded_rect($cr, 0, 0, 300, 200, 0);
            $cr->set_source_rgb(1.00, 1.00, 1.00);
            $cr->fill_preserve();
            $cr->set_source_rgb(0.8, 0.8, 0.8);
            $cr->set_line_width(2);
            $cr->stroke();

            # Draw cursors in grid
            $self->_draw_cursor_grid($cr, \@cursor_pixbufs, 300, 200);

            return 0;
        });

        # Dark panel draw handler
        $dark_panel->signal_connect('draw' => sub {
            my ($widget, $cr) = @_;

            # Draw rounded rectangle with dark background
            $self->_draw_rounded_rect($cr, 0, 0, 300, 200, 0);
            $cr->set_source_rgb(0.30, 0.30, 0.30);
            $cr->fill_preserve();
            $cr->set_source_rgb(0.5, 0.5, 0.5);
            $cr->set_line_width(2);
            $cr->stroke();

            # Draw cursors in grid
            $self->_draw_cursor_grid($cr, \@cursor_pixbufs, 300, 200);

            return 0;
        });

        # Theme name label
        my $label = Gtk3::Label->new($theme_info->{display_name});
        $label->set_ellipsize('middle');
        $label->set_max_width_chars(30);
        $label->set_margin_top(8);
        $label->set_halign('center');  # Center the label

        # Pack everything with proper alignment
        $container->pack_start($light_panel, 0, 0, 0);
        $container->pack_start($dark_panel, 0, 0, 0);
        $container->pack_start($label, 0, 0, 0);

        # Store theme info for later retrieval - use unique key
        my $widget_key = $container + 0;
        $self->theme_paths->{$widget_key} = $theme_info;

        print "Created preview widget for theme: " . $theme_info->{display_name} . " with " . @cursor_pixbufs . " cursors\n";

        return $container;
    }

    sub _load_cursor_pixbufs_for_theme {
        my ($self, $theme_info) = @_;

        my @cursor_pixbufs;
        my $cursors_path = "$theme_info->{path}/cursors";

        return @cursor_pixbufs unless -d $cursors_path;

        print "DEBUG: Loading cursor pixbufs for theme: " . $theme_info->{display_name} . "\n";

        foreach my $cursor_type (@{$self->cursor_types}) {
            my $cursor_file = $self->_find_cursor_file($cursors_path, $cursor_type);
            if ($cursor_file) {
                print "DEBUG: Found cursor file: $cursor_file for type: " . $cursor_type->{name} . "\n";
                my $pixbuf = $self->_extract_cursor_pixbuf_cached($cursor_file, $theme_info->{name}, $cursor_type->{name});
                if ($pixbuf) {
                    print "DEBUG: Successfully extracted pixbuf for: " . $cursor_type->{name} . "\n";
                    push @cursor_pixbufs, {
                        pixbuf => $pixbuf,
                        name => $cursor_type->{desc}
                    };
                } else {
                    print "DEBUG: Failed to extract pixbuf for: " . $cursor_type->{name} . "\n";
                }
            } else {
                print "DEBUG: No cursor file found for type: " . $cursor_type->{name} . "\n";
            }
        }

        print "DEBUG: Loaded " . @cursor_pixbufs . " cursor pixbufs for theme: " . $theme_info->{display_name} . "\n";

        return @cursor_pixbufs;
    }


    sub _extract_cursor_pixbuf_cached {
        my ($self, $cursor_file, $theme_name, $cursor_type) = @_;

        # Use dynamic cursor preview size for cache key
        my $target_size = $self->cursor_preview_size;

        # Generate cache key without file path to allow size-based caching
        my $cache_key = "${theme_name}_${cursor_type}_${target_size}";

        # Check memory cache first
        if (exists $self->cursor_cache->{$cache_key}) {
            print "DEBUG: Found cursor in memory cache: $cache_key\n";
            return $self->cursor_cache->{$cache_key};
        }

        # Check disk cache
        my $cache_file = $self->_get_cache_filename($theme_name, $cursor_type);

        if (-f $cache_file && (stat($cache_file))[9] > (stat($cursor_file))[9]) {
            print "DEBUG: Loading cursor from disk cache: $cache_file\n";
            eval {
                my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($cache_file);
                if ($pixbuf) {
                    # Verify the cached pixbuf matches the current target size
                    my $cached_width = $pixbuf->get_width();
                    my $cached_height = $pixbuf->get_height();
                    my $cached_size = $cached_width > $cached_height ? $cached_width : $cached_height;

                    # If cached size doesn't match current target size, regenerate
                    if (abs($cached_size - $target_size) > 2) {  # Allow 2px tolerance
                        print "DEBUG: Cached size ($cached_size) doesn't match target ($target_size), regenerating\n";
                        unlink $cache_file;  # Remove outdated cache
                    } else {
                        $self->cursor_cache->{$cache_key} = $pixbuf;
                        return $pixbuf;
                    }
                }
            };
            if ($@) {
                print "Error loading cached cursor: $@\n";
                # Delete corrupted cache file
                unlink $cache_file;
            } else {
                return $self->cursor_cache->{$cache_key} if $self->cursor_cache->{$cache_key};
            }
        }

        print "DEBUG: Creating new cursor thumbnail for $cursor_type from $cursor_file (size: $target_size)\n";
        # Create new cursor thumbnail
        my $pixbuf = $self->_create_cursor_thumbnail($cursor_file);

        if ($pixbuf) {
            print "DEBUG: Successfully created cursor thumbnail\n";
            # Cache in memory
            $self->cursor_cache->{$cache_key} = $pixbuf;

            # Save to disk cache
            eval {
                # Ensure cache directory exists
                my $cache_dir = $cache_file;
                $cache_dir =~ s/\/[^\/]+$//;
                unless (-d $cache_dir) {
                    system("mkdir -p '$cache_dir'");
                }

                $pixbuf->savev($cache_file, 'png', [], []);
                print "DEBUG: Saved cursor to cache: $cache_file\n";
            };
            if ($@) {
                print "Warning: Could not save cursor to cache: $@\n";
            }
        } else {
            print "DEBUG: Failed to create cursor thumbnail for $cursor_file\n";
        }

        return $pixbuf;
    }

    sub _create_cursor_thumbnail {
        my ($self, $cursor_file) = @_;

        return $self->_try_c_extractor_pixbuf($cursor_file);
    }

    sub _find_cursor_file {
        my ($self, $cursors_path, $cursor_type) = @_;

        my $primary_file = "$cursors_path/" . $cursor_type->{name};
        return $primary_file if -f $primary_file;

        foreach my $alias (@{$cursor_type->{aliases}}) {
            my $alias_file = "$cursors_path/$alias";
            return $alias_file if -f $alias_file;
        }

        return undef;
    }

    sub _extract_cursor_pixbuf {
        my ($self, $cursor_file) = @_;

        # This method is now just a wrapper for the cached version
        # Extract theme name and cursor type from the file path for caching
        my $theme_name = 'unknown';
        my $cursor_type = 'unknown';

        if ($cursor_file =~ m{/([^/]+)/cursors/([^/]+)$}) {
            $theme_name = $1;
            $cursor_type = $2;
        }

        return $self->_extract_cursor_pixbuf_cached($cursor_file, $theme_name, $cursor_type);
    }

    sub _manage_cursor_cache {
        my $self = shift;

        my $cache = $self->cursor_cache;
        my $max_cache_items = 500;  # Increased from 200 to 500 to be less aggressive

        my $current_cache_size = keys %$cache;

        if ($current_cache_size > $max_cache_items) {
            # Remove oldest entries (simple FIFO, could be improved with LRU)
            my @keys = keys %$cache;
            my $excess_items = $current_cache_size - $max_cache_items;
            my $to_remove = int($excess_items / 4);  # Remove only 1/4 of excess, not all

            # Ensure we remove at least 1 item if there's excess
            $to_remove = 1 if $to_remove < 1 && $excess_items > 0;

            # Only run loop if there are actually items to remove
            if ($to_remove > 0) {
                for my $i (0..$to_remove-1) {
                    delete $cache->{$keys[$i]};
                }

                my $new_cache_size = keys %$cache;
                print "Trimmed cursor cache: removed $to_remove items (cache size: $new_cache_size)\n";
            }
        }
    }

    sub _read_xcursor_pixbuf {
        my ($self, $cursor_file) = @_;

        return $self->_try_c_extractor_pixbuf($cursor_file);
    }

    sub _try_c_extractor_pixbuf {
        my ($self, $cursor_file) = @_;

        my $extractor_path;
        if (-x "./xcursor_extractor") {
            $extractor_path = "./xcursor_extractor";
        } elsif (system("which xcursor_extractor ") == 0) {
            $extractor_path = "xcursor_extractor";
        } else {
            print "Warning: xcursor_extractor not found. Using fallback icon.\n";
            return undef;
        }

        my $pid = $$;
        my $timestamp = time();
        my $random = int(rand(10000));
        my $temp_dir = "/tmp/xcursor_extract_${pid}_${timestamp}_${random}";
        mkdir($temp_dir) or return undef;

        my $pixbuf_result;

        eval {
            my $result = system("$extractor_path '$cursor_file' '$temp_dir' >/dev/null 2>&1");

            if ($result == 0) {
                opendir(my $dh, $temp_dir) or die "Cannot read temp dir: $!";
                my @png_files = grep { /^frame_\d+\.png$/ } readdir($dh);
                closedir($dh);

                if (@png_files > 0) {
                    @png_files = sort {
                        my ($a_num) = $a =~ /frame_(\d+)\.png/;
                        my ($b_num) = $b =~ /frame_(\d+)\.png/;
                        $a_num <=> $b_num;
                    } @png_files;

                    # Find the largest frame by checking actual image dimensions
                    my $best_frame;
                    my $largest_size = 0;

                    foreach my $png_file (@png_files) {
                        my $frame_path = "$temp_dir/$png_file";
                        if (-f $frame_path) {
                            eval {
                                my $test_pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($frame_path);
                                if ($test_pixbuf) {
                                    my $frame_width = $test_pixbuf->get_width();
                                    my $frame_height = $test_pixbuf->get_height();
                                    my $frame_size = $frame_width > $frame_height ? $frame_width : $frame_height;

                                    if ($frame_size > $largest_size) {
                                        $largest_size = $frame_size;
                                        $best_frame = $frame_path;
                                    }
                                }
                            };
                        }
                    }

                    # Use the largest frame found, or fall back to first frame
                    my $selected_frame = $best_frame || "$temp_dir/" . $png_files[0];

                    if (-f $selected_frame) {
                        my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($selected_frame);

                        if ($pixbuf) {
                            my $original_width = $pixbuf->get_width();
                            my $original_height = $pixbuf->get_height();

                            # Use the dynamic cursor preview size
                            my $target_size = $self->cursor_preview_size;

                            # Only scale down if larger than target, never scale up
                            if ($original_width > $target_size || $original_height > $target_size) {
                                my $scale_factor = $target_size / ($original_width > $original_height ? $original_width : $original_height);
                                my $new_width = int($original_width * $scale_factor);
                                my $new_height = int($original_height * $scale_factor);

                                # Use hyper interpolation for high-quality downscaling
                                $pixbuf_result = $pixbuf->scale_simple($new_width, $new_height, 'hyper');
                            } else {
                                # Use original size if already small enough
                                $pixbuf_result = $pixbuf;
                            }
                        }
                    }
                }
            }
        };

        if ($@) {
            print "Error extracting cursor: $@\n";
        }

        if (-d $temp_dir) {
            system("rm -rf '$temp_dir'");
        }

        return $pixbuf_result;
    }


    sub _draw_cursor_grid {
        my ($self, $cr, $cursor_pixbufs, $panel_width, $panel_height) = @_;

        return unless @$cursor_pixbufs > 0;

        # Grid configuration - 6 columns to match the original design
        my $cols = 6;
        my $rows = int((scalar(@$cursor_pixbufs) + $cols - 1) / $cols); # Calculate needed rows

        my $cell_width = int($panel_width / $cols);
        my $cell_height = int($panel_height / $rows);

        my $cursor_index = 0;

        for my $row (0 .. $rows - 1) {
            for my $col (0 .. $cols - 1) {
                last if $cursor_index >= @$cursor_pixbufs;

                my $cursor_data = $cursor_pixbufs->[$cursor_index];
                my $pixbuf = $cursor_data->{pixbuf};

                if ($pixbuf) {
                    # Calculate cell center
                    my $cell_x = $col * $cell_width;
                    my $cell_y = $row * $cell_height;
                    my $center_x = $cell_x + int($cell_width / 2);
                    my $center_y = $cell_y + int($cell_height / 2);

                    # Draw cursor centered in cell
                    my $cursor_width = $pixbuf->get_width();
                    my $cursor_height = $pixbuf->get_height();
                    my $draw_x = $center_x - int($cursor_width / 2);
                    my $draw_y = $center_y - int($cursor_height / 2);

                    $cr->set_antialias('none');
                    Gtk3::Gdk::cairo_set_source_pixbuf($cr, $pixbuf, $draw_x, $draw_y);
                    $cr->paint();
                }

                $cursor_index++;
            }
        }
    }

    sub _draw_rounded_rect {
        my ($self, $cr, $x, $y, $width, $height, $radius) = @_;

        # Start from top-left, going clockwise
        $cr->move_to($x + $radius, $y);
        $cr->line_to($x + $width - $radius, $y);
        $cr->arc($x + $width - $radius, $y + $radius, $radius, -3.14159/2, 0);
        $cr->line_to($x + $width, $y + $height - $radius);
        $cr->arc($x + $width - $radius, $y + $height - $radius, $radius, 0, 3.14159/2);
        $cr->line_to($x + $radius, $y + $height);
        $cr->arc($x + $radius, $y + $height - $radius, $radius, 3.14159/2, 3.14159);
        $cr->line_to($x, $y + $radius);
        $cr->arc($x + $radius, $y + $radius, $radius, 3.14159, -3.14159/2);
        $cr->close_path();
    }

    sub _add_cursor_directory {
        my $self = shift;

        my $dialog = Gtk3::FileChooserDialog->new(
            'Select Cursor Theme Directory',
            $self->window,
            'select-folder',
            'gtk-cancel' => 'cancel',
            'gtk-open' => 'accept'
        );

        if ($dialog->run() eq 'accept') {
            my $folder = $dialog->get_filename();
            my $name = $folder;
            $name =~ s/.*\///;

            # Check if directory already exists in UI
            my $already_exists = 0;
            foreach my $existing_path (values %{$self->directory_paths}) {
                if ($existing_path eq $folder) {
                    $already_exists = 1;
                    last;
                }
            }

            # Also check config for consistency
            if (!$already_exists && $self->config->{custom_directories}) {
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
                # Show message to user
                my $msg_dialog = Gtk3::MessageDialog->new(
                    $self->window,
                    'modal',
                    'info',
                    'ok',
                    'This directory is already in the list.'
                );
                $msg_dialog->run();
                $msg_dialog->destroy();
            }
        }

        $dialog->destroy();
    }

    sub _remove_cursor_directory {
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


    sub _set_cursor_theme {
        my ($self, $child) = @_;

        my $container = $child->get_child();
        my $theme_info = $self->theme_paths->{$container + 0};

        return unless $theme_info && -d $theme_info->{path};

        my $theme_name = $theme_info->{name};
        my $theme_path = $theme_info->{path};

        print "Setting cursor theme: $theme_name from path: $theme_path\n";

        # ONLY the directories that gsettings actually recognizes for cursor themes
        my @working_cursor_dirs = (
            $ENV{HOME} . '/.icons',
            '/usr/share/icons',
            '/usr/local/share/icons'
        );

        my $is_in_working_location = 0;
        foreach my $working_dir (@working_cursor_dirs) {
            if ($theme_path =~ /^\Q$working_dir\E/) {
                $is_in_working_location = 1;
                last;
            }
        }

        if ($is_in_working_location) {
            # Theme is already in a location that gsettings recognizes
            print "Theme is in working location, applying directly\n";
            my $result = system("gsettings set org.cinnamon.desktop.interface cursor-theme '$theme_name'");

            if ($result == 0) {
                print "Successfully applied cursor theme: $theme_name\n";
            } else {
                print "Failed to apply cursor theme: $theme_name\n";
                my $error_dialog = Gtk3::MessageDialog->new(
                    $self->window,
                    'modal',
                    'error',
                    'ok',
                    "Failed to apply cursor theme '$theme_info->{display_name}'."
                );
                $error_dialog->run();
                $error_dialog->destroy();
            }
        } else {
            # Theme is in custom location, create symlink in ~/.icons to make it work
            print "Theme is in custom location, creating symlink in ~/.icons\n";

            my $target_base = $ENV{HOME} . '/.icons';
            my $target_path = "$target_base/$theme_name";

            # Create ~/.icons directory if needed
            unless (-d $target_base) {
                system("mkdir -p '$target_base'");
                print "Created ~/.icons directory\n";
            }

            # Remove existing symlink/directory if it exists
            if (-l $target_path) {
                unlink($target_path);
                print "Removed existing symlink: $target_path\n";
            } elsif (-d $target_path) {
                system("rm -rf '$target_path'");
                print "Removed existing directory: $target_path\n";
            }

            # Create symlink
            my $symlink_result = system("ln -s '$theme_path' '$target_path'");

            if ($symlink_result == 0 && -l $target_path) {
                print "Successfully created symlink: $target_path -> $theme_path\n";

                # Now apply the theme
                my $apply_result = system("gsettings set org.cinnamon.desktop.interface cursor-theme '$theme_name'");

                if ($apply_result == 0) {
                    print "Successfully applied cursor theme: $theme_name\n";
                } else {
                    print "Failed to apply cursor theme after creating symlink: $theme_name\n";
                    my $error_dialog = Gtk3::MessageDialog->new(
                        $self->window,
                        'modal',
                        'error',
                        'ok',
                        "Created symlink but failed to apply cursor theme '$theme_info->{display_name}'.\n\n" .
                        "The theme may be invalid or corrupted."
                    );
                    $error_dialog->run();
                    $error_dialog->destroy();
                }
            } else {
                print "Failed to create symlink for theme: $theme_name\n";
                my $error_dialog = Gtk3::MessageDialog->new(
                    $self->window,
                    'modal',
                    'error',
                    'ok',
                    "Failed to create symlink for cursor theme '$theme_info->{display_name}'.\n\n" .
                    "Please check permissions for: ~/.icons/\n" .
                    "Source: $theme_path\n" .
                    "Target: $target_path"
                );
                $error_dialog->run();
                $error_dialog->destroy();
            }
        }
    }

    sub _update_environment_file {
        my ($self, $file_path, $xcursor_line) = @_;

        # Read existing file content
        my @lines;
        if (-f $file_path) {
            open my $fh, '<', $file_path or return;
            @lines = <$fh>;
            close $fh;
            chomp @lines;
        }

        # Check if XCURSOR_PATH is already set in the file
        my $xcursor_found = 0;
        for my $i (0..$#lines) {
            if ($lines[$i] =~ /^\s*export\s+XCURSOR_PATH=/) {
                # Replace existing XCURSOR_PATH line
                $lines[$i] = $xcursor_line;
                $xcursor_found = 1;
                last;
            }
        }

        # If XCURSOR_PATH wasn't found, add it
        if (!$xcursor_found) {
            push @lines, $xcursor_line;
        }

        # Write back to file
        eval {
            open my $fh, '>', $file_path or die "Cannot write to $file_path: $!";
            foreach my $line (@lines) {
                print $fh "$line\n";
            }
            close $fh;
            print "Updated $file_path with XCURSOR_PATH\n";
        };
        if ($@) {
            print "Warning: Could not update $file_path: $@\n";
        }
    }

    sub _install_cursor_theme_to_user_location {
        my ($self, $theme_info) = @_;

        my $theme_name = $theme_info->{name};
        my $source_path = $theme_info->{path};

        # Try user locations in order of preference
        # We focus on locations that gsettings will recognize for cursor themes
        my @target_bases = (
            $ENV{HOME} . '/.local/share/icons',  # Primary modern location
            $ENV{HOME} . '/.icons'               # Fallback legacy location
        );

        foreach my $target_base (@target_bases) {
            my $target_path = "$target_base/$theme_name";

            print "Attempting to install theme to: $target_path\n";

            # Create target directory if it doesn't exist
            unless (-d $target_base) {
                print "Creating directory: $target_base\n";
                system("mkdir -p '$target_base'");
                unless (-d $target_base) {
                    print "Failed to create directory: $target_base\n";
                    next; # Try next location
                }
            }

            # Check if target already exists and points to the same source
            if (-l $target_path) {
                my $existing_target = readlink($target_path);
                if ($existing_target && $existing_target eq $source_path) {
                    print "Symlink already exists and points to correct source: $target_path\n";
                    return 1; # Success, already installed correctly
                } else {
                    print "Removing old symlink: $target_path\n";
                    unlink($target_path);
                }
            } elsif (-d $target_path) {
                # Check if it's the same directory (avoid copying over itself)
                if (File::Spec->rel2abs($target_path) eq File::Spec->rel2abs($source_path)) {
                    print "Theme is already in target location: $target_path\n";
                    return 1; # Success, already in place
                } else {
                    print "Directory already exists, removing: $target_path\n";
                    system("rm -rf '$target_path'");
                }
            }

            # Try to create symlink first (preserves space and keeps original)
            my $symlink_result = system("ln -sf '$source_path' '$target_path' 2>/dev/null");

            if ($symlink_result == 0 && -l $target_path) {
                print "Successfully created symlink: $target_path -> $source_path\n";
                return 1; # Success
            }

            print "Symlink failed, trying copy instead\n";

            # If symlink fails, try copying
            my $copy_result = system("cp -r '$source_path' '$target_path' 2>/dev/null");

            if ($copy_result == 0 && -d $target_path) {
                print "Successfully copied theme to: $target_path\n";
                return 1; # Success
            }

            print "Failed to install to $target_path, trying next location\n";
        }

        print "Failed to install theme to any user location\n";
        return 0; # Failure
    }

    sub _load_config {
        my $self = shift;

        my $config_file = $self->_get_config_file_path();
        my $config = {
            thumbnail_size => 200,
            cursor_preview_size => 40,  # Add default cursor preview size
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

                    # Validate cursor_preview_size range
                    if (!$config->{cursor_preview_size} || $config->{cursor_preview_size} < 24 || $config->{cursor_preview_size} > 64) {
                        print "Invalid cursor preview size in config, using default\n";
                        $config->{cursor_preview_size} = 40;
                    }

                    # Ensure custom_directories is an array ref
                    if (!ref($config->{custom_directories}) || ref($config->{custom_directories}) ne 'ARRAY') {
                        $config->{custom_directories} = [];
                    }

                    print "Loaded configuration from $config_file\n";
                    print "  Thumbnail size: " . $config->{thumbnail_size} . "\n";
                    print "  Cursor preview size: " . $config->{cursor_preview_size} . "\n";
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
        print "Cursor Themes Manager started\n";
        Gtk3::main();
    }
}

# Main execution
if (!caller) {
    my $app = CursorThemesManager->new();
    $app->run();
}

1;
