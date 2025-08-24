#!/usr/bin/perl
use strict;
use warnings;
use utf8;

# Cinnamon Theme Manager - Desktop Theme Preview Application
# A dedicated Cinnamon theme management application for Linux Mint
# Written in Perl with GTK3

use Gtk3 -init;
use Glib 'TRUE', 'FALSE';
use File::Spec;
use JSON qw(encode_json decode_json);
use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use File::Basename;
use File::HomeDir;
use Cairo;

$SIG{__WARN__} = sub {
    my $warning = shift;
    return if $warning =~ /Theme parsing error/;
    warn $warning;
};

# Main application class
package CinnamonThemeManager {
    use Moo;
    use File::HomeDir;

    has 'window' => (is => 'rw');
    has 'directory_list' => (is => 'rw');
    has 'themes_grid' => (is => 'rw');
    has 'content_switcher' => (is => 'rw');
    has 'themes_mode' => (is => 'rw');
    has 'settings_mode' => (is => 'rw');
    has 'zoom_level' => (is => 'rw', default => sub { 400 });
    has 'directory_paths' => (is => 'rw', default => sub { {} });
    has 'theme_paths' => (is => 'rw', default => sub { {} });
    has 'theme_widgets' => (is => 'rw', default => sub { {} });
    has 'loading_spinner' => (is => 'rw');
    has 'loading_label' => (is => 'rw');
    has 'loading_box' => (is => 'rw');
    has 'current_directory' => (is => 'rw');
    has 'cached_theme_lists' => (is => 'rw', default => sub { {} });
    has 'config' => (is => 'rw');
    has 'last_selected_directory_path' => (is => 'rw');
    has 'current_theme' => (is => 'rw');

    sub BUILD {
        my $self = shift;
        $self->_initialize_configuration();
        $self->_setup_ui();
        $self->_populate_theme_directories();
        $self->_restore_last_selected_directory();
        $self->_detect_current_theme();
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
        $self->zoom_level($config->{preview_size} || 400);
        $self->last_selected_directory_path($config->{last_selected_directory});

        print "Configuration initialized\n";
        print "  Preview size: " . $self->zoom_level . "\n";
        print "  Custom directories: " . @{$config->{custom_directories} || []} . "\n";
        print "  Last directory: " . ($self->last_selected_directory_path || 'none') . "\n";
    }

    sub _initialize_directory_structure {
        my $self = shift;

        # Create main application directory for Cinnamon Theme Manager
        my $app_dir = $ENV{HOME} . '/.local/share/cinnamon-theme-manager';
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

        # Create previews subdirectory
        my $previews_dir = "$app_dir/previews";
        unless (-d $previews_dir) {
            system("mkdir -p '$previews_dir'");
            print "Created previews directory: $previews_dir\n";
        }

        print "Directory structure initialized for Cinnamon Theme Manager\n";
    }

    sub _setup_ui {
        my $self = shift;

        # Create main window
        my $window = Gtk3::Window->new('toplevel');
        $window->set_title('Cinnamon Theme Manager');
        $window->set_default_size(1200, 900);
        $window->set_position('center');
        $window->set_icon_name('preferences-desktop-theme');

        # Create header bar
        my $header = Gtk3::HeaderBar->new();
        $header->set_show_close_button(1);
        $header->set_title('Cinnamon Theme Manager');
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

        # Right panel - Theme display and settings
        my $right_panel = Gtk3::Frame->new();
        $right_panel->set_shadow_type('in');

        my $right_container = Gtk3::Box->new('vertical', 0);

        # Top buttons (Themes/Settings)
        my $mode_buttons = Gtk3::Box->new('horizontal', 0);
        $mode_buttons->set_margin_left(12);
        $mode_buttons->set_margin_right(12);
        $mode_buttons->set_margin_top(12);
        $mode_buttons->set_margin_bottom(6);

        my ($themes_mode, $settings_mode) = $self->_create_mode_buttons();

        $mode_buttons->pack_start($themes_mode, 1, 1, 0);
        $mode_buttons->pack_start($settings_mode, 1, 1, 0);

        $right_container->pack_start($mode_buttons, 0, 0, 0);

        # Content area (themes or settings)
        my $content_switcher = Gtk3::Stack->new();
        $content_switcher->set_transition_type('slide-left-right');

        # Themes content
        my $themes_view = Gtk3::ScrolledWindow->new();
        $themes_view->set_policy('automatic', 'automatic');
        $themes_view->set_vexpand(1);

        my $themes_grid = Gtk3::FlowBox->new();
        $themes_grid->set_valign('start');
        $themes_grid->set_max_children_per_line(6);
        $themes_grid->set_min_children_per_line(2);
        $themes_grid->set_selection_mode('single');
        $themes_grid->set_margin_left(12);
        $themes_grid->set_margin_right(12);
        $themes_grid->set_margin_top(12);
        $themes_grid->set_margin_bottom(12);
        $themes_grid->set_row_spacing(12);
        $themes_grid->set_column_spacing(12);

        $themes_view->add($themes_grid);
        $content_switcher->add_named($themes_view, 'themes');

        # Settings content
        my $settings_view = Gtk3::ScrolledWindow->new();
        $settings_view->set_policy('automatic', 'automatic');
        my $settings_content = $self->_create_theme_settings();
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
        $self->themes_grid($themes_grid);
        $self->content_switcher($content_switcher);
        $self->themes_mode($themes_mode);
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
        $self->_connect_mode_button_signals($self->themes_mode, $self->settings_mode, $self->content_switcher);

        $self->directory_list->signal_connect('row-selected' => sub {
            my ($widget, $row) = @_;
            return unless $row;

            # Save the selected directory to config
            my $dir_path = $self->directory_paths->{$row + 0};
            if ($dir_path) {
                $self->config->{last_selected_directory} = $dir_path;
                $self->_save_config($self->config);
            }

            $self->_load_themes_from_directory_async($row);
        });

        $add_dir_button->signal_connect('clicked' => sub {
            $self->_add_theme_directory();
        });

        $remove_dir_button->signal_connect('clicked' => sub {
            $self->_remove_theme_directory();
        });

        $zoom_in->signal_connect('clicked' => sub {
            my $new_zoom = ($self->zoom_level < 600) ? $self->zoom_level + 50 : 600;
            $self->zoom_level($new_zoom);
            $self->_update_theme_zoom_async();
            # Save zoom level to config
            $self->config->{preview_size} = $self->zoom_level;
            $self->_save_config($self->config);
        });

        $zoom_out->signal_connect('clicked' => sub {
            my $new_zoom = ($self->zoom_level > 200) ? $self->zoom_level - 50 : 200;
            $self->zoom_level($new_zoom);
            $self->_update_theme_zoom_async();
            # Save zoom level to config
            $self->config->{preview_size} = $self->zoom_level;
            $self->_save_config($self->config);
        });

        $self->themes_grid->signal_connect('child-activated' => sub {
            my ($widget, $child) = @_;
            $self->_set_cinnamon_theme($child);
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

    sub _create_theme_settings {
        my $self = shift;

        my $settings_box = Gtk3::Box->new('vertical', 12);
        $settings_box->set_margin_left(20);
        $settings_box->set_margin_right(20);
        $settings_box->set_margin_top(20);
        $settings_box->set_margin_bottom(20);

        # Current Theme Information section
        my $current_frame = Gtk3::Frame->new();
        $current_frame->set_label('Current Theme Status');
        $current_frame->set_label_align(0.02, 0.5);

        my $current_container = Gtk3::Box->new('vertical', 12);
        $current_container->set_margin_left(12);
        $current_container->set_margin_right(12);
        $current_container->set_margin_top(12);
        $current_container->set_margin_bottom(12);

        my $current_label = Gtk3::Label->new('Detecting current theme...');
        $current_label->set_halign('start');
        $current_label->set_markup('<b>Cinnamon Theme:</b> Detecting...');
        $current_container->pack_start($current_label, 0, 0, 0);

        my $gtk_theme_label = Gtk3::Label->new('Detecting GTK theme...');
        $gtk_theme_label->set_halign('start');
        $gtk_theme_label->set_markup('<b>GTK Theme:</b> Detecting...');
        $current_container->pack_start($gtk_theme_label, 0, 0, 0);

        my $icon_theme_label = Gtk3::Label->new('Detecting icon theme...');
        $icon_theme_label->set_halign('start');
        $icon_theme_label->set_markup('<b>Icon Theme:</b> Detecting...');
        $current_container->pack_start($icon_theme_label, 0, 0, 0);

        my $button_box = Gtk3::Box->new('horizontal', 6);

        my $refresh_button = Gtk3::Button->new_with_label('Refresh Theme Status');
        $refresh_button->set_halign('start');
        $refresh_button->signal_connect('clicked' => sub {
            $self->_detect_current_theme();
            my $theme = $self->current_theme || 'Unknown';
            $current_label->set_markup("<b>Cinnamon Theme:</b> $theme");

            my $gtk_theme = `gsettings get org.cinnamon.desktop.interface gtk-theme 2>/dev/null`;
            chomp $gtk_theme if $gtk_theme;
            $gtk_theme =~ s/^'(.*)'$/$1/ if $gtk_theme;
            $gtk_theme_label->set_markup("<b>GTK Theme:</b> " . ($gtk_theme || 'Unknown'));

            my $icon_theme = `gsettings get org.cinnamon.desktop.interface icon-theme 2>/dev/null`;
            chomp $icon_theme if $icon_theme;
            $icon_theme =~ s/^'(.*)'$/$1/ if $icon_theme;
            $icon_theme_label->set_markup("<b>Icon Theme:</b> " . ($icon_theme || 'Unknown'));
        });
        $button_box->pack_start($refresh_button, 0, 0, 0);

        $current_container->pack_start($button_box, 0, 0, 0);

        $current_frame->add($current_container);
        $settings_box->pack_start($current_frame, 0, 0, 0);

        # Application Settings section
        my $app_frame = Gtk3::Frame->new();
        $app_frame->set_label('Application Settings');
        $app_frame->set_label_align(0.02, 0.5);

        my $app_container = Gtk3::Box->new('vertical', 12);
        $app_container->set_margin_left(12);
        $app_container->set_margin_right(12);
        $app_container->set_margin_top(12);
        $app_container->set_margin_bottom(12);

        # Reload all thumbnails button
        my $reload_button = Gtk3::Button->new_with_label('Reload All Thumbnails');
        $reload_button->set_halign('start');
        $reload_button->signal_connect('clicked' => sub {
            $self->_regenerate_all_previews();
        });
        $app_container->pack_start($reload_button, 0, 0, 0);

        # Information label
        my $info_label = Gtk3::Label->new();
        $info_label->set_halign('start');
        $info_label->set_markup('<small>This application displays Cinnamon themes that have thumbnail.png files.\nThemes without thumbnails are automatically filtered out.</small>');
        $info_label->set_line_wrap(1);
        $app_container->pack_start($info_label, 0, 0, 0);

        $app_frame->add($app_container);
        $settings_box->pack_start($app_frame, 0, 0, 0);

        # Initialize current theme display
        Glib::Timeout->add(500, sub {
            $self->_detect_current_theme();
            my $theme = $self->current_theme || 'Unknown';
            $current_label->set_markup("<b>Cinnamon Theme:</b> $theme");

            my $gtk_theme = `gsettings get org.cinnamon.desktop.interface gtk-theme 2>/dev/null`;
            chomp $gtk_theme if $gtk_theme;
            $gtk_theme =~ s/^'(.*)'$/$1/ if $gtk_theme;
            $gtk_theme_label->set_markup("<b>GTK Theme:</b> " . ($gtk_theme || 'Unknown'));

            my $icon_theme = `gsettings get org.cinnamon.desktop.interface icon-theme 2>/dev/null`;
            chomp $icon_theme if $icon_theme;
            $icon_theme =~ s/^'(.*)'$/$1/ if $icon_theme;
            $icon_theme_label->set_markup("<b>Icon Theme:</b> " . ($icon_theme || 'Unknown'));

            return 0; # Don't repeat
        });

        return $settings_box;
    }

    sub _create_directory_buttons {
        my $self = shift;

        my $add_button = Gtk3::Button->new();
        $add_button->set_relief('none');
        $add_button->set_size_request(32, 32);
        $add_button->set_tooltip_text('Add theme directory');

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
        $zoom_out->set_tooltip_text('Decrease theme preview size');

        my $zoom_in = Gtk3::Button->new();
        $zoom_in->set_relief('none');
        $zoom_in->set_size_request(32, 32);
        $zoom_in->set_tooltip_text('Increase theme preview size');

        # Use system icons for zoom
        my $zoom_out_icon = Gtk3::Image->new_from_icon_name('zoom-out-symbolic', 1);
        $zoom_out->add($zoom_out_icon);

        my $zoom_in_icon = Gtk3::Image->new_from_icon_name('zoom-in-symbolic', 1);
        $zoom_in->add($zoom_in_icon);

        return ($zoom_out, $zoom_in);
    }

    sub _create_mode_buttons {
        my $self = shift;

        my $themes_mode = Gtk3::ToggleButton->new_with_label('Themes');
        my $settings_mode = Gtk3::ToggleButton->new_with_label('Settings');

        $themes_mode->set_active(1); # Active by default

        return ($themes_mode, $settings_mode);
    }

    sub _connect_mode_button_signals {
        my ($self, $themes_mode, $settings_mode, $content_switcher) = @_;

        # Handle clicks for themes mode button
        $themes_mode->signal_connect('toggled' => sub {
            my $widget = shift;
            if ($widget->get_active()) {
                $settings_mode->set_active(0);
                $content_switcher->set_visible_child_name('themes');
            }
        });

        # Handle clicks for settings mode button
        $settings_mode->signal_connect('toggled' => sub {
            my $widget = shift;
            if ($widget->get_active()) {
                $themes_mode->set_active(0);
                $content_switcher->set_visible_child_name('settings');
            }
        });
    }

    sub _populate_theme_directories {
        my $self = shift;

        my $home = File::HomeDir->my_home;

        # Default Cinnamon theme directories
        my @default_dirs = (
            { name => 'System Themes', path => '/usr/share/themes' },
            { name => 'User Themes',   path => "$home/.themes" },
            { name => 'Local Themes',  path => "$home/.local/share/themes" },
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

        print "Populated theme directories\n";
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
            # The row-selected signal will automatically trigger _load_themes_from_directory_async
        }
    }

   sub _load_themes_from_directory_async {
        my ($self, $row) = @_;

        return unless $row;

        my $dir_path = $self->directory_paths->{$row + 0};
        return unless $dir_path && -d $dir_path;

        # Guard against duplicate loading
        my $current_time = time();
        if ($self->{last_loaded_directory} &&
            $self->{last_loaded_directory} eq $dir_path &&
            $self->{last_load_time} &&
            ($current_time - $self->{last_load_time}) < 2) {
            print "DEBUG: Preventing duplicate load of $dir_path\n";
            return;
        }

        $self->{last_loaded_directory} = $dir_path;
        $self->{last_load_time} = $current_time;

        print "DEBUG: Loading Cinnamon themes from directory: $dir_path\n";

        # Show loading indicator
        $self->_show_loading_indicator('Scanning for Cinnamon themes...');

        # Clear existing themes immediately
        my $flowbox = $self->themes_grid;
        foreach my $child ($flowbox->get_children()) {
            $flowbox->remove($child);
        }

        # Clear references
        $self->theme_paths({});
        $self->theme_widgets({});
        $self->current_directory($dir_path);

        # Get or scan themes
        my $themes_ref;
        if (exists $self->cached_theme_lists->{$dir_path}) {
            $themes_ref = $self->cached_theme_lists->{$dir_path};
            print "Using cached theme list for $dir_path (" . @$themes_ref . " themes)\n";
        } else {
            my @themes = $self->_scan_cinnamon_themes($dir_path);
            @themes = sort { lc($a->{name}) cmp lc($b->{name}) } @themes;
            $themes_ref = \@themes;
            $self->cached_theme_lists->{$dir_path} = $themes_ref;
            print "Scanned $dir_path: " . @themes . " Cinnamon themes found\n";
        }

        if (@$themes_ref == 0) {
            $self->_hide_loading_indicator();
            print "No Cinnamon themes found in $dir_path\n";
            return;
        }

        # Start progressive loading with thumbnail loading
        $self->_start_progressive_loading($themes_ref, $dir_path);
    }

    sub _scan_cinnamon_themes {
        my ($self, $base_dir) = @_;

        my @themes = ();

        opendir(my $dh, $base_dir) or return @themes;
        my @subdirs = grep { -d "$base_dir/$_" && $_ !~ /^\./ } readdir($dh);
        closedir($dh);

        foreach my $subdir (@subdirs) {
            my $theme_path = "$base_dir/$subdir";
            my $cinnamon_dir = "$theme_path/cinnamon";

            # Check if this directory contains a Cinnamon theme
            if (-d $cinnamon_dir) {
                my $cinnamon_css = "$cinnamon_dir/cinnamon.css";

                if (-f $cinnamon_css) {
                    # Parse theme information
                    my $theme_info = $self->_parse_cinnamon_theme_info($theme_path, $subdir);

                    # Only include themes that have thumbnails/previews
                    if ($theme_info->{thumbnail_path}) {
                        push @themes, $theme_info;
                        print "DEBUG: Including Cinnamon theme '$subdir' with thumbnail: " . $theme_info->{thumbnail_path} . "\n";
                    } else {
                        print "DEBUG: Skipping Cinnamon theme '$subdir' - no thumbnail found\n";
                    }
                }
            }
        }

        return @themes;
    }

    sub _parse_cinnamon_theme_info {
        my ($self, $theme_path, $theme_name) = @_;

        my $theme_info = {
            name          => $theme_name,
            path          => $theme_path,
            display_name  => $theme_name,
            cinnamon_path => "$theme_path/cinnamon",
        };

        # Look for thumbnail files in priority order
        my @thumbnail_candidates = (
            "$theme_path/cinnamon/thumbnail.png",
            "$theme_path/thumbnail.png",
            "$theme_path/cinnamon/preview.png",
            "$theme_path/preview.png",
            "$theme_path/cinnamon/screenshot.png",
            "$theme_path/screenshot.png",
        );

        foreach my $thumbnail_path (@thumbnail_candidates) {
            if (-f $thumbnail_path && -s $thumbnail_path > 1000) {  # File exists and is not empty
                $theme_info->{thumbnail_path} = $thumbnail_path;
                print "Found thumbnail for $theme_name: $thumbnail_path\n";
                last;
            }
        }

        # Try to read metadata from theme.json
        my $theme_json = "$theme_path/cinnamon/theme.json";
        if (-f $theme_json) {
            eval {
                open my $fh, '<:encoding(UTF-8)', $theme_json;
                my $json_text = do { local $/; <$fh> };
                close $fh;

                if ($json_text) {
                    my $metadata = JSON->new->decode($json_text);
                    $theme_info->{display_name} = $metadata->{name} || $theme_name;
                    $theme_info->{description} = $metadata->{description};
                    $theme_info->{author} = $metadata->{author};
                    $theme_info->{version} = $metadata->{version};
                }
            };
            if ($@) {
                print "Warning: Could not parse theme.json for $theme_name: $@\n";
            }
        }

        # Fallback: try to get name from metadata.json
        my $metadata_json = "$theme_path/metadata.json";
        if (-f $metadata_json && !$theme_info->{description}) {
            eval {
                open my $fh, '<:encoding(UTF-8)', $metadata_json;
                my $json_text = do { local $/; <$fh> };
                close $fh;

                if ($json_text) {
                    my $metadata = JSON->new->decode($json_text);
                    $theme_info->{display_name} = $metadata->{name} || $theme_info->{display_name};
                    $theme_info->{description} = $metadata->{description};
                }
            };
        }

        return $theme_info;
    }

    sub _start_progressive_loading {
        my ($self, $themes_ref, $dir_path) = @_;

        my $total_themes = @$themes_ref;
        my $loaded_widgets = 0;

        print "Starting progressive loading of $total_themes Cinnamon themes\n";

        # Initialize progress tracking
        $self->{preview_progress} = {
            total => $total_themes,
            loaded_widgets => 0,
            completed_previews => 0,
            dir_path => $dir_path
        };

        # Phase 1: Quickly create all theme widgets with placeholders
        $self->_update_loading_progress("Creating theme widgets...", 0);

        my $create_widgets;
        $create_widgets = sub {
            return 0 if $self->current_directory ne $dir_path;  # Directory changed

            my $batch_size = 8;
            my $batch_end = ($loaded_widgets + $batch_size - 1 < $total_themes - 1)
                        ? $loaded_widgets + $batch_size - 1
                        : $total_themes - 1;

            # Create widgets for this batch
            for my $i ($loaded_widgets..$batch_end) {
                my $theme_info = $themes_ref->[$i];

                # Create widget with placeholder preview
                my $theme_widget = $self->_create_theme_widget_with_placeholder($theme_info);
                $self->themes_grid->add($theme_widget);
            }

            $loaded_widgets = $batch_end + 1;
            $self->{preview_progress}->{loaded_widgets} = $loaded_widgets;

            # Update progress
            my $widget_progress = int(($loaded_widgets / $total_themes) * 30);  # 30% for widget creation
            $self->_update_loading_progress("Creating theme widgets...", $widget_progress);

            $self->themes_grid->show_all();

            if ($loaded_widgets < $total_themes) {
                # Continue with next batch
                Glib::Timeout->add(10, $create_widgets);
                return 0;
            } else {
                # Widget creation complete, start thumbnail loading
                print "All widgets created, starting thumbnail loading\n";
                $self->_start_thumbnail_loading($themes_ref);
                return 0;
            }
        };

        # Start widget creation
        Glib::Timeout->add(10, $create_widgets);
    }

    sub _start_thumbnail_loading {
        my ($self, $themes_ref) = @_;

        my $progress = $self->{preview_progress};
        return unless $progress;

        print "Starting sequential thumbnail loading\n";

        my $current_index = 0;
        my $total_themes = @$themes_ref;

        my $load_next;
        $load_next = sub {
            return 0 if $self->current_directory ne $progress->{dir_path};

            if ($current_index >= $total_themes) {
                print "All thumbnail loading completed!\n";
                $self->_hide_loading_indicator();
                delete $self->{preview_progress};
                return 0;  # Stop loading
            }

            my $theme_info = $themes_ref->[$current_index];
            print "Loading thumbnail for: " . $theme_info->{name} . " ($current_index/$total_themes)\n";

            # Find the corresponding widget
            my $widget = $self->_find_theme_widget($theme_info->{name});
            if ($widget) {
                $self->_load_theme_thumbnail($theme_info, $widget);
            }

            $current_index++;

            # Update progress
            my $thumbnail_progress = 30 + int(($current_index / $total_themes) * 70);
            $self->_update_loading_progress(
                "Loading thumbnails... ($current_index/$total_themes)",
                $thumbnail_progress
            );

            # Schedule next thumbnail loading
            Glib::Timeout->add(50, $load_next);
            return 0;
        };

        # Start first thumbnail loading
        Glib::Timeout->add(50, $load_next);
    }

    sub _find_theme_widget {
        my ($self, $theme_name) = @_;

        my $flowbox = $self->themes_grid;
        foreach my $child ($flowbox->get_children()) {
            my $frame = $child->get_child();  # FlowBoxChild -> Frame
            my $theme_info = $self->theme_paths->{$frame + 0};

            if ($theme_info && $theme_info->{name} eq $theme_name) {
                return $frame;
            }
        }

        return undef;
    }

    sub _create_theme_widget_with_placeholder {
        my ($self, $theme_info) = @_;

        print "Creating widget with placeholder for: " . $theme_info->{name} . "\n";

        # Create frame with inset shadow
        my $frame = Gtk3::Frame->new();
        $frame->set_shadow_type('in');

        # Create vertical box container
        my $box = Gtk3::Box->new('vertical', 6);
        $box->set_margin_left(6);
        $box->set_margin_right(6);
        $box->set_margin_top(6);
        $box->set_margin_bottom(6);

        # Create placeholder preview
        my $placeholder = $self->_create_simple_placeholder($theme_info);
        $placeholder->set_size_request($self->zoom_level, int($self->zoom_level * 0.75));

        $box->pack_start($placeholder, 1, 1, 0);

        # Create label
        my $theme_name = $theme_info->{display_name} || $theme_info->{name};
        my $label = Gtk3::Label->new($theme_name);
        $label->set_ellipsize('middle');
        $label->set_max_width_chars(15);

        $box->pack_start($label, 0, 0, 0);
        $frame->add($box);

        # Store references
        $self->theme_paths->{$frame + 0} = $theme_info;
        $self->theme_widgets->{$frame + 0} = $placeholder;

        return $frame;
    }

    sub _create_simple_placeholder {
        my ($self, $theme_info) = @_;

        # Create a simple placeholder using system theme colors
        my $width = $self->zoom_level;
        my $height = int($self->zoom_level * 0.75);

        # Create a drawing area that uses system theme colors
        my $drawing_area = Gtk3::DrawingArea->new();
        $drawing_area->set_size_request($width, $height);

        # Connect draw signal to render placeholder content
        $drawing_area->signal_connect('draw' => sub {
            my ($widget, $cr) = @_;

            # Get the widget's style context to use system colors
            my $style_context = $widget->get_style_context();
            my $bg_color = $style_context->get_background_color('normal');
            my $fg_color = $style_context->get_color('normal');

            # Fill with system background color
            $cr->set_source_rgba($bg_color->red, $bg_color->green, $bg_color->blue, $bg_color->alpha);
            $cr->paint();

            # Add a subtle border using system colors
            my $border_color = $style_context->get_border_color('normal');
            $cr->set_source_rgba($border_color->red, $border_color->green, $border_color->blue, 0.3);
            $cr->set_line_width(1);
            $cr->rectangle(0.5, 0.5, $width - 1, $height - 1);
            $cr->stroke();

            # Draw loading text using system foreground color
            $cr->set_source_rgba($fg_color->red, $fg_color->green, $fg_color->blue, $fg_color->alpha);
            $cr->select_font_face("Sans", 'normal', 'normal');
            $cr->set_font_size(12);

            my $loading_text = "Loading thumbnail...";
            my $text_extents = $cr->text_extents($loading_text);
            $cr->move_to(($width - $text_extents->{width})/2, $height/2 - 10);
            $cr->show_text($loading_text);

            # Draw theme name
            $cr->set_font_size(10);
            my $name_text = $theme_info->{display_name} || $theme_info->{name};
            # Truncate long names
            if (length($name_text) > 20) {
                $name_text = substr($name_text, 0, 17) . "...";
            }
            my $name_extents = $cr->text_extents($name_text);
            $cr->move_to(($width - $name_extents->{width})/2, $height/2 + 15);
            $cr->show_text($name_text);

            # Draw a simple loading indicator (rotating circle)
            my $center_x = $width / 2;
            my $center_y = $height/2 - 30;
            my $radius = 8;

            # Simple spinner dots
            for my $i (0..7) {
                my $angle = ($i * 3.14159 * 2 / 8);
                my $alpha = 0.2 + (0.8 * ($i / 7));
                $cr->set_source_rgba($fg_color->red, $fg_color->green, $fg_color->blue, $alpha);
                my $dot_x = $center_x + cos($angle) * $radius;
                my $dot_y = $center_y + sin($angle) * $radius;
                $cr->arc($dot_x, $dot_y, 2, 0, 2 * 3.14159);
                $cr->fill();
            }

            return 0;
        });

        return $drawing_area;
    }

    sub _load_theme_thumbnail {
        my ($self, $theme_info, $widget_container) = @_;

        # Since we filtered themes, all themes should have thumbnails
        my $thumbnail_path = $theme_info->{thumbnail_path};

        # Double-check thumbnail file exists and is not empty
        unless (-f $thumbnail_path && -s $thumbnail_path > 1000) {
            print "ERROR: Thumbnail file is missing or corrupted for " . $theme_info->{name} . "\n";
            return 0;
        }

        print "Loading thumbnail from: $thumbnail_path\n";

        # Load and scale the thumbnail
        my $thumbnail_image = eval {
            my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($thumbnail_path);

            if ($pixbuf) {
                # Scale to fit the current zoom level while maintaining aspect ratio
                my $orig_width = $pixbuf->get_width();
                my $orig_height = $pixbuf->get_height();
                my $target_width = $self->zoom_level;
                my $target_height = int($self->zoom_level * 0.75);

                # Calculate scaling to fit within target dimensions
                my $scale_x = $target_width / $orig_width;
                my $scale_y = $target_height / $orig_height;
                my $scale = ($scale_x < $scale_y) ? $scale_x : $scale_y;

                my $new_width = int($orig_width * $scale);
                my $new_height = int($orig_height * $scale);

                my $scaled_pixbuf = $pixbuf->scale_simple($new_width, $new_height, 'bilinear');

                return Gtk3::Image->new_from_pixbuf($scaled_pixbuf);
            }
            return undef;
        };

        if ($@ || !$thumbnail_image) {
            print "ERROR: Failed to load thumbnail for " . $theme_info->{name} . ": $@\n";
            return 0;
        }

        # Update the widget with the thumbnail
        $self->_update_widget_preview($widget_container, $thumbnail_image);
        return 1;
    }

    sub _update_widget_preview {
        my ($self, $widget_container, $new_preview) = @_;

        return unless $new_preview;

        # Get the box container from the frame
        my $box = $widget_container->get_child();
        my @children = $box->get_children();
        my $old_preview = $children[0];  # First child is the theme preview

        # Replace the old preview with new one
        $box->remove($old_preview);

        # Set size for the new preview
        if ($new_preview->isa('Gtk3::Image')) {
            $new_preview->set_size_request($self->zoom_level, int($self->zoom_level * 0.75));
        } elsif ($new_preview->isa('Gtk3::DrawingArea')) {
            $new_preview->set_size_request($self->zoom_level, int($self->zoom_level * 0.75));
        }

        $box->pack_start($new_preview, 1, 1, 0);
        $box->reorder_child($new_preview, 0);  # Put it first
        $box->show_all();

        # Update reference
        $self->theme_widgets->{$widget_container + 0} = $new_preview;

        print "Updated theme preview with thumbnail\n";
    }

    sub _show_loading_indicator {
        my ($self, $message) = @_;

        $self->loading_label->set_text($message);
        $self->loading_box->show_all();
        $self->loading_spinner->start();
    }

    sub _update_loading_progress {
        my ($self, $message, $percentage) = @_;

        my $progress_text = "$message ($percentage%)";
        $self->loading_label->set_text($progress_text);
    }

    sub _hide_loading_indicator {
        my $self = shift;

        $self->loading_spinner->stop();
        $self->loading_box->hide();
    }

    sub _update_theme_zoom_async {
        my $self = shift;

        my $flowbox = $self->themes_grid;
        my $size = $self->zoom_level;

        print "DEBUG: Updating zoom to $size\n";

        # Show loading indicator
        $self->loading_box->show_all();
        $self->loading_spinner->start();
        $self->loading_label->set_text('Updating zoom level...');

        # Get all children and process in batches
        my @children = $flowbox->get_children();
        my $total_children = @children;
        my $processed = 0;
        my $batch_size = 6;

        return unless $total_children > 0;

        my $process_batch;
        $process_batch = sub {
            my $batch_start = $processed;
            my $batch_end = ($processed + $batch_size - 1 < $total_children - 1)
                        ? $processed + $batch_size - 1
                        : $total_children - 1;

            for my $i ($batch_start..$batch_end) {
                my $child = $children[$i];
                my $frame = $child->get_child();  # FlowBoxChild -> Frame

                my $image_widget = $self->theme_widgets->{$frame + 0};
                my $theme_info = $self->theme_paths->{$frame + 0};

                if ($image_widget && $theme_info) {
                    # Update image size request immediately for responsive UI
                    $image_widget->set_size_request($size, int($size * 0.75));

                    # Reload thumbnail with new size if available
                    if ($theme_info->{thumbnail_path}) {
                        $self->_load_theme_thumbnail($theme_info, $frame);
                    }
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
                print "Zoom update completed for $total_children theme previews\n";
                return 0;
            }
        };

        # Start processing first batch
        Glib::Timeout->add(10, $process_batch);
    }

    sub _regenerate_all_previews {
        my $self = shift;

        print "Reloading all theme thumbnails...\n";

        # Regenerate current directory
        my $selected_row = $self->directory_list->get_selected_row();
        if ($selected_row) {
            $self->_load_themes_from_directory_async($selected_row);
        }
    }

    sub _cleanup_background_processes {
        my $self = shift;

        # Clear cached theme lists to free memory
        $self->cached_theme_lists({});

        print "Background processes cleaned up\n";
    }

    sub _add_theme_directory {
        my $self = shift;

        my $dialog = Gtk3::FileChooserDialog->new(
            'Select Theme Directory',
            $self->window,
            'select-folder',
            'gtk-cancel' => 'cancel',
            'gtk-open' => 'accept'
        );

        if ($dialog->run() eq 'accept') {
            my $folder = $dialog->get_filename();
            my $name = basename($folder);

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

    sub _remove_theme_directory {
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

    sub _set_cinnamon_theme {
        my ($self, $child) = @_;

        my $frame = $child->get_child();  # FlowBoxChild -> Frame
        my $theme_info = $self->theme_paths->{$frame + 0};

        return unless $theme_info;

        my $theme_name = $theme_info->{name};
        print "Setting Cinnamon theme: $theme_name\n";

        # Verify the theme exists and has Cinnamon files
        my $cinnamon_dir = $theme_info->{cinnamon_path};

        unless (-d $cinnamon_dir && -f "$cinnamon_dir/cinnamon.css") {
            my $dialog = Gtk3::MessageDialog->new(
                $self->window,
                'modal',
                'error',
                'ok',
                "Error: Theme '$theme_name' does not contain valid Cinnamon files."
            );
            $dialog->run();
            $dialog->destroy();
            return;
        }

        # Apply the Cinnamon theme
        print "Applying Cinnamon theme: $theme_name\n";
        system("gsettings set org.cinnamon.theme name '$theme_name'");

        # Update current theme tracking
        $self->current_theme($theme_name);

        # Save to config
        $self->config->{last_applied_theme} = {
            name => $theme_name,
            path => $theme_info->{path},
            timestamp => time()
        };
        $self->_save_config($self->config);
    }

    sub _detect_current_theme {
        my $self = shift;

        # Get the current Cinnamon theme
        my $cinnamon_theme = `gsettings get org.cinnamon.theme name 2>/dev/null`;
        chomp $cinnamon_theme if $cinnamon_theme;
        $cinnamon_theme =~ s/^'(.*)'$/$1/ if $cinnamon_theme;

        $self->current_theme($cinnamon_theme || 'Default');
        print "Current Cinnamon theme: " . $self->current_theme . "\n";
    }

    sub _init_config_system {
        my $self = shift;

        # Create config directory structure
        my $config_dir = $ENV{HOME} . '/.local/share/cinnamon-theme-manager/config';

        unless (-d $config_dir) {
            system("mkdir -p '$config_dir'");
            print "Created config directory: $config_dir\n";
        }
    }

    sub _get_config_file_path {
        my $self = shift;
        return $ENV{HOME} . '/.local/share/cinnamon-theme-manager/config/settings.json';
    }

    sub _load_config {
        my $self = shift;

        my $config_file = $self->_get_config_file_path();
        my $config = {
            preview_size => 400,
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

                    # Validate preview_size range
                    if ($config->{preview_size} < 200 || $config->{preview_size} > 600) {
                        print "Invalid preview size in config, using default\n";
                        $config->{preview_size} = 400;
                    }

                    # Ensure custom_directories is an array ref
                    if (!ref($config->{custom_directories}) || ref($config->{custom_directories}) ne 'ARRAY') {
                        $config->{custom_directories} = [];
                    }

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

        eval {
            # Ensure config directory exists
            my $config_dir = $config_file;
            $config_dir =~ s/\/[^\/]+$//;
            unless (-d $config_dir) {
                system("mkdir -p '$config_dir'");
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

            print "Successfully saved configuration\n";
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
        print "Cinnamon Theme Manager started\n";
        Gtk3::main();
    }
}

# Main execution
if (!caller) {
    my $app = CinnamonThemeManager->new();
    $app->run();
}

1;
