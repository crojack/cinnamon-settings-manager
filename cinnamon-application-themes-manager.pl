#!/usr/bin/perl
use strict;
use warnings;
use utf8;

# Cinnamon Application Themes Manager - Standalone Application
# A dedicated GTK theme management application for Linux Mint Cinnamon
# Written in Perl with GTK3

use Gtk3 -init;
use Glib 'TRUE', 'FALSE';
use File::Spec;
use JSON qw(encode_json decode_json);
use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use File::Basename;
use File::HomeDir;

$SIG{__WARN__} = sub {
    my $warning = shift;
    return if $warning =~ /Theme parsing error/;
    warn $warning;
};

# Main application class
package CinnamonApplicationThemesManager {
    use Moo;
    use File::HomeDir;

    has 'window' => (is => 'rw');
    has 'directory_list' => (is => 'rw');
    has 'themes_grid' => (is => 'rw');
    has 'content_switcher' => (is => 'rw');
    has 'themes_mode' => (is => 'rw');
    has 'settings_mode' => (is => 'rw');
    has 'zoom_level' => (is => 'rw', default => sub { 300 });
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
        $self->zoom_level($config->{preview_size} || 450);
        $self->last_selected_directory_path($config->{last_selected_directory});

        print "Configuration initialized\n";
        print "  Preview size: " . $self->zoom_level . "\n";
        print "  Custom directories: " . @{$config->{custom_directories} || []} . "\n";
        print "  Last directory: " . ($self->last_selected_directory_path || 'none') . "\n";
    }

    sub _initialize_directory_structure {
        my $self = shift;

        # Create main application directory for Application Themes Manager
        my $app_dir = $ENV{HOME} . '/.local/share/cinnamon-application-themes-manager';
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

        print "Directory structure initialized for Application Themes Manager\n";
    }

    sub _setup_ui {
        my $self = shift;

        # Create main window
        my $window = Gtk3::Window->new('toplevel');
        $window->set_title('Cinnamon Application Themes Manager');
        $window->set_default_size(1200, 900);
        $window->set_position('center');
        $window->set_icon_name('preferences-desktop-theme');

        # Create header bar
        my $header = Gtk3::HeaderBar->new();
        $header->set_show_close_button(1);
        $header->set_title('Cinnamon Application Themes Manager');
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
        $themes_grid->set_max_children_per_line(8);
        $themes_grid->set_min_children_per_line(2);
        $themes_grid->set_selection_mode('single');
        $themes_grid->set_margin_left(12);
        $themes_grid->set_margin_right(12);
        $themes_grid->set_margin_top(12);
        $themes_grid->set_margin_bottom(12);
        $themes_grid->set_row_spacing(12);  # Changed from 24 back to 12 to match backgrounds manager
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
            my $new_zoom = ($self->zoom_level > 300) ? $self->zoom_level - 50 : 300;
            $self->zoom_level($new_zoom);
            $self->_update_theme_zoom_async();
            # Save zoom level to config
            $self->config->{preview_size} = $self->zoom_level;
            $self->_save_config($self->config);
        });

        $self->themes_grid->signal_connect('child-activated' => sub {
            my ($widget, $child) = @_;
            $self->_set_gtk_theme($child);
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
        $current_label->set_markup('<b>GTK Theme:</b> Detecting...');
        $current_container->pack_start($current_label, 0, 0, 0);

        my $icon_theme_label = Gtk3::Label->new('Detecting icon theme...');
        $icon_theme_label->set_halign('start');
        $icon_theme_label->set_markup('<b>Icon Theme:</b> Detecting...');
        $current_container->pack_start($icon_theme_label, 0, 0, 0);

        my $cursor_theme_label = Gtk3::Label->new('Detecting cursor theme...');
        $cursor_theme_label->set_halign('start');
        $cursor_theme_label->set_markup('<b>Cursor Theme:</b> Detecting...');
        $current_container->pack_start($cursor_theme_label, 0, 0, 0);

        my $button_box = Gtk3::Box->new('horizontal', 6);

        my $refresh_button = Gtk3::Button->new_with_label('Refresh Theme Status');
        $refresh_button->set_halign('start');
        $refresh_button->signal_connect('clicked' => sub {
            $self->_detect_current_theme();
            my $theme = $self->current_theme || 'Unknown';
            $current_label->set_markup("<b>GTK Theme:</b> $theme");

            my $icon_theme = `gsettings get org.cinnamon.desktop.interface icon-theme 2>/dev/null`;
            chomp $icon_theme if $icon_theme;
            $icon_theme =~ s/^'(.*)'$/$1/ if $icon_theme;
            $icon_theme_label->set_markup("<b>Icon Theme:</b> " . ($icon_theme || 'Unknown'));

            my $cursor_theme = `gsettings get org.cinnamon.desktop.interface cursor-theme 2>/dev/null`;
            chomp $cursor_theme if $cursor_theme;
            $cursor_theme =~ s/^'(.*)'$/$1/ if $cursor_theme;
            $cursor_theme_label->set_markup("<b>Cursor Theme:</b> " . ($cursor_theme || 'Unknown'));
        });
        $button_box->pack_start($refresh_button, 0, 0, 0);

        my $apply_system_button = Gtk3::Button->new_with_label('Apply System Theme');
        $apply_system_button->set_halign('start');
        $apply_system_button->signal_connect('clicked' => sub {
            my $dialog = Gtk3::MessageDialog->new(
                $self->window,
                'modal',
                'question',
                'yes-no',
                "Apply the default Cinnamon system theme?\n\nThis will set:\n• GTK Theme: Mint-Y\n• Icon Theme: Mint-Y\n• Cursor Theme: DMZ-White\n\nContinue?"
            );
            my $response = $dialog->run();
            $dialog->destroy();

            if ($response eq 'yes') {
                $self->_apply_system_theme();
            }
        });
        $button_box->pack_start($apply_system_button, 0, 0, 0);

        my $backup_button = Gtk3::Button->new_with_label('Backup Current Settings');
        $backup_button->set_halign('start');
        $backup_button->signal_connect('clicked' => sub {
            $self->_backup_current_settings();
        });
        $button_box->pack_start($backup_button, 0, 0, 0);

        $current_container->pack_start($button_box, 0, 0, 0);

        $current_frame->add($current_container);
        $settings_box->pack_start($current_frame, 0, 0, 0);

        # GTK Theme Options section
        my $options_frame = Gtk3::Frame->new();
        $options_frame->set_label('Interface Options');
        $options_frame->set_label_align(0.02, 0.5);

        my $options_container = Gtk3::Box->new('vertical', 12);
        $options_container->set_margin_left(12);
        $options_container->set_margin_right(12);
        $options_container->set_margin_top(12);
        $options_container->set_margin_bottom(12);

        # Font scaling
        my $font_scaling_label = Gtk3::Label->new('Font Scaling:');
        $font_scaling_label->set_halign('start');
        $options_container->pack_start($font_scaling_label, 0, 0, 0);

        my $font_scaling_scale = Gtk3::Scale->new_with_range('horizontal', 0.5, 2.0, 0.1);
        $font_scaling_scale->set_value(1.0);
        $font_scaling_scale->set_show_fill_level(1);
        $options_container->pack_start($font_scaling_scale, 0, 0, 0);

        # Dark theme preference
        my $dark_theme_check = Gtk3::CheckButton->new_with_label('Prefer Dark Theme Variants');
        $options_container->pack_start($dark_theme_check, 0, 0, 0);

        # Cursor size
        my $cursor_size_label = Gtk3::Label->new('Cursor Size:');
        $cursor_size_label->set_halign('start');
        $options_container->pack_start($cursor_size_label, 0, 0, 0);

        my $cursor_size_combo = Gtk3::ComboBoxText->new();
        $cursor_size_combo->append_text('Small (16px)');
        $cursor_size_combo->append_text('Normal (24px)');
        $cursor_size_combo->append_text('Large (32px)');
        $cursor_size_combo->append_text('Extra Large (48px)');
        $cursor_size_combo->set_active(1); # Default to Normal
        $cursor_size_combo->set_halign('start');
        $options_container->pack_start($cursor_size_combo, 0, 0, 0);

        # Toolbar style
        my $toolbar_style_label = Gtk3::Label->new('Toolbar Style:');
        $toolbar_style_label->set_halign('start');
        $options_container->pack_start($toolbar_style_label, 0, 0, 0);

        my $toolbar_style_combo = Gtk3::ComboBoxText->new();
        $toolbar_style_combo->append_text('Icons and Text');
        $toolbar_style_combo->append_text('Icons Only');
        $toolbar_style_combo->append_text('Text Only');
        $toolbar_style_combo->set_active(0);
        $toolbar_style_combo->set_halign('start');
        $options_container->pack_start($toolbar_style_combo, 0, 0, 0);

        $options_frame->add($options_container);
        $settings_box->pack_start($options_frame, 0, 0, 0);

        # Apply button
        my $apply_button = Gtk3::Button->new_with_label('Apply Settings');
        $apply_button->set_halign('center');

        # Connect apply button signal
        $apply_button->signal_connect('clicked' => sub {
            my $font_scaling = $font_scaling_scale->get_value();
            my $prefer_dark = $dark_theme_check->get_active();
            my $cursor_size_text = $cursor_size_combo->get_active_text();
            my $toolbar_style_text = $toolbar_style_combo->get_active_text();

            # Map cursor size to pixel value
            my %cursor_sizes = (
                'Small (16px)' => 16,
                'Normal (24px)' => 24,
                'Large (32px)' => 32,
                'Extra Large (48px)' => 48
            );
            my $cursor_size = $cursor_sizes{$cursor_size_text} || 24;

            # Map toolbar style
            my %toolbar_styles = (
                'Icons and Text' => 'both',
                'Icons Only' => 'icons',
                'Text Only' => 'text'
            );
            my $toolbar_style = $toolbar_styles{$toolbar_style_text} || 'both';

            print "Applying GTK settings:\n";
            print "  Font scaling: $font_scaling\n";
            print "  Prefer dark theme: " . ($prefer_dark ? 'yes' : 'no') . "\n";
            print "  Cursor size: $cursor_size\n";
            print "  Toolbar style: $toolbar_style\n";

            # Apply settings using gsettings
            system("gsettings set org.cinnamon.desktop.interface text-scaling-factor $font_scaling");
            system("gsettings set org.cinnamon.desktop.interface gtk-theme-prefer-dark-theme " . ($prefer_dark ? 'true' : 'false'));
            system("gsettings set org.cinnamon.desktop.interface cursor-size $cursor_size");
            system("gsettings set org.cinnamon.desktop.interface toolbar-style '$toolbar_style'");

            # Show confirmation
            my $dialog = Gtk3::MessageDialog->new(
                $self->window,
                'modal',
                'info',
                'ok',
                'Interface settings applied successfully!'
            );
            $dialog->run();
            $dialog->destroy();
        });

        $settings_box->pack_start($apply_button, 0, 0, 12);

        # Initialize current theme display
        Glib::Timeout->add(500, sub {
            $self->_detect_current_theme();
            my $theme = $self->current_theme || 'Unknown';
            $current_label->set_markup("<b>GTK Theme:</b> $theme");

            my $icon_theme = `gsettings get org.cinnamon.desktop.interface icon-theme 2>/dev/null`;
            chomp $icon_theme if $icon_theme;
            $icon_theme =~ s/^'(.*)'$/$1/ if $icon_theme;
            $icon_theme_label->set_markup("<b>Icon Theme:</b> " . ($icon_theme || 'Unknown'));

            my $cursor_theme = `gsettings get org.cinnamon.desktop.interface cursor-theme 2>/dev/null`;
            chomp $cursor_theme if $cursor_theme;
            $cursor_theme =~ s/^'(.*)'$/$1/ if $cursor_theme;
            $cursor_theme_label->set_markup("<b>Cursor Theme:</b> " . ($cursor_theme || 'Unknown'));

            return 0; # Don't repeat
        });

        return $settings_box;
    }

    sub _apply_system_theme {
        my $self = shift;

        print "Applying default Cinnamon system theme...\n";

        # Apply default Mint themes
        system("gsettings set org.cinnamon.desktop.interface gtk-theme 'Mint-Y'");
        system("gsettings set org.cinnamon.desktop.interface icon-theme 'Mint-Y'");
        system("gsettings set org.cinnamon.desktop.interface cursor-theme 'DMZ-White'");

        # Update current theme tracking
        $self->current_theme('Mint-Y');

        my $dialog = Gtk3::MessageDialog->new(
            $self->window,
            'modal',
            'info',
            'ok',
            "Default Cinnamon system theme applied!\n\nGTK Theme: Mint-Y\nIcon Theme: Mint-Y\nCursor Theme: DMZ-White"
        );
        $dialog->run();
        $dialog->destroy();

        # Refresh the current theme detection
        $self->_detect_current_theme();
    }

    sub _backup_current_settings {
        my $self = shift;

        print "Backing up current theme settings...\n";

        # Get current settings
        my $gtk_theme = `gsettings get org.cinnamon.desktop.interface gtk-theme 2>/dev/null`;
        my $icon_theme = `gsettings get org.cinnamon.desktop.interface icon-theme 2>/dev/null`;
        my $cursor_theme = `gsettings get org.cinnamon.desktop.interface cursor-theme 2>/dev/null`;

        chomp($gtk_theme, $icon_theme, $cursor_theme);
        $gtk_theme =~ s/^'(.*)'$/$1/;
        $icon_theme =~ s/^'(.*)'$/$1/;
        $cursor_theme =~ s/^'(.*)'$/$1/;

        my $backup = {
            gtk_theme => $gtk_theme,
            icon_theme => $icon_theme,
            cursor_theme => $cursor_theme,
            timestamp => time(),
            date => scalar(localtime())
        };

        # Save backup to config
        if (!$self->config->{theme_backups}) {
            $self->config->{theme_backups} = [];
        }

        push @{$self->config->{theme_backups}}, $backup;

        # Keep only last 10 backups
        if (@{$self->config->{theme_backups}} > 10) {
            shift @{$self->config->{theme_backups}};
        }

        $self->_save_config($self->config);

        my $dialog = Gtk3::MessageDialog->new(
            $self->window,
            'modal',
            'info',
            'ok',
            "Current theme settings backed up successfully!\n\nGTK: $gtk_theme\nIcon: $icon_theme\nCursor: $cursor_theme"
        );
        $dialog->run();
        $dialog->destroy();
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

        # Default GTK theme directories
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

        print "DEBUG: Loading directory: $dir_path\n";

        # Show enhanced loading indicator
        $self->_show_loading_indicator('Scanning for themes...');

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
            my @themes = $self->_scan_gtk_themes($dir_path);
            @themes = sort { lc($a->{name}) cmp lc($b->{name}) } @themes;
            $themes_ref = \@themes;
            $self->cached_theme_lists->{$dir_path} = $themes_ref;
            print "Scanned $dir_path: " . @themes . " GTK themes found\n";
        }

        if (@$themes_ref == 0) {
            $self->_hide_loading_indicator();
            print "No GTK themes found in $dir_path\n";
            return;
        }

        # Start progressive loading with parallel preview generation
        $self->_start_progressive_loading($themes_ref, $dir_path);
    }

    sub _start_progressive_loading {
        my ($self, $themes_ref, $dir_path) = @_;

        my $total_themes = @$themes_ref;
        my $loaded_widgets = 0;
        my $completed_previews = 0;

        print "Starting progressive loading of $total_themes themes\n";

        # Initialize progress tracking
        $self->{preview_progress} = {
            total => $total_themes,
            loaded_widgets => 0,
            completed_previews => 0,
            active_generations => 0,
            max_parallel => 3,  # Generate 3 previews simultaneously
            generation_queue => [],
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

                # Add to preview generation queue
                push @{$self->{preview_progress}->{generation_queue}}, {
                    theme_info => $theme_info,
                    widget => $theme_widget,
                    index => $i
                };
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
                # Widget creation complete, start preview generation
                print "All widgets created, starting parallel preview generation\n";
                $self->_start_parallel_preview_generation();
                return 0;
            }
        };

        # Start widget creation
        Glib::Timeout->add(10, $create_widgets);
    }

    sub _start_parallel_preview_generation {
        my $self = shift;

        my $progress = $self->{preview_progress};
        return unless $progress;

        print "Starting parallel preview generation (max " . $progress->{max_parallel} . " concurrent)\n";

        # Start initial parallel workers
        for my $worker_id (0..$progress->{max_parallel}-1) {
            $self->_start_preview_worker($worker_id);
        }

        # Start progress monitor
        $self->_start_progress_monitor();
    }

    sub _start_preview_worker {
        my ($self, $worker_id) = @_;

        my $progress = $self->{preview_progress};
        return unless $progress && @{$progress->{generation_queue}};

        # Get next item from queue
        my $item = shift @{$progress->{generation_queue}};
        return unless $item;

        $progress->{active_generations}++;

        print "Worker $worker_id: Starting preview for " . $item->{theme_info}->{name} . "\n";

        # Generate preview in background
        Glib::Timeout->add(50, sub {
            return 0 if $self->current_directory ne $progress->{dir_path};

            my $success = $self->_generate_theme_preview_fast($item->{theme_info}, $item->{widget});

            # Update progress
            $progress->{completed_previews}++;
            $progress->{active_generations}--;

            my $preview_progress = 30 + int(($progress->{completed_previews} / $progress->{total}) * 70);
            $self->_update_loading_progress(
                "Generating previews... (" . $progress->{completed_previews} . "/" . $progress->{total} . ")",
                $preview_progress
            );

            print "Worker $worker_id: Completed " . $item->{theme_info}->{name} . " (" .
                $progress->{completed_previews} . "/" . $progress->{total} . ")\n";

            # Start next item if available
            if (@{$progress->{generation_queue}}) {
                $self->_start_preview_worker($worker_id);
            }

            return 0;
        });
    }

    sub _create_theme_widget_with_placeholder {
        my ($self, $theme_info) = @_;

        print "Creating widget with placeholder for: " . $theme_info->{name} . "\n";

        # Create frame with inset shadow (like backgrounds manager)
        my $frame = Gtk3::Frame->new();
        $frame->set_shadow_type('in');

        # Create vertical box container
        my $box = Gtk3::Box->new('vertical', 6);
        $box->set_margin_left(6);
        $box->set_margin_right(6);
        $box->set_margin_top(6);
        $box->set_margin_bottom(6);

        # Create placeholder preview (fast)
        my $placeholder = $self->_create_fast_placeholder($theme_info);
        $placeholder->set_size_request($self->zoom_level, int($self->zoom_level * 0.75));

        $box->pack_start($placeholder, 1, 1, 0);

        # Create label
        my $theme_name = $theme_info->{display_name} || $theme_info->{name};
        my $label = Gtk3::Label->new($theme_name);
        $label->set_ellipsize('middle');
        $label->set_max_width_chars(15);

        $box->pack_start($label, 0, 0, 0);
        $frame->add($box);

        # Store references - use frame as key like backgrounds manager
        $self->theme_paths->{$frame + 0} = $theme_info;
        $self->theme_widgets->{$frame + 0} = $placeholder;

        return $frame;
    }

    sub _create_fast_placeholder {
        my ($self, $theme_info) = @_;

        # Quick background color detection
        my $bg_color = $self->_extract_theme_background_color_fast($theme_info);

        # Create simple colored rectangle
        my $width = $self->zoom_level;
        my $height = int($self->zoom_level * 0.75);

        my $surface = Cairo::ImageSurface->create('argb32', $width, $height);
        my $cr = Cairo::Context->create($surface);

        # Fill with theme background color
        $cr->set_source_rgb(@$bg_color);
        $cr->rectangle(0, 0, $width, $height);
        $cr->fill();

        # Add subtle border
        $cr->set_source_rgb(0.7, 0.7, 0.7);
        $cr->set_line_width(1);
        $cr->rectangle(0.5, 0.5, $width - 1, $height - 1);
        $cr->stroke();

        # Convert to pixbuf
        $surface->write_to_png("/tmp/fast_placeholder_$$.png");
        my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file("/tmp/fast_placeholder_$$.png");
        unlink("/tmp/fast_placeholder_$$.png");

        return Gtk3::Image->new_from_pixbuf($pixbuf);
    }

    sub _extract_theme_background_color_fast {
        my ($self, $theme_info) = @_;

        # Fast color detection - just basic patterns
        my $theme_name = $theme_info->{name};

        # Quick theme name-based detection
        if ($theme_name =~ /dark|noir|black/i) {
            return [0.22, 0.22, 0.22];  # Dark theme
        } elsif ($theme_name =~ /mint/i) {
            return [0.96, 0.96, 0.96];  # Mint light
        } elsif ($theme_name =~ /adwaita/i) {
            return [0.98, 0.98, 0.98];  # Adwaita light
        }

        # Default light theme
        return [0.95, 0.95, 0.95];
    }

    sub _update_widget_preview {
        my ($self, $widget_container, $preview_path) = @_;

        # Load new theme preview
        my $new_preview = eval {
            my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale(
                $preview_path, $self->zoom_level, int($self->zoom_level * 0.75), 1
            );
            return $pixbuf ? Gtk3::Image->new_from_pixbuf($pixbuf) : undef;
        };

        return unless $new_preview && !$@;

        # Get the box container from the frame
        my $box = $widget_container->get_child();
        my @children = $box->get_children();
        my $old_preview = $children[0];  # First child is the theme preview

        # Replace the old preview with new one
        $box->remove($old_preview);
        $new_preview->set_size_request($self->zoom_level, int($self->zoom_level * 0.75));
        $box->pack_start($new_preview, 1, 1, 0);
        $box->reorder_child($new_preview, 0);  # Put it first
        $box->show_all();

        # Update reference
        $self->theme_widgets->{$widget_container + 0} = $new_preview;

        print "Updated theme preview for widget\n";
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


    sub _scan_gtk_themes {
        my ($self, $base_dir) = @_;

        my @themes = ();

        opendir(my $dh, $base_dir) or return @themes;
        my @subdirs = grep { -d "$base_dir/$_" && $_ !~ /^\./ } readdir($dh);
        closedir($dh);

        foreach my $subdir (@subdirs) {
            my $theme_path = "$base_dir/$subdir";
            my $gtk3_dir = "$theme_path/gtk-3.0";
            my $gtk2_dir = "$theme_path/gtk-2.0";

            # Check if this directory contains a GTK theme
            if (-d $gtk3_dir || -d $gtk2_dir) {
                my $gtk3_css = "$gtk3_dir/gtk.css";
                my $gtk2_rc = "$gtk2_dir/gtkrc";

                if (-f $gtk3_css || -f $gtk2_rc) {
                    # Parse theme information
                    my $theme_info = $self->_parse_theme_info($theme_path, $subdir);
                    push @themes, $theme_info;
                    print "DEBUG: Including GTK theme '$subdir'\n";
                }
            }
        }

        return @themes;
    }

    sub _parse_theme_info {
        my ($self, $theme_path, $theme_name) = @_;

        my $theme_info = {
            name          => $theme_name,
            path          => $theme_path,
            display_name  => $theme_name,
        };

        # Optionally override display name if index.theme defines it
        my $index_file = "$theme_path/index.theme";
        if (-f $index_file) {
            open my $fh, '<', $index_file or return $theme_info;

            while (my $line = <$fh>) {
                chomp $line;
                next if $line =~ /^\s*#/ || $line =~ /^\s*$/;
                if ($line =~ /^Name\s*=\s*(.+)$/) {
                    $theme_info->{display_name} = $1;
                    last;
                }
            }
            close $fh;
        }

        return $theme_info;
    }

    sub _create_gtk_preview {
        my ($self, $theme_info, $size) = @_;

        my $theme_name = $theme_info->{name};
        my $theme_path = $theme_info->{path};

        # Calculate exact dimensions
        my $width = $size;
        my $height = int($size * 0.75);

        # Preview cache directory
        $self->{preview_cache_dir} //= "$ENV{HOME}/.local/share/cinnamon-application-themes-manager/previews";
        system("mkdir -p '$self->{preview_cache_dir}'") unless -d $self->{preview_cache_dir};

        my $preview_path = "$self->{preview_cache_dir}/${theme_name}-preview.png";

    # Try to load existing preview first
        my $preview_widget;
        if (-f $preview_path && -s $preview_path) {
            eval {
                my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale(
                    $preview_path, $width, $height, 1
                );
                $preview_widget = Gtk3::Image->new_from_pixbuf($pixbuf) if $pixbuf;
            };
            warn "Error loading cached preview: $@" if $@;
        }

        # Try static preview images from theme directory
        unless ($preview_widget) {
            foreach my $fallback (
                "thumbnail.png", "preview.png", "screenshot.png", "thumb.png"
            ) {
                my $static = "$theme_path/$fallback";
                next unless -f $static && -s $static > 1000;
                eval {
                    my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale(
                        $static, $width, $height, 1
                    );
                    $preview_widget = Gtk3::Image->new_from_pixbuf($pixbuf) if $pixbuf;
                };
                warn "Error loading static preview: $@" if $@;
                last if $preview_widget;
            }
        }

        # Generate dynamic preview if no static preview exists
        unless ($preview_widget) {
            # Create themed placeholder first
            my $pixbuf = $self->_create_themed_placeholder_pixbuf($theme_info, $width, $height);
            $preview_widget = Gtk3::Image->new_from_pixbuf($pixbuf);

            # Schedule dynamic preview generation
            $self->_schedule_preview_generation($theme_name, $theme_path, $preview_path, $width, $height);
        }

        return $preview_widget;
    }

    sub _schedule_preview_generation {
        my ($self, $theme_name, $theme_path, $cache_file, $width, $height) = @_;

        # Add to generation queue if not already queued
        if (!$self->{preview_generation_queue}) {
            $self->{preview_generation_queue} = [];
        }

        # Check if already queued
        foreach my $queued (@{$self->{preview_generation_queue}}) {
            return if $queued->{theme_name} eq $theme_name;
        }

        # Add to queue with exact dimensions
        push @{$self->{preview_generation_queue}}, {
            theme_name => $theme_name,
            theme_path => $theme_path,
            cache_file => $cache_file,
            width => $width,
            height => $height
        };

        # Start processing queue if not already running
        if (!$self->{preview_generation_active}) {
            $self->_process_preview_generation_queue();
        }
    }

    sub _generate_preview_async {
        my ($self, $theme_info, $widget_container, $preview_path, $size) = @_;

        my $theme_name = $theme_info->{name};
        my $theme_path = $theme_info->{path};

        print "Starting async preview generation for: $theme_name\n";

        # Create the preview script
        my $script_content = $self->_create_improved_preview_script(
            $theme_name, $theme_path, $preview_path, $size, int($size * 0.75)
        );

        # Write script to temporary file
        my $script_path = "/tmp/preview_${$}_${theme_name}_" . time() . ".pl";
        $script_path =~ s/[^a-zA-Z0-9_\/\-\.]/_/g;  # Sanitize filename

        open my $fh, '>', $script_path or do {
            print "ERROR: Cannot create preview script: $!\n";
            return 0;
        };
        print $fh $script_content;
        close $fh;
        chmod 0755, $script_path;

        print "Created script: $script_path\n";
        print "Target preview: $preview_path\n";

        # Create a log file for debugging
        my $log_path = "/tmp/preview_${$}_${theme_name}_" . time() . ".log";
        $log_path =~ s/[^a-zA-Z0-9_\/\-\.]/_/g;

        # Start background process with logging
        my $cmd = "timeout 30s perl '$script_path' > '$log_path' 2>&1 &";
        print "Executing: $cmd\n";
        system($cmd);

        print "Started background preview generation for $theme_name\n";

        # Monitor for completion using a timer
        $self->_monitor_preview_file($preview_path, $widget_container, $theme_name, $script_path, $log_path);

        return 1;
    }

    sub _monitor_preview_file {
        my ($self, $preview_path, $widget_container, $theme_name, $script_path, $log_path) = @_;

        my $check_count = 0;
        my $max_checks = 60;  # Check for 30 seconds (60 * 500ms)

        my $monitor;
        $monitor = sub {
            $check_count++;

            print "Checking preview for $theme_name (attempt $check_count)\n";

            # Check if preview file exists and has content
            if (-f $preview_path && -s $preview_path > 1000) {
                print "Preview completed for $theme_name (file size: " . (-s $preview_path) . " bytes)\n";

                # Update the widget preview
                $self->_update_widget_preview($widget_container, $preview_path);

                # Clean up files
                unlink $script_path if -f $script_path;
                unlink $log_path if -f $log_path;

                return 0;  # Stop monitoring
            }

            # Check if we've exceeded max wait time
            if ($check_count >= $max_checks) {
                print "Preview generation timed out for $theme_name\n";

                # Show error log if available
                if (-f $log_path && -s $log_path) {
                    print "Error log for $theme_name:\n";
                    open my $log_fh, '<', $log_path;
                    while (my $line = <$log_fh>) {
                        print "  $line";
                    }
                    close $log_fh;
                } else {
                    print "No log file found for $theme_name\n";
                }

                # Clean up files
                unlink $script_path if -f $script_path;
                unlink $log_path if -f $log_path;

                return 0;  # Stop monitoring
            }

            # Continue monitoring
            Glib::Timeout->add(500, $monitor);
            return 0;
        };

        # Start monitoring after a brief delay
        Glib::Timeout->add(500, $monitor);
    }

    sub _generate_theme_preview_fast {
        my ($self, $theme_info, $widget_container) = @_;

        my $size = $self->zoom_level;
        my $cache_dir = $self->{preview_cache_dir} || "$ENV{HOME}/.local/share/cinnamon-application-themes-manager/previews";
        system("mkdir -p '$cache_dir'") unless -d $cache_dir;

        my $preview_path = "$cache_dir/" . $theme_info->{name} . "-preview.png";

        print "Checking for existing preview: $preview_path\n";

        # Check if preview already exists and is recent
        if (-f $preview_path && -s $preview_path > 1000) {
            my $preview_age = time() - (stat($preview_path))[9];
            if ($preview_age < 86400) {  # Less than 24 hours old
                print "Using existing preview for " . $theme_info->{name} . "\n";
                $self->_update_widget_preview($widget_container, $preview_path);
                return 1;
            }
        }

        # Check if _create_improved_preview_script method exists
        if ($self->can('_create_improved_preview_script')) {
            print "Using _create_improved_preview_script for " . $theme_info->{name} . "\n";
            # Generate preview asynchronously
            $self->_generate_preview_async($theme_info, $widget_container, $preview_path, $size);
        } else {
            print "No _create_improved_preview_script method, using fallback for " . $theme_info->{name} . "\n";
            # Use your existing _generate_dynamic_preview method synchronously but with shorter timeout
            my $success = eval {
                local $SIG{ALRM} = sub { die "timeout\n" };
                alarm(5);  # 5 second timeout per preview

                my $result = $self->_generate_dynamic_preview(
                    $theme_info->{name},
                    $theme_info->{path},
                    $preview_path,
                    $size,
                    int($size * 0.75)
                );

                alarm(0);
                return $result;
            };

            if ($@ || !$success) {
                print "Preview generation failed for " . $theme_info->{name} . ": $@\n";
            } elsif (-f $preview_path && -s $preview_path > 1000) {
                print "Preview generated successfully for " . $theme_info->{name} . "\n";
                $self->_update_widget_preview($widget_container, $preview_path);
            }
        }

        return 1;
    }

    sub _start_progress_monitor {
        my $self = shift;

        my $last_check_time = time();

        my $monitor;
        $monitor = sub {
            my $progress = $self->{preview_progress};
            return 0 unless $progress;

            my $current_time = time();

            # Update progress every 2 seconds
            if ($current_time - $last_check_time >= 2) {
                # Count how many previews actually exist
                my $actual_completed = 0;
                foreach my $item (@{$progress->{generation_queue}}) {
                    my $cache_dir = $self->{preview_cache_dir} || "$ENV{HOME}/.local/share/cinnamon-application-themes-manager/previews";
                    my $preview_path = "$cache_dir/" . $item->{theme_info}->{name} . "-preview.png";

                    if (-f $preview_path && -s $preview_path > 1000) {
                        $actual_completed++;
                    }
                }

                my $progress_percentage = 30 + int(($actual_completed / $progress->{total}) * 70);
                $self->_update_loading_progress(
                    "Generating previews... ($actual_completed/" . $progress->{total} . ")",
                    $progress_percentage
                );

                $last_check_time = $current_time;

                # Check if all are complete
                if ($actual_completed >= $progress->{total}) {
                    print "All preview generation completed!\n";
                    $self->_hide_loading_indicator();
                    delete $self->{preview_progress};
                    return 0;  # Stop monitoring
                }
            }

            # Continue monitoring
            Glib::Timeout->add(1000, $monitor);
            return 0;
        };

        Glib::Timeout->add(1000, $monitor);
    }

    sub _process_preview_generation_queue {
        my $self = shift;

        return unless $self->{preview_generation_queue} && @{$self->{preview_generation_queue}};

        $self->{preview_generation_active} = 1;

        my $item = shift @{$self->{preview_generation_queue}};

        print "Processing preview generation for: " . $item->{theme_name} . "\n";

        # Generate preview in background
        Glib::Timeout->add(50, sub {
            my $success = $self->_generate_dynamic_preview(
                $item->{theme_name},
                $item->{theme_path},
                $item->{cache_file},
                $item->{width},
                $item->{height}
            );

            if ($success) {
                print "Auto-generated preview for " . $item->{theme_name} . "\n";
                # Trigger a refresh of this specific theme widget
                $self->_refresh_theme_widget_if_visible($item->{theme_name});
            }

            # Continue with next item in queue
            if (@{$self->{preview_generation_queue}}) {
                Glib::Timeout->add(100, sub {
                    $self->_process_preview_generation_queue();
                    return 0;
                });
            } else {
                $self->{preview_generation_active} = 0;
                print "Preview generation queue completed\n";
            }

            return 0; # Don't repeat
        });
    }

    sub _refresh_theme_widget_if_visible {
        my ($self, $theme_name) = @_;

        # Check if this theme is currently visible and refresh its widget
        my $flowbox = $self->themes_grid;
        foreach my $child ($flowbox->get_children()) {
            my $container = $child->get_child();
            my $theme_info = $self->theme_paths->{$container + 0};

            if ($theme_info && $theme_info->{name} eq $theme_name) {
                print "Refreshing widget for $theme_name\n";
                # Replace the placeholder with the new preview
                my $cache_file = $self->{preview_cache_dir} . "/${theme_name}-preview.png";
                if (-f $cache_file && -s $cache_file) {
                    my $new_preview = eval {
                        my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale(
                            $cache_file, $self->zoom_level, int($self->zoom_level * 0.75), 1
                        );
                        return $pixbuf ? Gtk3::Image->new_from_pixbuf($pixbuf) : undef;
                    };

                    if ($new_preview && !$@) {
                        # Set fixed size for consistency
                        $new_preview->set_size_request($self->zoom_level, int($self->zoom_level * 0.75));
                        $new_preview->set_halign('center');

                        # Get the old preview widget (first child of container)
                        my @children = $container->get_children();
                        my $old_preview = $children[0];

                        # Replace the old preview widget
                        $container->remove($old_preview);
                        $container->pack_start($new_preview, 0, 0, 0);
                        $container->reorder_child($new_preview, 0); # Put it first
                        $container->show_all();

                        # Update widget reference
                        $self->theme_widgets->{$container + 0} = $new_preview;
                    }
                }
                last;
            }
        }
    }

    sub _generate_dynamic_preview {
        my ($self, $theme_name, $theme_path, $output_file, $width, $height) = @_;

        $width //= $self->zoom_level;
        $height //= int($self->zoom_level * 0.75);

        print "Generating hybrid preview for theme: $theme_name (${width}x${height})\n";

        my $success = eval {
            $self->_create_hybrid_preview($theme_name, $theme_path, $output_file, $width, $height);
        };

        if ($@ || !$success) {
            print "Hybrid preview failed ($@), falling back to GTK preview\n";
            return $self->_generate_gtk_preview_fallback($theme_name, $theme_path, $output_file, $width, $height);
        }

        print "Successfully generated hybrid preview for $theme_name\n";
        return 1;
    }

    sub _generate_gtk_preview_fallback {
        my ($self, $theme_name, $theme_path, $output_file, $width, $height) = @_;

        print "Using GTK fallback for theme: $theme_name\n";

        my $script = $self->_create_improved_preview_script($theme_name, $theme_path, $output_file, $width, $height);

        # Write script to temporary file
        my $script_path = "/tmp/theme_preview_${$}_" . time() . ".pl";
        open my $fh, '>', $script_path or return 0;
        print $fh $script;
        close $fh;
        chmod 0755, $script_path;

        # Run the script with timeout
        my $result = system("timeout 30s perl '$script_path' 2>/dev/null");
        unlink $script_path;

        # Check if output file was created successfully
        my $success = ($result == 0 && -f $output_file && -s $output_file > 1000);

        return $success;
    }

    sub _create_themed_placeholder_pixbuf {
        my ($self, $theme_info, $width, $height) = @_;

        print "Creating enhanced themed placeholder for: " . $theme_info->{name} . "\n";

        # Extract comprehensive theme colors
        my $colors = $self->_extract_comprehensive_theme_colors($theme_info);

        # Create output file path for the enhanced preview
        my $temp_file = "/tmp/enhanced_preview_" . $theme_info->{name} . "_$$.png";

        # Generate enhanced Cairo preview instead of just solid color
        my $success = $self->_create_enhanced_cairo_preview($colors, $width, $height, $temp_file);

        if ($success && -f $temp_file && -s $temp_file > 100) {
            # Load the enhanced preview
            my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($temp_file);
            unlink($temp_file); # Clean up temp file
            return $pixbuf;
        } else {
            # Final fallback: create simple solid color pixbuf
            my $bg_color = $colors->{bg_color};
            my $surface = Cairo::ImageSurface->create('argb32', $width, $height);
            my $cr = Cairo::Context->create($surface);

            $cr->save();
            $cr->set_source_rgb(@$bg_color);
            $cr->rectangle(0, 0, $width, $height);
            $cr->fill();
            $cr->restore();

            # Convert Cairo surface to GdkPixbuf
            $surface->write_to_png("/tmp/simple_placeholder_$$.png");
            my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file("/tmp/simple_placeholder_$$.png");
            unlink("/tmp/simple_placeholder_$$.png");

            return $pixbuf;
        }
    }

    sub _extract_theme_background_color {
        my ($self, $theme_info) = @_;

        my $theme_path = $theme_info->{path};
        my $theme_name = $theme_info->{name};
        my $css_file = "$theme_path/gtk-3.0/gtk.css";

        # Default colors
        my $default_light = [0.98, 0.98, 0.98];  # Light gray
        my $default_dark = [0.22, 0.22, 0.22];   # Dark gray

        return $default_light unless -f $css_file;

        # Read CSS file
        open my $fh, '<', $css_file or return $default_light;
        my $css_content = do { local $/; <$fh> };
        close $fh;

        # Priority-based color extraction
        my $bg_color;

        # 1. Look for @define-color variables (highest priority)
        if ($css_content =~ /\@define-color\s+theme_bg_color\s+([^;]+);/i) {
            $bg_color = $self->_parse_css_color_value($1, $css_content);
        }
        elsif ($css_content =~ /\@define-color\s+bg_color\s+([^;]+);/i) {
            $bg_color = $self->_parse_css_color_value($1, $css_content);
        }
        elsif ($css_content =~ /\@define-color\s+window_bg_color\s+([^;]+);/i) {
            $bg_color = $self->_parse_css_color_value($1, $css_content);
        }
        elsif ($css_content =~ /\@define-color\s+base_color\s+([^;]+);/i) {
            $bg_color = $self->_parse_css_color_value($1, $css_content);
        }

        # 2. Look for window background declarations
        elsif ($css_content =~ /window\s*\{[^}]*background(?:-color)?\s*:\s*([^;}]+)/si) {
            $bg_color = $self->_parse_css_color_value($1, $css_content);
        }

        # 3. Look for specific theme patterns
        elsif ($theme_name =~ /breeze/i) {
            if ($theme_name =~ /dark/i) {
                $bg_color = [0.19, 0.20, 0.22];  # Breeze Dark proper color
            } else {
                $bg_color = [0.93, 0.93, 0.93];  # Breeze Light proper color
            }
        }
        elsif ($theme_name =~ /adwaita/i) {
            if ($theme_name =~ /dark/i) {
                $bg_color = [0.24, 0.24, 0.24];  # Adwaita Dark
            } else {
                $bg_color = [0.98, 0.98, 0.98];  # Adwaita Light
            }
        }
        elsif ($theme_name =~ /ambiance/i) {
            $bg_color = [0.26, 0.26, 0.21];  # Ubuntu Ambiance brown
        }
        elsif ($theme_name =~ /mint[-_]?[lxy]/i) {
            if ($theme_name =~ /dark/i) {
                $bg_color = [0.18, 0.20, 0.21];  # Mint Dark themes
            } else {
                $bg_color = [0.96, 0.96, 0.96];  # Mint Light themes
            }
        }

        # 4. Fallback: detect dark vs light theme
        elsif ($css_content =~ /dark/i || $theme_name =~ /dark/i) {
            $bg_color = $default_dark;
        }

        return $bg_color || $default_light;
    }

    sub _parse_css_color {
        my ($self, $color_string) = @_;

        return unless $color_string;

        # Remove quotes and clean up
        $color_string =~ s/["']//g;
        $color_string =~ s/^\s+|\s+$//g;

        # Handle hex colors (#RGB or #RRGGBB)
        if ($color_string =~ /^#?([0-9a-fA-F]{3,6})$/) {
            my $hex = $1;
            if (length($hex) == 3) {
                # Short hex format (#abc -> #aabbcc)
                $hex = join('', map { $_ x 2 } split //, $hex);
            }
            if (length($hex) == 6) {
                my $r = hex(substr($hex, 0, 2)) / 255.0;
                my $g = hex(substr($hex, 2, 2)) / 255.0;
                my $b = hex(substr($hex, 4, 2)) / 255.0;
                return [$r, $g, $b];
            }
        }

        # Handle rgb() and rgba() colors
        elsif ($color_string =~ /rgba?\(\s*([0-9]+)\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*(?:,\s*[0-9.]+)?\s*\)/i) {
            my $r = $1 / 255.0;
            my $g = $2 / 255.0;
            my $b = $3 / 255.0;
            return [$r, $g, $b];
        }

        # Handle @theme_color references (resolve to defaults for now)
        elsif ($color_string =~ /^\@/) {
            # This would need theme color resolution, for now return undef to use fallback
            return undef;
        }

        return undef;
    }

    sub _parse_css_color_value {
        my ($self, $color_value, $css_content) = @_;

        return unless $color_value;

        # Clean up the value
        $color_value =~ s/^\s+|\s+$//g;
        $color_value =~ s/["']//g;

        # Handle @color references
        if ($color_value =~ /^\@([a-zA-Z_][a-zA-Z0-9_-]*)$/) {
            my $var_name = $1;
            # Look up the variable in the CSS
            if ($css_content =~ /\@define-color\s+$var_name\s+([^;]+);/i) {
                return $self->_parse_css_color_value($1, $css_content);
            }
            return undef;
        }

        # Handle hex colors
        if ($color_value =~ /^#?([0-9a-fA-F]{3,6})$/) {
            my $hex = $1;
            if (length($hex) == 3) {
                $hex = join('', map { $_ x 2 } split //, $hex);
            }
            if (length($hex) == 6) {
                my $r = hex(substr($hex, 0, 2)) / 255.0;
                my $g = hex(substr($hex, 2, 2)) / 255.0;
                my $b = hex(substr($hex, 4, 2)) / 255.0;
                return [$r, $g, $b];
            }
        }

        # Handle rgb() and rgba()
        elsif ($color_value =~ /rgba?\(\s*([0-9]+)\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*(?:,\s*[0-9.]+)?\s*\)/i) {
            my $r = $1 / 255.0;
            my $g = $2 / 255.0;
            my $b = $3 / 255.0;
            return [$r, $g, $b];
        }

        # Handle common color names
        elsif ($color_value =~ /^white$/i) {
            return [1.0, 1.0, 1.0];
        }
        elsif ($color_value =~ /^black$/i) {
            return [0.0, 0.0, 0.0];
        }
        elsif ($color_value =~ /^transparent$/i) {
            return undef; # Let it fallback
        }

        return undef;
    }

    sub _create_improved_preview_script {
        my ($self, $theme_name, $theme_path, $output_file, $width, $height) = @_;

        # Extract colors BEFORE generating preview
        my $theme_info = { name => $theme_name, path => $theme_path };
        my $bg_color = $self->_extract_theme_background_color($theme_info);
        my $fg_color = $self->_extract_theme_foreground_color($theme_info);
        my $selected_color = $self->_extract_theme_selected_color($theme_info);
        
        # Convert to hex colors with safety checks
        my $bg_hex = sprintf("#%02x%02x%02x", 
            int(($bg_color->[0] // 0.98) * 255), 
            int(($bg_color->[1] // 0.98) * 255), 
            int(($bg_color->[2] // 0.98) * 255)
        );
        my $fg_hex = sprintf("#%02x%02x%02x", 
            int(($fg_color->[0] // 0.13) * 255), 
            int(($fg_color->[1] // 0.13) * 255), 
            int(($fg_color->[2] // 0.13) * 255)
        );
        my $selected_hex = sprintf("#%02x%02x%02x", 
            int(($selected_color->[0] // 0.33) * 255), 
            int(($selected_color->[1] // 0.40) * 255), 
            int(($selected_color->[2] // 1.0) * 255)
        );

        return qq{#!/usr/bin/perl
            use strict;
            use warnings;
            use Gtk3 -init;
            use Glib 'TRUE', 'FALSE';

            # Suppress GTK warnings
            \$SIG{__WARN__} = sub {
                my \$warning = shift;
                return if \$warning =~ /Theme parsing error/;
                return if \$warning =~ /Unable to locate theme engine/;
                warn \$warning;
            };

            # Apply theme name
            \$ENV{GTK_THEME} = '$theme_name';
            my \$settings = Gtk3::Settings->get_default();
            \$settings->set_property('gtk-theme-name', '$theme_name');

            # Create window with guaranteed size
            my \$window = Gtk3::OffscreenWindow->new();
            \$window->set_size_request($width, $height);

            # Load original theme CSS first
            if (-f '$theme_path/gtk-3.0/gtk.css') {
                my \$theme_css_provider = Gtk3::CssProvider->new();
                eval {
                    \$theme_css_provider->load_from_path('$theme_path/gtk-3.0/gtk.css');
                    my \$screen = Gtk3::Gdk::Screen->get_default();
                    Gtk3::StyleContext->add_provider_for_screen(\$screen, \$theme_css_provider, 600);
                };
                warn "Theme CSS error: \$@" if \$@;
            }

            # Create override CSS to fix sizing issues
            my \$override_css = qq{
            window { 
                background-color: $bg_hex; 
                min-width: ${width}px; 
                min-height: ${height}px; 
            }
            };

            # Apply override CSS with higher priority
            my \$override_provider = Gtk3::CssProvider->new();
            eval {
                \$override_provider->load_from_data(\$override_css);
                my \$screen = Gtk3::Gdk::Screen->get_default();
                Gtk3::StyleContext->add_provider_for_screen(\$screen, \$override_provider, 900);
            };
            if (\$@) {
                warn "Override CSS error: \$@";
            }

            # Main container
            my \$main_box = Gtk3::Box->new('vertical', 8);
            \$main_box->set_margin_left(12);
            \$main_box->set_margin_right(12);
            \$main_box->set_margin_top(12);
            \$main_box->set_margin_bottom(12);

            # Sample widgets grid
            my \$grid = Gtk3::Grid->new();
            \$grid->set_row_spacing(8);
            \$grid->set_column_spacing(8);
            \$grid->set_halign('center');
            \$grid->set_valign('center');

            # Row 1: Entry and combo
            my \$entry = Gtk3::Entry->new();
            \$entry->set_text('Sample text');
            \$entry->set_size_request(120, -1);
            \$grid->attach(\$entry, 0, 0, 1, 1);

            my \$combo = Gtk3::ComboBoxText->new();
            \$combo->append_text('Option 1');
            \$combo->append_text('Option 2');
            \$combo->set_active(0);
            \$combo->set_size_request(100, -1);
            \$grid->attach(\$combo, 1, 0, 1, 1);

            # Row 2: Buttons
            my \$button1 = Gtk3::Button->new_with_label('Normal');
            \$grid->attach(\$button1, 0, 1, 1, 1);

            my \$button2 = Gtk3::Button->new_with_label('Suggested');
            \$button2->get_style_context()->add_class('suggested-action');
            \$grid->attach(\$button2, 1, 1, 1, 1);

            # Row 3: Checkboxes
            my \$check1 = Gtk3::CheckButton->new_with_label('Enabled');
            \$check1->set_active(1);
            \$grid->attach(\$check1, 0, 2, 1, 1);

            my \$check2 = Gtk3::CheckButton->new_with_label('Disabled');
            \$check2->set_sensitive(0);
            \$grid->attach(\$check2, 1, 2, 1, 1);

            # Row 4: Scale
            my \$scale = Gtk3::Scale->new_with_range('horizontal', 0, 100, 1);
            \$scale->set_value(60);
            \$scale->set_draw_value(0);
            \$scale->set_size_request(200, -1);
            \$grid->attach(\$scale, 0, 3, 2, 1);

            \$main_box->pack_start(\$grid, 1, 1, 0);
            \$window->add(\$main_box);
            \$window->show_all();

            # Wait for rendering
            for my \$i (1..15) {
                while (Gtk3::events_pending()) {
                    Gtk3::main_iteration();
                }
                select(undef, undef, undef, 0.05);
            }

            # Capture screenshot at exact size
            my \$pixbuf = \$window->get_pixbuf();
            if (\$pixbuf) {
                # Ensure exact size
                if (\$pixbuf->get_width() != $width || \$pixbuf->get_height() != $height) {
                    \$pixbuf = \$pixbuf->scale_simple($width, $height, 'bilinear');
                }
                \$pixbuf->savev('$output_file', 'png', [], []);
                exit 0;
            } else {
                exit 1;
            }
        };
    }

    sub _extract_theme_foreground_color {
        my ($self, $theme_info) = @_;

        my $theme_path = $theme_info->{path};
        my $css_file = "$theme_path/gtk-3.0/gtk.css";

        # Default colors
        my $default_light_fg = [0.13, 0.13, 0.13];  # Dark gray text
        my $default_dark_fg = [0.87, 0.87, 0.87];   # Light gray text

        return $default_light_fg unless -f $css_file;

        open my $fh, '<', $css_file or return $default_light_fg;
        my $css_content = do { local $/; <$fh> };
        close $fh;

        # Look for foreground color patterns
        if ($css_content =~ /\@define-color\s+theme_fg_color\s+[#@]?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})/i ||
            $css_content =~ /color\s*:\s*[#@]?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})/i) {

            my $hex_color = $1;
            if ($hex_color && length($hex_color) >= 3) {
                if (length($hex_color) == 3) {
                    $hex_color = join('', map { $_ x 2 } split //, $hex_color);
                }
                my $r = hex(substr($hex_color, 0, 2)) / 255.0;
                my $g = hex(substr($hex_color, 2, 2)) / 255.0;
                my $b = hex(substr($hex_color, 4, 2)) / 255.0;
                return [$r, $g, $b];
            }
        }

        # Check if it's a dark theme
        if ($css_content =~ /dark/i || $theme_info->{name} =~ /dark/i) {
            return $default_dark_fg;
        }

        return $default_light_fg;
    }

    sub _extract_theme_selected_color {
        my ($self, $theme_info) = @_;

        my $theme_path = $theme_info->{path};
        my $css_file = "$theme_path/gtk-3.0/gtk.css";

        # Get system selection color as fallback
        my $default_selection = $self->_get_system_selection_color();

        return $default_selection unless -f $css_file;

        open my $fh, '<', $css_file or return $default_selection;
        my $css_content = do { local $/; <$fh> };
        close $fh;

        # Look for selected/accent color patterns
        if ($css_content =~ /\@define-color\s+theme_selected_bg_color\s+[#@]?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})/i ||
            $css_content =~ /suggested-action[^}]*background[^}]*?[#@]?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})/si) {

            my $hex_color = $1;
            if ($hex_color && length($hex_color) >= 3) {
                if (length($hex_color) == 3) {
                    $hex_color = join('', map { $_ x 2 } split //, $hex_color);
                }
                my $r = hex(substr($hex_color, 0, 2)) / 255.0;
                my $g = hex(substr($hex_color, 2, 2)) / 255.0;
                my $b = hex(substr($hex_color, 4, 2)) / 255.0;
                return [$r, $g, $b];
            }
        }

        return $default_selection;
    }

    sub _get_system_selection_color {
        my ($self) = @_;

        # Try to get selection color from current GTK theme
        my $widget = Gtk3::Button->new();
        my $style_context = $widget->get_style_context();
        $style_context->add_class('suggested-action');

        # Get the actual selection/accent color from GTK
        my $bg_color = $style_context->get_background_color('normal');

        # Convert to our RGB array format
        return [$bg_color->red, $bg_color->green, $bg_color->blue];
    }

    sub _create_hybrid_preview {
        my ($self, $theme_name, $theme_path, $output_file, $width, $height) = @_;

        print "Creating enhanced realistic preview for: $theme_name\n";

        # Step 1: Extract comprehensive theme colors and properties
        my $theme_info = { name => $theme_name, path => $theme_path };
        my $theme_colors = $self->_extract_comprehensive_theme_colors($theme_info);

        # Step 2: Check if this is a resource-based theme
        my $css_file = "$theme_path/gtk-3.0/gtk.css";
        my $is_resource_theme = 0;

        if (-f $css_file) {
            open my $fh, '<', $css_file or return 0;
            my $css_content = do { local $/; <$fh> };
            close $fh;
            $is_resource_theme = ($css_content =~ /resource:\/\/.*gtk.*css/i);
        }

        if ($is_resource_theme) {
            print "Resource-based theme detected, using enhanced Cairo rendering\n";
            return $self->_create_enhanced_cairo_preview($theme_colors, $width, $height, $output_file);
        } else {
            print "File-based theme detected, using realistic widget rendering\n";
            return $self->_create_realistic_widget_preview($theme_name, $theme_path, $theme_colors, $width, $height, $output_file);
        }
    }

    sub _create_realistic_widget_preview {
        my ($self, $theme_name, $theme_path, $colors, $width, $height, $output_file) = @_;

        print "Creating realistic widget preview for: $theme_name\n";

        # Create the preview script that will actually apply the theme and render widgets
        my $preview_script = $self->_create_realistic_preview_script($theme_name, $theme_path, $colors, $width, $height, $output_file);

        # Write script to temporary file
        my $script_path = "/tmp/realistic_preview_${$}_" . time() . ".pl";
        open my $fh, '>', $script_path or do {
            print "ERROR: Cannot create preview script: $!\n";
            return $self->_create_enhanced_cairo_preview($colors, $width, $height, $output_file);
        };
        print $fh $preview_script;
        close $fh;
        chmod 0755, $script_path;

        # Execute the script with timeout
        my $success = 0;
        eval {
            local $SIG{ALRM} = sub { die "timeout\n" };
            alarm(15); # 15 second timeout

            my $result = system("timeout 10s perl '$script_path' 2>/dev/null");
            $success = ($result == 0 && -f $output_file && -s $output_file > 1000);

            alarm(0);
        };

        if ($@ || !$success) {
            print "Widget preview generation failed or timed out, using enhanced Cairo fallback\n";
            $success = $self->_create_enhanced_cairo_preview($colors, $width, $height, $output_file);
        }

        # Clean up
        unlink $script_path if -f $script_path;

        return $success;
    }

    sub _create_realistic_preview_script {
        my ($self, $theme_name, $theme_path, $colors, $width, $height, $output_file) = @_;

        # Convert colors to CSS format
        my $bg_hex = sprintf("#%02x%02x%02x", map { int($_ * 255) } @{$colors->{bg_color}});
        my $fg_hex = sprintf("#%02x%02x%02x", map { int($_ * 255) } @{$colors->{fg_color}});
        my $selected_hex = sprintf("#%02x%02x%02x", map { int($_ * 255) } @{$colors->{selected_bg_color}});
        my $border_hex = sprintf("#%02x%02x%02x", map { int($_ * 255) } @{$colors->{border_color}});
        my $button_hex = sprintf("#%02x%02x%02x", map { int($_ * 255) } @{$colors->{button_bg}});
        my $entry_hex = sprintf("#%02x%02x%02x", map { int($_ * 255) } @{$colors->{entry_bg}});

        return qq{#!/usr/bin/perl
    use strict;
    use warnings;
    use Gtk3 -init;
    use Glib 'TRUE', 'FALSE';

    # Suppress warnings
    \$SIG{__WARN__} = sub { return; };

    # Set the theme
    \$ENV{GTK_THEME} = '$theme_name';
    my \$settings = Gtk3::Settings->get_default();
    \$settings->set_property('gtk-theme-name', '$theme_name');

    # Create CSS provider for enhanced styling
    my \$css_provider = Gtk3::CssProvider->new();
    my \$enhanced_css = qq{
        window {
            background: $bg_hex;
            color: $fg_hex;
        }
        entry {
            background: $entry_hex;
            border: 1px solid $border_hex;
            color: $fg_hex;
            border-radius: 3px;
        }
        button {
            background: $button_hex;
            border: 1px solid $border_hex;
            color: $fg_hex;
            border-radius: 3px;
            padding: 4px 8px;
        }
        button:hover {
            background: lighter($button_hex);
        }
        button.suggested-action {
            background: $selected_hex;
            border: 1px solid $selected_hex;
            color: white;
        }
        combobox button {
            background: $button_hex;
            border: 1px solid $border_hex;
        }
        checkbutton check {
            background: $entry_hex;
            border: 1px solid $border_hex;
        }
        checkbutton check:checked {
            background: $selected_hex;
            border: 1px solid $selected_hex;
            color: white;
        }
        progressbar trough {
            background: $entry_hex;
            border: 1px solid $border_hex;
        }
        progressbar progress {
            background: $selected_hex;
        }
        scale trough {
            background: $entry_hex;
            border: 1px solid $border_hex;
        }
        scale highlight {
            background: $selected_hex;
        }
        scale slider {
            background: $button_hex;
            border: 1px solid $border_hex;
            border-radius: 50%;
        }
    };

    \$css_provider->load_from_data(\$enhanced_css);
    my \$screen = Gtk3::Gdk::Screen->get_default();
    Gtk3::StyleContext->add_provider_for_screen(\$screen, \$css_provider, 999);

    # Create offscreen window
    my \$window = Gtk3::OffscreenWindow->new();
    \$window->set_size_request($width, $height);

    # Create main container
    my \$main_box = Gtk3::Box->new('vertical', 8);
    \$main_box->set_margin_left(12);
    \$main_box->set_margin_right(12);
    \$main_box->set_margin_top(12);
    \$main_box->set_margin_bottom(12);

    # Create realistic widget layout
    my \$grid = Gtk3::Grid->new();
    \$grid->set_row_spacing(8);
    \$grid->set_column_spacing(8);
    \$grid->set_halign('center');
    \$grid->set_valign('start');

    # Row 1: Entry and combo
    my \$entry = Gtk3::Entry->new();
    \$entry->set_text('Sample text');
    \$entry->set_size_request(120, 28);
    \$grid->attach(\$entry, 0, 0, 1, 1);

    my \$combo = Gtk3::ComboBoxText->new();
    \$combo->append_text('Option 1');
    \$combo->append_text('Option 2');
    \$combo->set_active(0);
    \$combo->set_size_request(100, 28);
    \$grid->attach(\$combo, 1, 0, 1, 1);

    # Row 2: Buttons
    my \$button1 = Gtk3::Button->new_with_label('Normal');
    \$button1->set_size_request(110, 28);
    \$grid->attach(\$button1, 0, 1, 1, 1);

    my \$button2 = Gtk3::Button->new_with_label('Suggested');
    \$button2->get_style_context()->add_class('suggested-action');
    \$button2->set_size_request(110, 28);
    \$grid->attach(\$button2, 1, 1, 1, 1);

    # Row 3: Checkboxes
    my \$check1 = Gtk3::CheckButton->new_with_label('Enabled');
    \$check1->set_active(1);
    \$grid->attach(\$check1, 0, 2, 1, 1);

    my \$check2 = Gtk3::CheckButton->new_with_label('Disabled');
    \$check2->set_sensitive(0);
    \$grid->attach(\$check2, 1, 2, 1, 1);

    # Row 4: Progress bar
    my \$progress = Gtk3::ProgressBar->new();
    \$progress->set_fraction(0.65);
    \$progress->set_size_request(220, 12);
    \$grid->attach(\$progress, 0, 3, 2, 1);

    # Row 5: Scale
    my \$scale = Gtk3::Scale->new_with_range('horizontal', 0, 100, 1);
    \$scale->set_value(40);
    \$scale->set_draw_value(0);
    \$scale->set_size_request(220, 20);
    \$grid->attach(\$scale, 0, 4, 2, 1);

    \$main_box->pack_start(\$grid, 1, 1, 0);
    \$window->add(\$main_box);
    \$window->show_all();

    # Allow time for theme application and rendering
    for my \$i (1..20) {
        while (Gtk3::events_pending()) {
            Gtk3::main_iteration();
        }
        select(undef, undef, undef, 0.05);
    }

    # Capture the rendered window
    my \$pixbuf = \$window->get_pixbuf();
    if (\$pixbuf && \$pixbuf->get_width() > 0 && \$pixbuf->get_height() > 0) {
        # Scale to exact size if needed
        if (\$pixbuf->get_width() != $width || \$pixbuf->get_height() != $height) {
            \$pixbuf = \$pixbuf->scale_simple($width, $height, 'bilinear');
        }

        # Save the preview
        \$pixbuf->savev('$output_file', 'png', [], []);
        print "Realistic preview saved\\n";
    } else {
        print "Failed to capture window\\n";
        exit 1;
    }

    exit 0;
    };
    }

    sub _create_enhanced_cairo_preview {
        my ($self, $colors, $width, $height, $output_file) = @_;

        print "Creating enhanced Cairo preview with realistic styling\n";

        # Create Cairo surface
        my $surface = Cairo::ImageSurface->create('argb32', $width, $height);
        my $cr = Cairo::Context->create($surface);

        # Fill background
        $cr->save();
        $cr->set_source_rgb(@{$colors->{bg_color}});
        $cr->paint();
        $cr->restore();

        # Draw realistic UI elements
        $self->_draw_realistic_ui_elements($cr, $width, $height, $colors);

        # Save the surface
        $surface->write_to_png($output_file);

        return (-f $output_file && -s $output_file > 100);
    }

    sub _extract_comprehensive_theme_colors {
        my ($self, $theme_info) = @_;

        my $theme_path = $theme_info->{path};
        my $theme_name = $theme_info->{name};
        my $css_file = "$theme_path/gtk-3.0/gtk.css";

        # Initialize with intelligent defaults
        my $colors = {
            bg_color => [0.95, 0.95, 0.95],          # Window background
            fg_color => [0.13, 0.13, 0.13],          # Text color
            base_color => [1.0, 1.0, 1.0],           # Entry/text backgrounds
            text_color => [0.0, 0.0, 0.0],           # Entry text
            selected_bg_color => $self->_extract_theme_selected_color($theme_info),
            selected_fg_color => [1.0, 1.0, 1.0],    # Selection text
            border_color => [0.68, 0.68, 0.68],      # Borders
            button_bg => [0.88, 0.88, 0.88],         # Button background
            button_border => [0.68, 0.68, 0.68],     # Button border
            button_hover => [0.92, 0.92, 0.92],      # Button hover
            entry_bg => [0.98, 0.98, 0.98],          # Entry background
            entry_border => [0.75, 0.75, 0.75],      # Entry border
            headerbar_bg => [0.85, 0.85, 0.85],      # Header bar background
            sidebar_bg => [0.92, 0.92, 0.92],        # Sidebar background
            is_dark_theme => 0,
        };

        # Check if it's a dark theme first
        if ($theme_name =~ /dark|noir|black|night/i) {
            $colors->{is_dark_theme} = 1;
            # Dark theme defaults
            $colors->{bg_color} = [0.24, 0.24, 0.24];
            $colors->{fg_color} = [0.87, 0.87, 0.87];
            $colors->{base_color} = [0.18, 0.18, 0.18];
            $colors->{text_color} = [0.95, 0.95, 0.95];
            $colors->{border_color} = [0.45, 0.45, 0.45];
            $colors->{button_bg} = [0.32, 0.32, 0.32];
            $colors->{button_border} = [0.45, 0.45, 0.45];
            $colors->{button_hover} = [0.38, 0.38, 0.38];
            $colors->{entry_bg} = [0.20, 0.20, 0.20];
            $colors->{entry_border} = [0.40, 0.40, 0.40];
            $colors->{headerbar_bg} = [0.28, 0.28, 0.28];
            $colors->{sidebar_bg} = [0.22, 0.22, 0.22];
        }

        return $colors unless -f $css_file;

        # Read CSS content
        my $css_content = $self->_read_css_with_imports($css_file, "$theme_path/gtk-3.0");
        return $colors if $css_content =~ /resource:\/\/.*gtk.*css/i;

        # Extract colors from CSS
        $self->_parse_theme_colors($css_content, $colors);

        # Apply intelligent color derivations
        $self->_derive_missing_colors($colors);

        print "Extracted colors for $theme_name:\n";
        print "  Background: " . join(", ", map { sprintf("%.2f", $_) } @{$colors->{bg_color}}) . "\n";
        print "  Text: " . join(", ", map { sprintf("%.2f", $_) } @{$colors->{fg_color}}) . "\n";
        print "  Selected: " . join(", ", map { sprintf("%.2f", $_) } @{$colors->{selected_bg_color}}) . "\n";

        return $colors;
    }

    sub _draw_realistic_progressbar {
        my ($self, $cr, $x, $y, $w, $h, $colors, $progress) = @_;

        $cr->save();

        # Progress trough with inset effect
        my $trough_gradient = Cairo::LinearGradient->create($x, $y, $x, $y + $h);
        my @darker_bg = (
            $colors->{entry_bg}->[0] - 0.1 < 0 ? 0 : $colors->{entry_bg}->[0] - 0.1,
            $colors->{entry_bg}->[1] - 0.1 < 0 ? 0 : $colors->{entry_bg}->[1] - 0.1,
            $colors->{entry_bg}->[2] - 0.1 < 0 ? 0 : $colors->{entry_bg}->[2] - 0.1
        );
        $trough_gradient->add_color_stop_rgb(0, @darker_bg);
        $trough_gradient->add_color_stop_rgb(1, @{$colors->{entry_bg}});

        $cr->set_source($trough_gradient);
        $cr->rectangle($x, $y, $w, $h);
        $cr->fill();

        # Trough border
        $cr->set_source_rgb(@{$colors->{border_color}});
        $cr->set_line_width(1);
        $cr->rectangle($x + 0.5, $y + 0.5, $w - 1, $h - 1);
        $cr->stroke();

        # Progress fill with gradient
        my $fill_width = ($w - 4) * $progress;
        if ($fill_width > 2) {
            my $progress_gradient = Cairo::LinearGradient->create($x + 2, $y + 2, $x + 2, $y + $h - 2);
            $progress_gradient->add_color_stop_rgb(0,
                $colors->{selected_bg_color}->[0] + 0.15 > 1 ? 1 : $colors->{selected_bg_color}->[0] + 0.15,
                $colors->{selected_bg_color}->[1] + 0.15 > 1 ? 1 : $colors->{selected_bg_color}->[1] + 0.15,
                $colors->{selected_bg_color}->[2] + 0.15 > 1 ? 1 : $colors->{selected_bg_color}->[2] + 0.15
            );
            $progress_gradient->add_color_stop_rgb(1, @{$colors->{selected_bg_color}});

            $cr->set_source($progress_gradient);
            $cr->rectangle($x + 2, $y + 2, $fill_width, $h - 4);
            $cr->fill();

            # Progress highlight
            $cr->set_source_rgba(1.0, 1.0, 1.0, 0.3);
            $cr->set_line_width(1);
            $cr->rectangle($x + 2.5, $y + 2.5, $fill_width - 1, 1);
            $cr->stroke();
        }

        $cr->restore();
    }

    sub _draw_realistic_ui_elements {
        my ($self, $cr, $width, $height, $colors) = @_;

        my $margin = 12;
        my $spacing = 10;
        my $y = $margin;

        # Calculate element dimensions
        my $element_height = 28;
        my $half_width = ($width / 2) - $margin - 2;

        # Row 1: Entry field and combo box
        if ($y + $element_height < $height - $margin) {
            # Entry field with realistic styling
            $self->_draw_realistic_entry($cr, $margin, $y, $half_width, $element_height, $colors, "Sample text");

            # Combo box
            my $combo_x = $width / 2 + 2;
            $self->_draw_realistic_combo($cr, $combo_x, $y, $half_width, $element_height, $colors, "Option 1");

            $y += $element_height + $spacing;
        }

        # Row 2: Normal and suggested buttons
        if ($y + $element_height < $height - $margin) {
            # Normal button
            $self->_draw_realistic_button($cr, $margin, $y, $half_width, $element_height, $colors, "Normal", 0);

            # Suggested button
            my $button2_x = $width / 2 + 2;
            $self->_draw_realistic_button($cr, $button2_x, $y, $half_width, $element_height, $colors, "Suggested", 1);

            $y += $element_height + $spacing;
        }

        # Row 3: Checkboxes with realistic styling
        if ($y + 20 < $height - $margin) {
            # Enabled checkbox
            $self->_draw_realistic_checkbox($cr, $margin, $y, $colors, "Enabled", 1, 1);

            # Disabled checkbox
            my $check2_x = $width / 2 + 2;
            $self->_draw_realistic_checkbox($cr, $check2_x, $y, $colors, "Disabled", 0, 0);

            $y += 20 + $spacing;
        }

        # Row 4: Progress bar with theme colors
        if ($y + 16 < $height - $margin) {
            $self->_draw_realistic_progressbar($cr, $margin, $y, $width - 2*$margin, 12, $colors, 0.65);
            $y += 16 + $spacing;
        }

        # Row 5: Scale/slider
        if ($y + 20 < $height - $margin) {
            $self->_draw_realistic_scale($cr, $margin, $y, $width - 2*$margin, 20, $colors, 0.4);
        }
    }

    sub _draw_realistic_entry {
        my ($self, $cr, $x, $y, $w, $h, $colors, $text) = @_;

        $cr->save();

        # Draw entry background with subtle gradient
        my $gradient = Cairo::LinearGradient->create($x, $y, $x, $y + $h);
        $gradient->add_color_stop_rgb(0, @{$colors->{entry_bg}});
        my @darker_bg = (
            $colors->{entry_bg}->[0] - 0.02,
            $colors->{entry_bg}->[1] - 0.02,
            $colors->{entry_bg}->[2] - 0.02
        );
        for my $i (0..2) { $darker_bg[$i] = 0 if $darker_bg[$i] < 0; }
        $gradient->add_color_stop_rgb(1, @darker_bg);

        $cr->set_source($gradient);
        $cr->rectangle($x, $y, $w, $h);
        $cr->fill();

        # Draw border with subtle shadow effect
        $cr->set_source_rgb(@{$colors->{entry_border}});
        $cr->set_line_width(1);
        $cr->rectangle($x + 0.5, $y + 0.5, $w - 1, $h - 1);
        $cr->stroke();

        # Inner highlight
        my @highlight = (
            $colors->{entry_bg}->[0] + 0.1,
            $colors->{entry_bg}->[1] + 0.1,
            $colors->{entry_bg}->[2] + 0.1
        );
        for my $i (0..2) { $highlight[$i] = 1 if $highlight[$i] > 1; }
        $cr->set_source_rgba(@highlight, 0.4);
        $cr->set_line_width(1);
        $cr->rectangle($x + 1.5, $y + 1.5, $w - 3, 1);
        $cr->stroke();

        # Entry text
        $cr->set_source_rgb(@{$colors->{text_color}});
        $cr->select_font_face("Sans", 'normal', 'normal');
        $cr->set_font_size(11);
        $cr->move_to($x + 8, $y + $h/2 + 4);
        $cr->show_text($text);

        # Text cursor
        $cr->set_line_width(1);
        my $text_extents = $cr->text_extents($text);
        $cr->move_to($x + 8 + $text_extents->{width} + 2, $y + 6);
        $cr->line_to($x + 8 + $text_extents->{width} + 2, $y + $h - 6);
        $cr->stroke();

        $cr->restore();
    }

    sub _draw_realistic_combo {
        my ($self, $cr, $x, $y, $w, $h, $colors, $text) = @_;

        $cr->save();

        # Button-like background with gradient
        my $gradient = Cairo::LinearGradient->create($x, $y, $x, $y + $h);
        $gradient->add_color_stop_rgb(0, @{$colors->{button_bg}});
        my @darker_bg = (
            $colors->{button_bg}->[0] - 0.05,
            $colors->{button_bg}->[1] - 0.05,
            $colors->{button_bg}->[2] - 0.05
        );
        for my $i (0..2) { $darker_bg[$i] = 0 if $darker_bg[$i] < 0; }
        $gradient->add_color_stop_rgb(1, @darker_bg);

        $cr->set_source($gradient);
        $cr->rectangle($x, $y, $w, $h);
        $cr->fill();

        # Border
        $cr->set_source_rgb(@{$colors->{button_border}});
        $cr->set_line_width(1);
        $cr->rectangle($x + 0.5, $y + 0.5, $w - 1, $h - 1);
        $cr->stroke();

        # Top highlight
        my @highlight = (
            $colors->{button_bg}->[0] + 0.15,
            $colors->{button_bg}->[1] + 0.15,
            $colors->{button_bg}->[2] + 0.15
        );
        for my $i (0..2) { $highlight[$i] = 1 if $highlight[$i] > 1; }
        $cr->set_source_rgba(@highlight, 0.6);
        $cr->set_line_width(1);
        $cr->rectangle($x + 1.5, $y + 1.5, $w - 3, 1);
        $cr->stroke();

        # Combo text
        $cr->set_source_rgb(@{$colors->{fg_color}});
        $cr->move_to($x + 8, $y + $h/2 + 4);
        $cr->show_text($text);

        # Dropdown arrow with proper styling
        my $arrow_x = $x + $w - 20;
        my $arrow_y = $y + $h/2;

        $cr->set_source_rgb(@{$colors->{fg_color}});
        $cr->set_line_width(2);
        $cr->move_to($arrow_x, $arrow_y - 3);
        $cr->line_to($arrow_x + 6, $arrow_y + 3);
        $cr->line_to($arrow_x + 12, $arrow_y - 3);
        $cr->stroke();

        $cr->restore();
    }

    sub _draw_realistic_button {
        my ($self, $cr, $x, $y, $w, $h, $colors, $text, $is_suggested) = @_;

        $cr->save();

        # Choose colors based on button type
        my $bg_color = $is_suggested ? $colors->{selected_bg_color} : $colors->{button_bg};
        my $text_color = $is_suggested ? $colors->{selected_fg_color} : $colors->{fg_color};
        my $border_color = $is_suggested ? $colors->{selected_bg_color} : $colors->{button_border};

        # Create realistic button gradient
        my $gradient = Cairo::LinearGradient->create($x, $y, $x, $y + $h);
        if ($is_suggested) {
            # Suggested button has more vibrant gradient
            $gradient->add_color_stop_rgb(0,
                $bg_color->[0] + 0.1 > 1 ? 1 : $bg_color->[0] + 0.1,
                $bg_color->[1] + 0.1 > 1 ? 1 : $bg_color->[1] + 0.1,
                $bg_color->[2] + 0.1 > 1 ? 1 : $bg_color->[2] + 0.1
            );
            $gradient->add_color_stop_rgb(1, @$bg_color);
        } else {
            # Normal button
            $gradient->add_color_stop_rgb(0, @$bg_color);
            $gradient->add_color_stop_rgb(1,
                $bg_color->[0] - 0.08 < 0 ? 0 : $bg_color->[0] - 0.08,
                $bg_color->[1] - 0.08 < 0 ? 0 : $bg_color->[1] - 0.08,
                $bg_color->[2] - 0.08 < 0 ? 0 : $bg_color->[2] - 0.08
            );
        }

        # Draw button background
        $cr->set_source($gradient);
        $cr->rectangle($x, $y, $w, $h);
        $cr->fill();

        # Draw border
        $cr->set_source_rgb(@$border_color);
        $cr->set_line_width(1);
        $cr->rectangle($x + 0.5, $y + 0.5, $w - 1, $h - 1);
        $cr->stroke();

        # Top highlight for 3D effect
        my @highlight_color = (
            $bg_color->[0] + 0.2 > 1 ? 1 : $bg_color->[0] + 0.2,
            $bg_color->[1] + 0.2 > 1 ? 1 : $bg_color->[1] + 0.2,
            $bg_color->[2] + 0.2 > 1 ? 1 : $bg_color->[2] + 0.2
        );
        $cr->set_source_rgba(@highlight_color, 0.5);
        $cr->set_line_width(1);
        $cr->rectangle($x + 1.5, $y + 1.5, $w - 3, 1);
        $cr->stroke();

        # Button text with proper centering
        $cr->set_source_rgb(@$text_color);
        $cr->select_font_face("Sans", 'normal', 'normal');
        $cr->set_font_size(11);
        my $text_extents = $cr->text_extents($text);
        $cr->move_to($x + ($w - $text_extents->{width})/2, $y + $h/2 + 4);
        $cr->show_text($text);

        $cr->restore();
    }

    sub _draw_realistic_checkbox {
        my ($self, $cr, $x, $y, $colors, $text, $is_checked, $is_enabled) = @_;

        $cr->save();

        my $alpha = $is_enabled ? 1.0 : 0.4;
        my $check_size = 16;

        # Checkbox background
        my $bg_color = $is_enabled ? $colors->{entry_bg} : $colors->{bg_color};
        $cr->set_source_rgba(@$bg_color, $alpha);
        $cr->rectangle($x, $y, $check_size, $check_size);
        $cr->fill();

        # Checkbox border
        $cr->set_source_rgba(@{$colors->{border_color}}, $alpha);
        $cr->set_line_width(1);
        $cr->rectangle($x + 0.5, $y + 0.5, $check_size - 1, $check_size - 1);
        $cr->stroke();

        # Inner highlight for realism
        if ($is_enabled) {
            my @highlight = (
                $bg_color->[0] + 0.1 > 1 ? 1 : $bg_color->[0] + 0.1,
                $bg_color->[1] + 0.1 > 1 ? 1 : $bg_color->[1] + 0.1,
                $bg_color->[2] + 0.1 > 1 ? 1 : $bg_color->[2] + 0.1
            );
            $cr->set_source_rgba(@highlight, 0.3);
            $cr->set_line_width(1);
            $cr->rectangle($x + 1.5, $y + 1.5, $check_size - 3, 1);
            $cr->stroke();
        }

        # Checkmark
        if ($is_checked) {
            $cr->set_source_rgba(@{$colors->{selected_bg_color}}, $alpha);
            $cr->set_line_width(2.5);
            $cr->move_to($x + 3, $y + 8);
            $cr->line_to($x + 7, $y + 12);
            $cr->line_to($x + 13, $y + 4);
            $cr->stroke();
        }

        # Label
        $cr->set_source_rgba(@{$colors->{fg_color}}, $alpha);
        $cr->select_font_face("Sans", 'normal', 'normal');
        $cr->set_font_size(10);
        $cr->move_to($x + $check_size + 6, $y + 12);
        $cr->show_text($text);

        $cr->restore();
    }

    sub _parse_theme_colors {
        my ($self, $css_content, $colors) = @_;

        # Color variable mappings
        my %color_vars = (
            'theme_bg_color' => 'bg_color',
            'bg_color' => 'bg_color',
            'window_bg_color' => 'bg_color',
            'theme_fg_color' => 'fg_color',
            'fg_color' => 'fg_color',
            'theme_base_color' => 'base_color',
            'base_color' => 'base_color',
            'theme_text_color' => 'text_color',
            'text_color' => 'text_color',
            'theme_selected_bg_color' => 'selected_bg_color',
            'selected_bg_color' => 'selected_bg_color',
            'theme_selected_fg_color' => 'selected_fg_color',
            'selected_fg_color' => 'selected_fg_color',
            'borders' => 'border_color',
            'border_color' => 'border_color',
            'theme_unfocused_bg_color' => 'sidebar_bg',
            'sidebar_bg_color' => 'sidebar_bg',
            'headerbar_bg_color' => 'headerbar_bg',
            'toolbar_bg_color' => 'headerbar_bg',
        );

        # Parse @define-color variables
        foreach my $var_name (keys %color_vars) {
            my $color_key = $color_vars{$var_name};
            if ($css_content =~ /\@define-color\s+$var_name\s+([^;]+);/i) {
                my $color_value = $1;
                my $parsed_color = $self->_parse_css_color_value($color_value, $css_content);
                if ($parsed_color) {
                    $colors->{$color_key} = $parsed_color;
                    print "  Found $var_name -> $color_key\n";
                }
            }
        }

        # Parse specific selectors for additional colors
        my %selector_patterns = (
            'button' => 'button_bg',
            'entry' => 'entry_bg',
            'headerbar' => 'headerbar_bg',
            'window\.background' => 'bg_color',
            '\.sidebar' => 'sidebar_bg',
        );

        foreach my $selector (keys %selector_patterns) {
            my $color_key = $selector_patterns{$selector};
            if ($css_content =~ /$selector[^}]*\{([^}]+)\}/si) {
                my $rule_content = $1;
                if ($rule_content =~ /background(?:-color)?\s*:\s*([^;}]+)/i) {
                    my $color_value = $1;
                    $color_value =~ s/\s+$//;
                    my $parsed_color = $self->_parse_css_color_value($color_value, $css_content);
                    if ($parsed_color) {
                        $colors->{$color_key} = $parsed_color;
                        print "  Found $selector background -> $color_key\n";
                    }
                }
            }
        }

        # Check for dark theme indicators in CSS
        if ($css_content =~ /dark/i ||
            ($colors->{bg_color}->[0] + $colors->{bg_color}->[1] + $colors->{bg_color}->[2]) / 3 < 0.5) {
            $colors->{is_dark_theme} = 1;
        }
    }

    sub _derive_missing_colors {
        my ($self, $colors) = @_;

        # Derive button colors from background
        unless ($colors->{button_bg}) {
            if ($colors->{is_dark_theme}) {
                $colors->{button_bg} = [
                    $colors->{bg_color}->[0] + 0.08,
                    $colors->{bg_color}->[1] + 0.08,
                    $colors->{bg_color}->[2] + 0.08
                ];
            } else {
                $colors->{button_bg} = [
                    $colors->{bg_color}->[0] - 0.07,
                    $colors->{bg_color}->[1] - 0.07,
                    $colors->{bg_color}->[2] - 0.07
                ];
            }
            # Clamp values
            for my $i (0..2) {
                $colors->{button_bg}->[$i] = 0.0 if $colors->{button_bg}->[$i] < 0.0;
                $colors->{button_bg}->[$i] = 1.0 if $colors->{button_bg}->[$i] > 1.0;
            }
        }

        # Derive entry background
        unless ($colors->{entry_bg}) {
            if ($colors->{is_dark_theme}) {
                $colors->{entry_bg} = [
                    $colors->{bg_color}->[0] - 0.04,
                    $colors->{bg_color}->[1] - 0.04,
                    $colors->{bg_color}->[2] - 0.04
                ];
            } else {
                $colors->{entry_bg} = [
                    $colors->{base_color}->[0],
                    $colors->{base_color}->[1],
                    $colors->{base_color}->[2]
                ];
            }
        }

        # Derive border colors
        unless ($colors->{border_color}) {
            $colors->{border_color} = [
                $colors->{bg_color}->[0] - 0.25,
                $colors->{bg_color}->[1] - 0.25,
                $colors->{bg_color}->[2] - 0.25
            ];
            for my $i (0..2) {
                $colors->{border_color}->[$i] = 0.0 if $colors->{border_color}->[$i] < 0.0;
            }
        }

        # Derive button border
        $colors->{button_border} = $colors->{border_color};

        # Derive entry border
        $colors->{entry_border} = [
            $colors->{border_color}->[0] + 0.1,
            $colors->{border_color}->[1] + 0.1,
            $colors->{border_color}->[2] + 0.1
        ];

        # Derive hover colors
        $colors->{button_hover} = [
            $colors->{button_bg}->[0] + ($colors->{is_dark_theme} ? 0.05 : -0.03),
            $colors->{button_bg}->[1] + ($colors->{is_dark_theme} ? 0.05 : -0.03),
            $colors->{button_bg}->[2] + ($colors->{is_dark_theme} ? 0.05 : -0.03)
        ];

        # Derive sidebar/headerbar if missing
        unless ($colors->{sidebar_bg}) {
            $colors->{sidebar_bg} = [
                $colors->{bg_color}->[0] + ($colors->{is_dark_theme} ? -0.02 : 0.02),
                $colors->{bg_color}->[1] + ($colors->{is_dark_theme} ? -0.02 : 0.02),
                $colors->{bg_color}->[2] + ($colors->{is_dark_theme} ? -0.02 : 0.02)
            ];
        }

        unless ($colors->{headerbar_bg}) {
            $colors->{headerbar_bg} = [
                $colors->{bg_color}->[0] + ($colors->{is_dark_theme} ? 0.04 : -0.05),
                $colors->{bg_color}->[1] + ($colors->{is_dark_theme} ? 0.04 : -0.05),
                $colors->{bg_color}->[2] + ($colors->{is_dark_theme} ? 0.04 : -0.05)
            ];
        }

        # Clamp all derived colors
        foreach my $color_key (keys %$colors) {
            next unless ref($colors->{$color_key}) eq 'ARRAY';
            for my $i (0..2) {
                $colors->{$color_key}->[$i] = 0.0 if $colors->{$color_key}->[$i] < 0.0;
                $colors->{$color_key}->[$i] = 1.0 if $colors->{$color_key}->[$i] > 1.0;
            }
        }
    }

    sub _generate_normal_gtk_widgets {
        my ($self, $theme_name, $theme_path, $output_file, $width, $height) = @_;

        # Use the existing working GTK script
        my $script = $self->_create_improved_preview_script($theme_name, $theme_path, $output_file, $width, $height);

        # Write script to temporary file
        my $script_path = "/tmp/normal_widgets_${$}_" . time() . ".pl";
        open my $fh, '>', $script_path or return 0;
        print $fh $script;
        close $fh;
        chmod 0755, $script_path;

        # Run the script with timeout
        my $result = system("timeout 30s perl '$script_path' 2>/dev/null");
        unlink $script_path;

        # Check if output file was created successfully
        my $success = ($result == 0 && -f $output_file && -s $output_file > 1000);

        return $success;
    }

    sub _generate_transparent_gtk_widgets {
        my ($self, $theme_name, $theme_path, $output_file, $width, $height) = @_;

            my $script = $self->_create_transparent_widget_script($theme_name, $theme_path, $output_file, $width, $height);

            # Write script to temporary file
            my $script_path = "/tmp/transparent_widgets_${$}_" . time() . ".pl";
            open my $fh, '>', $script_path or return 0;
            print $fh $script;
            close $fh;
            chmod 0755, $script_path;

            # Run the script with timeout
            my $result = system("timeout 30s perl '$script_path' 2>/dev/null");
            unlink $script_path;

            # Check if output file was created successfully
            my $success = ($result == 0 && -f $output_file && -s $output_file > 1000);

            return $success;
        }

        sub _create_transparent_widget_script {
        my ($self, $theme_name, $theme_path, $output_file, $width, $height) = @_;

        return qq{#!/usr/bin/perl
        use strict;
        use warnings;
        use Gtk3 -init;
        use Glib 'TRUE', 'FALSE';

        # Suppress GTK warnings
        \$SIG{__WARN__} = sub {
            my \$warning = shift;
            return if \$warning =~ /Theme parsing error/;
            return if \$warning =~ /Unable to locate theme engine/;
            warn \$warning;
        };

        # Apply theme
        \$ENV{GTK_THEME} = '$theme_name';
        my \$settings = Gtk3::Settings->get_default();
        \$settings->set_property('gtk-theme-name', '$theme_name');

        # Load theme CSS if available
        if (-f '$theme_path/gtk-3.0/gtk.css') {
            my \$css_provider = Gtk3::CssProvider->new();
            eval {
                \$css_provider->load_from_path('$theme_path/gtk-3.0/gtk.css');
                my \$screen = Gtk3::Gdk::Screen->get_default();
                Gtk3::StyleContext->add_provider_for_screen(
                    \$screen, \$css_provider, 800
                );
            };
        }

        # Create window with TRANSPARENT background
        my \$window = Gtk3::OffscreenWindow->new();
        \$window->set_size_request($width, $height);

        # Make window background transparent using CSS
        my \$transparent_css = '
        window {
            background-color: transparent;
            background-image: none;
        }
        ';

        my \$transparent_provider = Gtk3::CssProvider->new();
        \$transparent_provider->load_from_data(\$transparent_css);
        my \$screen = Gtk3::Gdk::Screen->get_default();
        Gtk3::StyleContext->add_provider_for_screen(\$screen, \$transparent_provider, 999);

        # Main container
        my \$main_box = Gtk3::Box->new('vertical', 8);
        \$main_box->set_margin_left(12);
        \$main_box->set_margin_right(12);
        \$main_box->set_margin_top(12);
        \$main_box->set_margin_bottom(12);

        # Sample widgets grid
        my \$grid = Gtk3::Grid->new();
        \$grid->set_row_spacing(8);
        \$grid->set_column_spacing(8);
        \$grid->set_halign('center');
        \$grid->set_valign('center');

        # Row 1: Entry and combo
        my \$entry = Gtk3::Entry->new();
        \$entry->set_text('Sample text');
        \$entry->set_size_request(120, -1);
        \$grid->attach(\$entry, 0, 0, 1, 1);

        my \$combo = Gtk3::ComboBoxText->new();
        \$combo->append_text('Option 1');
        \$combo->append_text('Option 2');
        \$combo->set_active(0);
        \$combo->set_size_request(100, -1);
        \$grid->attach(\$combo, 1, 0, 1, 1);

        # Row 2: Buttons
        my \$button1 = Gtk3::Button->new_with_label('Normal');
        \$grid->attach(\$button1, 0, 1, 1, 1);

        my \$button2 = Gtk3::Button->new_with_label('Suggested');
        \$button2->get_style_context()->add_class('suggested-action');
        \$grid->attach(\$button2, 1, 1, 1, 1);

        # Row 3: Checkboxes and radio buttons
        my \$check1 = Gtk3::CheckButton->new_with_label('Enabled');
        \$check1->set_active(1);
        \$grid->attach(\$check1, 0, 2, 1, 1);

        my \$radio1 = Gtk3::RadioButton->new_with_label(undef, 'Radio');
        \$radio1->set_active(1);
        \$grid->attach(\$radio1, 1, 2, 1, 1);

        # Row 4: Scale
        my \$scale = Gtk3::Scale->new_with_range('horizontal', 0, 100, 1);
        \$scale->set_value(60);
        \$scale->set_draw_value(0);
        \$scale->set_size_request(200, -1);
        \$grid->attach(\$scale, 0, 3, 2, 1);

        \$main_box->pack_start(\$grid, 1, 1, 0);
        \$window->add(\$main_box);
        \$window->show_all();

        # Wait for rendering
        for my \$i (1..15) {
            while (Gtk3::events_pending()) {
                Gtk3::main_iteration();
            }
            select(undef, undef, undef, 0.05);
        }

        # Capture screenshot at exact size
        my \$pixbuf = \$window->get_pixbuf();
        if (\$pixbuf) {
            # Ensure exact size
            if (\$pixbuf->get_width() != $width || \$pixbuf->get_height() != $height) {
                \$pixbuf = \$pixbuf->scale_simple($width, $height, 'bilinear');
            }
            \$pixbuf->savev('$output_file', 'png', [], []);
            exit 0;
        } else {
            exit 1;
        }
        };
    }

    sub _create_cairo_preview {
        my ($self, $theme_info, $width, $height, $output_file) = @_;

        # Extract theme colors and style hints
        my $bg_color = $self->_extract_theme_background_color($theme_info);
        my $fg_color = $self->_extract_theme_foreground_color($theme_info);
        my $selected_color = $self->_extract_theme_selected_color($theme_info);
        my $is_flat_theme = $self->_detect_flat_theme($theme_info);

        # Create Cairo surface with exact dimensions
        my $surface = Cairo::ImageSurface->create('argb32', $width, $height);
        my $cr = Cairo::Context->create($surface);

        # Fill entire background with theme color
        $cr->set_source_rgb(@$bg_color);
        $cr->rectangle(0, 0, $width, $height);
        $cr->fill();

        # Helper functions
        my $rounded_rect = sub {
            my ($x, $y, $w, $h, $radius) = @_;
            if ($radius <= 0) {
                $cr->rectangle($x, $y, $w, $h);
                return;
            }
            $cr->move_to($x + $radius, $y);
            $cr->arc($x + $w - $radius, $y + $radius, $radius, -3.14159/2, 0);
            $cr->arc($x + $w - $radius, $y + $h - $radius, $radius, 0, 3.14159/2);
            $cr->arc($x + $radius, $y + $h - $radius, $radius, 3.14159/2, 3.14159);
            $cr->arc($x + $radius, $y + $radius, $radius, 3.14159, -3.14159/2);
            $cr->close_path();
        };

        my $draw_button = sub {
            my ($x, $y, $w, $h, $text, $is_suggested) = @_;

            if ($is_flat_theme) {
                # Flat button style (like Mint-L)
                my $corner = 2;
                if ($is_suggested) {
                    $cr->set_source_rgb(@$selected_color);
                } else {
                    $cr->set_source_rgba($bg_color->[0] + 0.1, $bg_color->[1] + 0.1, $bg_color->[2] + 0.1, 1.0);
                }
                $rounded_rect->($x, $y, $w, $h, $corner);
                $cr->fill();

                # Flat border
                $cr->set_source_rgba($fg_color->[0], $fg_color->[1], $fg_color->[2], 0.2);
                $cr->set_line_width(1);
                $rounded_rect->($x, $y, $w, $h, $corner);
                $cr->stroke();
            } else {
                # 3D button style with gradients
                my $corner = 6;

                # Shadow
                $cr->set_source_rgba(0, 0, 0, 0.15);
                $rounded_rect->($x + 1, $y + 2, $w, $h, $corner);
                $cr->fill();

                # Gradient background
                my $gradient = Cairo::LinearGradient->create($x, $y, $x, $y + $h);
                if ($is_suggested) {
                    my $light = [$selected_color->[0] + 0.1, $selected_color->[1] + 0.1, $selected_color->[2] + 0.1];
                    my $dark = [$selected_color->[0] - 0.1, $selected_color->[1] - 0.1, $selected_color->[2] - 0.1];
                    # Clamp values
                    for my $i (0..2) {
                        $light->[$i] = 1.0 if $light->[$i] > 1.0;
                        $dark->[$i] = 0.0 if $dark->[$i] < 0.0;
                    }
                    $gradient->add_color_stop_rgb(0, @$light);
                    $gradient->add_color_stop_rgb(1, @$dark);
                } else {
                    $gradient->add_color_stop_rgb(0, 0.98, 0.98, 0.98);
                    $gradient->add_color_stop_rgb(1, 0.90, 0.90, 0.90);
                }
                $cr->set_source($gradient);
                $rounded_rect->($x, $y, $w, $h, $corner);
                $cr->fill();

                # Border
                $cr->set_source_rgba($fg_color->[0], $fg_color->[1], $fg_color->[2], 0.4);
                $cr->set_line_width(1);
                $rounded_rect->($x, $y, $w, $h, $corner);
                $cr->stroke();
            }

            # Button text
            if ($is_suggested && $is_flat_theme) {
                $cr->set_source_rgb(1.0, 1.0, 1.0);
            } elsif ($is_suggested) {
                $cr->set_source_rgb(1.0, 1.0, 1.0);
            } else {
                $cr->set_source_rgb(@$fg_color);
            }

            # Center text
            my $text_extents = $cr->text_extents($text);
            my $text_x = $x + ($w - $text_extents->{width}) / 2;
            my $text_y = $y + ($h + $text_extents->{height}) / 2;
            $cr->move_to($text_x, $text_y);
            $cr->show_text($text);
        };

        # Set up layout
        my $margin = 16;
        my $col1_x = $margin;
        my $col2_x = $width / 2 + 10;
        my $col3_x = $width - 80 - $margin;
        my $current_y = $margin;
        my $widget_spacing = 12;

        # Set font
        $cr->select_font_face("Sans", 'normal', 'normal');
        $cr->set_font_size(11);

        # Row 1: Entry field and Combo box
        my $row_height = 30;

        # Entry field
        my $entry_w = 120;
        $cr->set_source_rgb(1.0, 1.0, 1.0);
        $rounded_rect->($col1_x, $current_y, $entry_w, $row_height, $is_flat_theme ? 2 : 4);
        $cr->fill();

        $cr->set_source_rgba($fg_color->[0], $fg_color->[1], $fg_color->[2], 0.3);
        $cr->set_line_width(1);
        $rounded_rect->($col1_x, $current_y, $entry_w, $row_height, $is_flat_theme ? 2 : 4);
        $cr->stroke();

        # Entry text with selection
        $cr->set_source_rgb(@$selected_color);
        $cr->rectangle($col1_x + 6, $current_y + 6, 70, 18);
        $cr->fill();

        $cr->set_source_rgb(1.0, 1.0, 1.0);
        $cr->move_to($col1_x + 8, $current_y + 19);
        $cr->show_text("Sample text");

        # Combo box
        my $combo_w = 100;
        $cr->set_source_rgb(0.96, 0.96, 0.96);
        $rounded_rect->($col2_x, $current_y, $combo_w, $row_height, $is_flat_theme ? 2 : 4);
        $cr->fill();

        $cr->set_source_rgba($fg_color->[0], $fg_color->[1], $fg_color->[2], 0.3);
        $cr->set_line_width(1);
        $rounded_rect->($col2_x, $current_y, $combo_w, $row_height, $is_flat_theme ? 2 : 4);
        $cr->stroke();

        $cr->set_source_rgb(@$fg_color);
        $cr->move_to($col2_x + 8, $current_y + 19);
        $cr->show_text("Option 1");

        # Dropdown arrow
        $cr->set_source_rgba($fg_color->[0], $fg_color->[1], $fg_color->[2], 0.7);
        $cr->move_to($col2_x + $combo_w - 18, $current_y + 11);
        $cr->line_to($col2_x + $combo_w - 13, $current_y + 17);
        $cr->line_to($col2_x + $combo_w - 8, $current_y + 11);
        $cr->set_line_width(2);
        $cr->stroke();
        $cr->set_line_width(1);

        # Scrollbar (vertical)
        my $scrollbar_w = 12;
        my $scrollbar_h = 80;

        # Scrollbar track
        $cr->set_source_rgba($bg_color->[0] - 0.1, $bg_color->[1] - 0.1, $bg_color->[2] - 0.1, 1.0);
        $rounded_rect->($col3_x, $current_y, $scrollbar_w, $scrollbar_h, $is_flat_theme ? 0 : 6);
        $cr->fill();

        # Scrollbar thumb
        my $thumb_h = 25;
        my $thumb_y = $current_y + 15;
        $cr->set_source_rgba($fg_color->[0], $fg_color->[1], $fg_color->[2], 0.6);
        $rounded_rect->($col3_x + 2, $thumb_y, $scrollbar_w - 4, $thumb_h, $is_flat_theme ? 0 : 3);
        $cr->fill();

        $current_y += $row_height + $widget_spacing;

        # Row 2: Buttons
        $draw_button->($col1_x, $current_y, 80, 32, "Normal", 0);
        $draw_button->($col2_x, $current_y, 90, 32, "Suggested", 1);

        $current_y += 32 + $widget_spacing;

        # Row 3: Radio buttons and Checkboxes
        my $radio_size = 16;
        my $checkbox_size = 16;

        # Radio button (selected)
        $cr->set_source_rgb(1.0, 1.0, 1.0);
        $cr->arc($col1_x + $radio_size/2, $current_y + $radio_size/2, $radio_size/2, 0, 2 * 3.14159);
        $cr->fill();

        $cr->set_source_rgba($fg_color->[0], $fg_color->[1], $fg_color->[2], 0.4);
        $cr->set_line_width(1);
        $cr->arc($col1_x + $radio_size/2, $current_y + $radio_size/2, $radio_size/2, 0, 2 * 3.14159);
        $cr->stroke();

        # Radio button inner dot
        $cr->set_source_rgb(@$selected_color);
        $cr->arc($col1_x + $radio_size/2, $current_y + $radio_size/2, $radio_size/4, 0, 2 * 3.14159);
        $cr->fill();

        # Radio button label
        $cr->set_source_rgb(@$fg_color);
        $cr->move_to($col1_x + $radio_size + 6, $current_y + 13);
        $cr->show_text("Radio");

        # Checkbox (checked)
        $cr->set_source_rgb(1.0, 1.0, 1.0);
        $rounded_rect->($col2_x, $current_y, $checkbox_size, $checkbox_size, $is_flat_theme ? 1 : 3);
        $cr->fill();

        $cr->set_source_rgba($fg_color->[0], $fg_color->[1], $fg_color->[2], 0.4);
        $cr->set_line_width(1);
        $rounded_rect->($col2_x, $current_y, $checkbox_size, $checkbox_size, $is_flat_theme ? 1 : 3);
        $cr->stroke();

        # Checkmark
        $cr->set_source_rgb(@$selected_color);
        $cr->set_line_width(2);
        $cr->move_to($col2_x + 3, $current_y + 8);
        $cr->line_to($col2_x + 7, $current_y + 12);
        $cr->line_to($col2_x + 13, $current_y + 4);
        $cr->stroke();
        $cr->set_line_width(1);

        # Checkbox label
        $cr->set_source_rgb(@$fg_color);
        $cr->move_to($col2_x + $checkbox_size + 6, $current_y + 13);
        $cr->show_text("Enabled");

        $current_y += 20 + $widget_spacing;

        # Row 4: Progress bar/Scale - theme-aware styling
        my $scale_width = $width - (2 * $margin);
        my $scale_height = $is_flat_theme ? 4 : 6;

        # Scale track
        $cr->set_source_rgba($bg_color->[0] - 0.15, $bg_color->[1] - 0.15, $bg_color->[2] - 0.15, 1.0);
        $rounded_rect->($col1_x, $current_y + 8, $scale_width, $scale_height, $is_flat_theme ? 0 : 3);
        $cr->fill();

        # Scale progress (60%)
        my $progress_width = $scale_width * 0.6;
        $cr->set_source_rgb(@$selected_color);
        $rounded_rect->($col1_x, $current_y + 8, $progress_width, $scale_height, $is_flat_theme ? 0 : 3);
        $cr->fill();

        # Scale handle - different styles for flat vs 3D themes
        my $handle_x = $col1_x + $progress_width - 8;

        if ($is_flat_theme) {
            # Flat square handle
            $cr->set_source_rgb(1.0, 1.0, 1.0);
            $cr->rectangle($handle_x + 4, $current_y + 4, 8, 16);
            $cr->fill();

            $cr->set_source_rgba($fg_color->[0], $fg_color->[1], $fg_color->[2], 0.6);
            $cr->set_line_width(1);
            $cr->rectangle($handle_x + 4, $current_y + 4, 8, 16);
            $cr->stroke();
        } else {
            # Round 3D handle
            my $handle_size = 14;

            # Handle shadow
            $cr->set_source_rgba(0, 0, 0, 0.2);
            $cr->arc($handle_x + 8, $current_y + 13, $handle_size/2, 0, 2 * 3.14159);
            $cr->fill();

            # Handle gradient
            my $handle_grad = Cairo::LinearGradient->create($handle_x, $current_y + 3, $handle_x, $current_y + 19);
            $handle_grad->add_color_stop_rgb(0, 1.0, 1.0, 1.0);
            $handle_grad->add_color_stop_rgb(1, 0.92, 0.92, 0.92);
            $cr->set_source($handle_grad);
            $cr->arc($handle_x + 7, $current_y + 11, $handle_size/2, 0, 2 * 3.14159);
            $cr->fill();

            # Handle border
            $cr->set_source_rgba($fg_color->[0], $fg_color->[1], $fg_color->[2], 0.3);
            $cr->set_line_width(1);
            $cr->arc($handle_x + 7, $current_y + 11, $handle_size/2, 0, 2 * 3.14159);
            $cr->stroke();
        }

        # Save to PNG
        $surface->write_to_png($output_file);

        return 1;
    }

    sub _detect_flat_theme {
        my ($self, $theme_info) = @_;

        my $theme_name = $theme_info->{name};
        my $theme_path = $theme_info->{path};
        my $css_file = "$theme_path/gtk-3.0/gtk.css";

        # Check theme name patterns
        return 1 if $theme_name =~ /mint-?[lyx]/i;  # Mint-L, Mint-X, Mint-Y are flat
        return 1 if $theme_name =~ /flat|material|paper/i;

        # Check CSS for flat indicators
        if (-f $css_file) {
            open my $fh, '<', $css_file or return 0;
            my $css_content = do { local $/; <$fh> };
            close $fh;

            # Look for flat design indicators in CSS
            return 1 if $css_content =~ /border-radius\s*:\s*[01]px/i;  # Very small border radius
            return 1 if $css_content =~ /box-shadow\s*:\s*none/i;       # No shadows
            return 1 if $css_content =~ /gradient.*none/i;              # No gradients
        }

        return 0;  # Default to 3D styling
    }

    sub _extract_theme_border_color {
        my ($self, $theme_info) = @_;

        my $theme_path = $theme_info->{path};
        my $css_file = "$theme_path/gtk-3.0/gtk.css";

        # Default border colors
        my $default_light_border = [0.8, 0.8, 0.8];  # Light gray border
        my $default_dark_border = [0.4, 0.4, 0.4];   # Dark gray border

        return $default_light_border unless -f $css_file;

        open my $fh, '<', $css_file or return $default_light_border;
        my $css_content = do { local $/; <$fh> };
        close $fh;

        # Look for border color patterns
        if ($css_content =~ /\@define-color\s+borders\s+[#@]?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})/i ||
            $css_content =~ /border-color\s*:\s*[#@]?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})/i) {

            my $hex_color = $1;
            if ($hex_color && length($hex_color) >= 3) {
                if (length($hex_color) == 3) {
                    $hex_color = join('', map { $_ x 2 } split //, $hex_color);
                }
                my $r = hex(substr($hex_color, 0, 2)) / 255.0;
                my $g = hex(substr($hex_color, 2, 2)) / 255.0;
                my $b = hex(substr($hex_color, 4, 2)) / 255.0;
                return [$r, $g, $b];
            }
        }

        # Check if it's a dark theme
        if ($css_content =~ /dark/i || $theme_info->{name} =~ /dark/i) {
            return $default_dark_border;
        }

        return $default_light_border;
    }

    sub _create_theme_widget {
        my ($self, $theme_info, $size) = @_;

        print "DEBUG: Creating theme widget for: " . $theme_info->{name} . "\n";

        # Create frame with inset shadow (like backgrounds manager)
        my $frame = Gtk3::Frame->new();
        $frame->set_shadow_type('in');

        # Create vertical box container
        my $box = Gtk3::Box->new('vertical', 6);
        $box->set_margin_left(6);
        $box->set_margin_right(6);
        $box->set_margin_top(6);
        $box->set_margin_bottom(6);

        my $preview_widget = $self->_create_gtk_preview($theme_info, $size);
        if (!$preview_widget) {
            print "ERROR: _create_gtk_preview returned undef for " . $theme_info->{name} . "\n";
            my $placeholder_pixbuf = $self->_create_placeholder_pixbuf($size, int($size * 0.75));
            $preview_widget = Gtk3::Image->new_from_pixbuf($placeholder_pixbuf);
        }

        # Set size and add to container
        $preview_widget->set_size_request($size, int($size * 0.75));
        $box->pack_start($preview_widget, 1, 1, 0);

        # Create theme name label
        my $theme_name = $theme_info->{display_name} || $theme_info->{name};
        my $label = Gtk3::Label->new($theme_name);
        $label->set_ellipsize('middle');
        $label->set_max_width_chars(15);

        $box->pack_start($label, 0, 0, 0);
        $frame->add($box);

        # Store references - use frame as key like backgrounds manager
        $self->theme_paths->{$frame + 0} = $theme_info;
        $self->theme_widgets->{$frame + 0} = $preview_widget;

        print "DEBUG: Successfully created theme widget for: " . $theme_info->{name} . "\n";
        return $frame;
    }

    sub _create_placeholder_pixbuf {
        my ($self, $width, $height) = @_;

        # Create a simple placeholder pixbuf
        my $surface = Cairo::ImageSurface->create('argb32', $width, $height);
        my $cr = Cairo::Context->create($surface);

        # Draw empty background (white/light gray)
        $cr->save();
        $cr->set_source_rgb(0.98, 0.98, 0.98);
        $cr->rectangle(0, 0, $width, $height);
        $cr->fill();
        $cr->restore();

        # Convert Cairo surface to GdkPixbuf
        $surface->write_to_png("/tmp/placeholder.png");
        my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file("/tmp/placeholder.png");
        unlink("/tmp/placeholder.png");

        return $pixbuf;
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

                    # Load new theme preview asynchronously
                    $self->_generate_theme_preview_fast($theme_info, $frame);
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

    sub _set_gtk_theme {
        my ($self, $child) = @_;

        my $frame = $child->get_child();  # FlowBoxChild -> Frame
        my $theme_info = $self->theme_paths->{$frame + 0};

        return unless $theme_info;

        my $theme_name = $theme_info->{name};
        print "Setting GTK theme: $theme_name\n";

        # Verify the theme exists and has GTK files
        my $gtk3_dir = $theme_info->{path} . "/gtk-3.0";
        my $gtk2_dir = $theme_info->{path} . "/gtk-2.0";

        unless (-d $gtk3_dir || -d $gtk2_dir) {
            my $dialog = Gtk3::MessageDialog->new(
                $self->window,
                'modal',
                'error',
                'ok',
                "Error: Theme '$theme_name' does not contain GTK files."
            );
            $dialog->run();
            $dialog->destroy();
            return;
        }

        # Apply the GTK theme
        print "Applying GTK theme: $theme_name\n";
        system("gsettings set org.cinnamon.desktop.interface gtk-theme '$theme_name'");

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

        # Get the current GTK theme
        my $gtk_theme = `gsettings get org.cinnamon.desktop.interface gtk-theme 2>/dev/null`;
        chomp $gtk_theme if $gtk_theme;
        $gtk_theme =~ s/^'(.*)'$/$1/ if $gtk_theme;

        $self->current_theme($gtk_theme || 'Unknown');
        print "Current GTK theme: " . $self->current_theme . "\n";
    }

    sub _init_config_system {
        my $self = shift;

        # Create config directory structure
        my $config_dir = $ENV{HOME} . '/.local/share/cinnamon-application-themes-manager/config';

        unless (-d $config_dir) {
            system("mkdir -p '$config_dir'");
            print "Created config directory: $config_dir\n";
        }
    }

    sub _get_config_file_path {
        my $self = shift;
        return $ENV{HOME} . '/.local/share/cinnamon-application-themes-manager/config/settings.json';
    }

    sub _load_config {
        my $self = shift;

        my $config_file = $self->_get_config_file_path();
        my $config = {
            preview_size => 450,
            custom_directories => [],
            last_selected_directory => undef,
            theme_backups => [],
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
                    if ($config->{preview_size} < 40 || $config->{preview_size} > 450) {
                        print "Invalid preview size in config, using default\n";
                        $config->{preview_size} = 450;
                    }

                    # Ensure custom_directories is an array ref
                    if (!ref($config->{custom_directories}) || ref($config->{custom_directories}) ne 'ARRAY') {
                        $config->{custom_directories} = [];
                    }

                    # Ensure theme_backups is an array ref
                    if (!ref($config->{theme_backups}) || ref($config->{theme_backups}) ne 'ARRAY') {
                        $config->{theme_backups} = [];
                    }

                    print "Loaded configuration from $config_file\n";
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
        print "Cinnamon Application Themes Manager started\n";
        Gtk3::main();
    }
}

# Main execution
if (!caller) {
    my $app = CinnamonApplicationThemesManager->new();
    $app->run();
}

1;

