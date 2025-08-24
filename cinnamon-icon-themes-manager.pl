#!/usr/bin/perl
use strict;
use warnings;
use utf8;

# Cinnamon Icons Theme Manager - Standalone Application
# A dedicated icon theme management application for Linux Mint Cinnamon
# Written in Perl with GTK3

use Gtk3 -init;
use Glib 'TRUE', 'FALSE';
use File::Spec;
use File::Basename qw(basename dirname);
use JSON qw(encode_json decode_json);
use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use Cairo;

$SIG{__WARN__} = sub {
    my $warning = shift;
    return if $warning =~ /Theme parsing error/;
    warn $warning;
};

# Main application class
package CinnamonIconsThemeManager {
    use Moo;
    use File::Basename qw(basename dirname);

    has 'window' => (is => 'rw');
    has 'directory_list' => (is => 'rw');
    has 'icons_grid' => (is => 'rw');
    has 'content_switcher' => (is => 'rw');
    has 'icons_mode' => (is => 'rw');
    has 'settings_mode' => (is => 'rw');
    has 'zoom_level' => (is => 'rw', default => sub { 250 });
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
    has 'icon_cache' => (is => 'rw', default => sub { {} });
    has 'current_theme' => (is => 'rw');

    has 'icon_types' => (is => 'ro', default => sub { [
        # Row 1: Places icons
        {
            name => 'computer',
            desc => 'Computer',
            alternatives => ['computer-laptop', 'computer-desktop', 'system'],
            fallback_names => ['computer'],
            category => 'devices'
        },
        {
            name => 'folder',
            desc => 'Folder',
            alternatives => ['user-folder', 'folder-home', 'user-folder-home'],
            fallback_names => ['folder'],
            category => 'places'
        },
        {
            name => 'desktop',
            desc => 'Desktop',
            alternatives => ['user-desktop', 'gnome-fs-desktop','folder-desktop'],
            fallback_names => ['user-desktop'],
            category => 'places'
        },
        {
            name => 'user-trash',
            desc => 'Trash',
            alternatives => ['user-trash-empty', 'trash-empty', 'edittrash', 'gnome-stock-trash-empty'],
            fallback_names => ['user-trash'],
            category => 'places'
        },
        # Row 2: Application/Script mimetypes
        {
            name => 'application-x-shellscript',
            desc => 'Shell Script',
            alternatives => ['text-x-script', 'application-x-script', 'text-x-shellscript'],
            fallback_names => ['application-x-shellscript'],
            category => 'mimetypes'
        },
        {
            name => 'application-x-php',
            desc => 'PHP',
            alternatives => ['text-x-php', 'application-php', 'text-php'],
            fallback_names => ['application-x-php'],
            category => 'mimetypes'
        },
        {
            name => 'application-x-ruby',
            desc => 'Ruby',
            alternatives => ['text-x-ruby', 'application-ruby', 'text-ruby'],
            fallback_names => ['application-x-ruby'],
            category => 'mimetypes'
        },
        {
            name => 'text-x-javascript',
            desc => 'JavaScript',
            alternatives => ['application-x-javascript', 'application-javascript', 'text-javascript'],
            fallback_names => ['text-x-javascript'],
            category => 'mimetypes'
        },
        # Row 3: Document mimetypes
        {
            name => 'text-plain',
            desc => 'Text',
            alternatives => ['text-x-generic', 'text', 'text-x-plain'],
            fallback_names => ['text-plain'],
            category => 'mimetypes'
        },
        {
            name => 'x-office-document',
            desc => 'Document',
            alternatives => ['application-vnd.oasis.opendocument.text', 'application-msword', 'application-document'],
            fallback_names => ['x-office-document'],
            category => 'mimetypes'
        },
        {
            name => 'x-office-presentation',
            desc => 'Presentation',
            alternatives => ['application-vnd.oasis.opendocument.presentation', 'application-vnd.ms-powerpoint', 'application-presentation'],
            fallback_names => ['x-office-presentation'],
            category => 'mimetypes'
        },
        {
            name => 'x-office-spreadsheet',
            desc => 'Spreadsheet',
            alternatives => ['application-vnd.oasis.opendocument.spreadsheet', 'application-vnd.ms-excel', 'application-spreadsheet'],
            fallback_names => ['x-office-spreadsheet'],
            category => 'mimetypes'
        },
        # Row 4: Device icons
        {
            name => 'application-x-tar',
            desc => 'Tar',
            alternatives => ['application-tar', 'gnome-mime-application-x-compressed-tar', 'gnome-mime-application-x-tar','package-tar','tar'],
            fallback_names => ['tar'],
            category => 'mimetypes'
        },
        {
            name => 'image',
            desc => 'Image',
            alternatives => ['application-image', 'application-x-image'],
            fallback_names => ['image'],
            category => 'mimetypes'
        },
        {
            name => 'application-executable',
            desc => 'Executable',
            alternatives => ['application-x-executable', 'exec', 'gnome-mime-application-x-executable'],
            fallback_names => ['executable'],
            category => 'mimetypes'
        },
        {
            name => 'printer',
            desc => 'Printer',
            alternatives => ['printer-network', 'printer-local', 'device-printer'],
            fallback_names => ['printer'],
            category => 'devices'
        }
    ] });

    sub BUILD {
        my $self = shift;
        $self->_initialize_configuration();
        $self->_setup_ui();
        $self->_populate_icon_directories();
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

        # Set zoom level from config (updated range)
        $self->zoom_level($config->{preview_size} || 250);
        $self->last_selected_directory_path($config->{last_selected_directory});

        print "Configuration initialized\n";
        print "  Preview size: " . $self->zoom_level . "\n";
        print "  Custom directories: " . @{$config->{custom_directories} || []} . "\n";
        print "  Last directory: " . ($self->last_selected_directory_path || 'none') . "\n";
    }

    sub _initialize_directory_structure {
        my $self = shift;

        # Create main application directory for Icons Theme Manager
        my $app_dir = $ENV{HOME} . '/.local/share/cinnamon-icons-theme-manager';
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

        print "Directory structure initialized for Icons Theme Manager\n";
    }

    sub _detect_current_theme {
        my $self = shift;

        # Get the current icon theme
        my $icon_theme = `gsettings get org.cinnamon.desktop.interface icon-theme 2>/dev/null`;
        chomp $icon_theme if $icon_theme;
        $icon_theme =~ s/^'(.*)'$/$1/ if $icon_theme;

        $self->current_theme($icon_theme || 'Unknown');
        print "Current Icon theme: " . $self->current_theme . "\n";
    }

    sub _setup_ui {
        my $self = shift;

        # Create main window
        my $window = Gtk3::Window->new('toplevel');
        $window->set_title('Cinnamon Icons Theme Manager');
        $window->set_default_size(1200, 900);
        $window->set_position('center');
        $window->set_icon_name('preferences-desktop-theme');

        # Create header bar
        my $header = Gtk3::HeaderBar->new();
        $header->set_show_close_button(1);
        $header->set_title('Cinnamon Icons Theme Manager');
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

        # Right panel - Icons display and settings
        my $right_panel = Gtk3::Frame->new();
        $right_panel->set_shadow_type('in');

        my $right_container = Gtk3::Box->new('vertical', 0);

        # Top buttons (Icon Themes/Settings)
        my $mode_buttons = Gtk3::Box->new('horizontal', 0);
        $mode_buttons->set_margin_left(12);
        $mode_buttons->set_margin_right(12);
        $mode_buttons->set_margin_top(12);
        $mode_buttons->set_margin_bottom(6);

        my ($icons_mode, $settings_mode) = $self->_create_mode_buttons();

        $mode_buttons->pack_start($icons_mode, 1, 1, 0);
        $mode_buttons->pack_start($settings_mode, 1, 1, 0);

        $right_container->pack_start($mode_buttons, 0, 0, 0);

        # Content area (icons or settings)
        my $content_switcher = Gtk3::Stack->new();
        $content_switcher->set_transition_type('slide-left-right');

        # Icons content
        my $icons_view = Gtk3::ScrolledWindow->new();
        $icons_view->set_policy('automatic', 'automatic');
        $icons_view->set_vexpand(1);

        my $icons_grid = Gtk3::FlowBox->new();
        $icons_grid->set_valign('start');
        $icons_grid->set_max_children_per_line(8); # Will be dynamically adjusted
        $icons_grid->set_min_children_per_line(1); # Allow single column when needed
        $icons_grid->set_selection_mode('single');
        $icons_grid->set_margin_left(12);
        $icons_grid->set_margin_right(12);
        $icons_grid->set_margin_top(12);
        $icons_grid->set_margin_bottom(12);
        $icons_grid->set_row_spacing(12);
        $icons_grid->set_column_spacing(12);

        $icons_view->add($icons_grid);
        $content_switcher->add_named($icons_view, 'icons');

        # Settings content
        my $settings_view = Gtk3::ScrolledWindow->new();
        $settings_view->set_policy('automatic', 'automatic');
        my $settings_content = $self->_create_icon_settings();
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
        $self->icons_grid($icons_grid);
        $self->content_switcher($content_switcher);
        $self->icons_mode($icons_mode);
        $self->settings_mode($settings_mode);
        $self->loading_spinner($loading_spinner);
        $self->loading_label($loading_label);
        $self->loading_box($loading_box);

        # Connect signals
        $self->_connect_signals($add_dir_button, $remove_dir_button, $zoom_in, $zoom_out);

        print "UI setup completed\n";
    }

    sub _create_directory_buttons {
        my $self = shift;

        my $add_button = Gtk3::Button->new();
        $add_button->set_relief('none');
        $add_button->set_size_request(32, 32);
        $add_button->set_tooltip_text('Add icon theme directory');

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
        $zoom_out->set_tooltip_text('Decrease icon preview size (200px minimum)');

        my $zoom_in = Gtk3::Button->new();
        $zoom_in->set_relief('none');
        $zoom_in->set_size_request(32, 32);
        $zoom_in->set_tooltip_text('Increase icon preview size (800px maximum)');

        # Use system icons for zoom
        my $zoom_out_icon = Gtk3::Image->new_from_icon_name('zoom-out-symbolic', 1);
        $zoom_out->add($zoom_out_icon);

        my $zoom_in_icon = Gtk3::Image->new_from_icon_name('zoom-in-symbolic', 1);
        $zoom_in->add($zoom_in_icon);

        return ($zoom_out, $zoom_in);
    }

    sub _create_mode_buttons {
        my $self = shift;

        my $icons_mode = Gtk3::ToggleButton->new_with_label('Icon Themes');
        my $settings_mode = Gtk3::ToggleButton->new_with_label('Settings');

        $icons_mode->set_active(1); # Active by default

        return ($icons_mode, $settings_mode);
    }

    sub _create_icon_settings {
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
        $current_label->set_markup('<b>Icon Theme:</b> Detecting...');
        $current_container->pack_start($current_label, 0, 0, 0);

        my $button_box = Gtk3::Box->new('horizontal', 6);

        my $refresh_button = Gtk3::Button->new_with_label('Refresh Theme Status');
        $refresh_button->set_halign('start');
        $refresh_button->signal_connect('clicked' => sub {
            $self->_detect_current_theme();
            my $theme = $self->current_theme || 'Unknown';
            $current_label->set_markup("<b>Icon Theme:</b> $theme");
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
                "Apply the default Cinnamon system icon theme?\n\nThis will set:\n• Icon Theme: Mint-Y\n\nContinue?"
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

        # Icon Theme Options section
        my $options_frame = Gtk3::Frame->new();
        $options_frame->set_label('Icon Options');
        $options_frame->set_label_align(0.02, 0.5);

        my $options_container = Gtk3::Box->new('vertical', 12);
        $options_container->set_margin_left(12);
        $options_container->set_margin_right(12);
        $options_container->set_margin_top(12);
        $options_container->set_margin_bottom(12);

        # Icon size for desktop
        my $desktop_size_label = Gtk3::Label->new('Desktop Icon Size:');
        $desktop_size_label->set_halign('start');
        $options_container->pack_start($desktop_size_label, 0, 0, 0);

        my $desktop_size_combo = Gtk3::ComboBoxText->new();
        $desktop_size_combo->append_text('Small (32px)');
        $desktop_size_combo->append_text('Medium (48px)');
        $desktop_size_combo->append_text('Large (64px)');
        $desktop_size_combo->append_text('Extra Large (96px)');
        $desktop_size_combo->set_active(1); # Default to Medium
        $desktop_size_combo->set_halign('start');
        $options_container->pack_start($desktop_size_combo, 0, 0, 0);

        # Icon size for file manager
        my $fm_size_label = Gtk3::Label->new('File Manager Icon Size:');
        $fm_size_label->set_halign('start');
        $options_container->pack_start($fm_size_label, 0, 0, 0);

        my $fm_size_combo = Gtk3::ComboBoxText->new();
        $fm_size_combo->append_text('Small (16px)');
        $fm_size_combo->append_text('Medium (24px)');
        $fm_size_combo->append_text('Large (32px)');
        $fm_size_combo->append_text('Extra Large (48px)');
        $fm_size_combo->set_active(2); # Default to Large
        $fm_size_combo->set_halign('start');
        $options_container->pack_start($fm_size_combo, 0, 0, 0);

        # Icon size for panel
        my $panel_size_label = Gtk3::Label->new('Panel Icon Size:');
        $panel_size_label->set_halign('start');
        $options_container->pack_start($panel_size_label, 0, 0, 0);

        my $panel_size_combo = Gtk3::ComboBoxText->new();
        $panel_size_combo->append_text('Small (16px)');
        $panel_size_combo->append_text('Medium (22px)');
        $panel_size_combo->append_text('Large (24px)');
        $panel_size_combo->append_text('Extra Large (32px)');
        $panel_size_combo->set_active(1); # Default to Medium
        $panel_size_combo->set_halign('start');
        $options_container->pack_start($panel_size_combo, 0, 0, 0);

        # Use symbolic icons
        my $symbolic_check = Gtk3::CheckButton->new_with_label('Use Symbolic Icons Where Available');
        $options_container->pack_start($symbolic_check, 0, 0, 0);

        $options_frame->add($options_container);
        $settings_box->pack_start($options_frame, 0, 0, 0);

        # Apply button
        my $apply_button = Gtk3::Button->new_with_label('Apply Settings');
        $apply_button->set_halign('center');

        # Connect apply button signal
        $apply_button->signal_connect('clicked' => sub {
            my $desktop_size_text = $desktop_size_combo->get_active_text();
            my $fm_size_text = $fm_size_combo->get_active_text();
            my $panel_size_text = $panel_size_combo->get_active_text();
            my $use_symbolic = $symbolic_check->get_active();

            # Map sizes to pixel values
            my %size_mapping = (
                'Small (32px)' => 32, 'Medium (48px)' => 48, 'Large (64px)' => 64, 'Extra Large (96px)' => 96,
                'Small (16px)' => 16, 'Medium (24px)' => 24, 'Large (32px)' => 32, 'Extra Large (48px)' => 48,
                'Medium (22px)' => 22, 'Large (24px)' => 24
            );

            my $desktop_size = $size_mapping{$desktop_size_text} || 48;
            my $fm_size = $size_mapping{$fm_size_text} || 32;
            my $panel_size = $size_mapping{$panel_size_text} || 22;

            print "Applying icon settings:\n";
            print "  Desktop icon size: $desktop_size\n";
            print "  File manager icon size: $fm_size\n";
            print "  Panel icon size: $panel_size\n";
            print "  Use symbolic icons: " . ($use_symbolic ? 'yes' : 'no') . "\n";

            # Apply settings using gsettings
            system("gsettings set org.cinnamon.desktop.interface desktop-icon-size $desktop_size");
            system("gsettings set org.nemo.icon-view default-zoom-level '$fm_size'");
            system("gsettings set org.cinnamon panel-icon-size $panel_size");

            # Show confirmation
            my $dialog = Gtk3::MessageDialog->new(
                $self->window,
                'modal',
                'info',
                'ok',
                'Icon settings applied successfully!'
            );
            $dialog->run();
            $dialog->destroy();
        });

        $settings_box->pack_start($apply_button, 0, 0, 12);

        # Initialize current theme display
        Glib::Timeout->add(500, sub {
            $self->_detect_current_theme();
            my $theme = $self->current_theme || 'Unknown';
            $current_label->set_markup("<b>Icon Theme:</b> $theme");
            return 0; # Don't repeat
        });

        return $settings_box;
    }

    sub _apply_system_theme {
        my $self = shift;

        print "Applying default Cinnamon system icon theme...\n";

        # Apply default Mint icon theme
        system("gsettings set org.cinnamon.desktop.interface icon-theme 'Mint-Y'");

        # Update current theme tracking
        $self->current_theme('Mint-Y');

        my $dialog = Gtk3::MessageDialog->new(
            $self->window,
            'modal',
            'info',
            'ok',
            "Default Cinnamon system icon theme applied!\n\nIcon Theme: Mint-Y"
        );
        $dialog->run();
        $dialog->destroy();

        # Refresh the current theme detection
        $self->_detect_current_theme();
    }

    sub _backup_current_settings {
        my $self = shift;

        print "Backing up current icon theme settings...\n";

        # Get current settings
        my $icon_theme = `gsettings get org.cinnamon.desktop.interface icon-theme 2>/dev/null`;

        chomp($icon_theme);
        $icon_theme =~ s/^'(.*)'$/$1/;

        my $backup = {
            icon_theme => $icon_theme,
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
            "Current icon theme settings backed up successfully!\n\nIcon Theme: $icon_theme"
        );
        $dialog->run();
        $dialog->destroy();
    }

    sub _connect_signals {
        my ($self, $add_dir_button, $remove_dir_button, $zoom_in, $zoom_out) = @_;

        # Connect signals for mode buttons
        $self->_connect_mode_button_signals($self->icons_mode, $self->settings_mode, $self->content_switcher);

        $self->directory_list->signal_connect('row-selected' => sub {
            my ($widget, $row) = @_;
            return unless $row;

            # Save the selected directory to config
            my $dir_path = $self->directory_paths->{$row + 0};
            if ($dir_path) {
                $self->config->{last_selected_directory} = $dir_path;
                $self->_save_config($self->config);
            }

            $self->_load_icons_from_directory ($row);
        });

        $add_dir_button->signal_connect('clicked' => sub {
            $self->_add_icon_directory();
        });

        $remove_dir_button->signal_connect('clicked' => sub {
            $self->_remove_icon_directory();
        });

        $zoom_in->signal_connect('clicked' => sub {
            # Updated maximum zoom level to 800
            my $new_zoom = ($self->zoom_level < 800) ? $self->zoom_level + 50 : 800;
            $self->zoom_level($new_zoom);
            $self->_update_icon_zoom();
            $self->_adjust_grid_columns(); # Add dynamic column adjustment
            # Save zoom level to config
            $self->config->{preview_size} = $self->zoom_level;
            $self->_save_config($self->config);
            print "Zoomed in to: " . $self->zoom_level . "px\n";
        });

        $zoom_out->signal_connect('clicked' => sub {
            # Keep minimum zoom level at 200
            my $new_zoom = ($self->zoom_level > 200) ? $self->zoom_level - 50 : 200;
            $self->zoom_level($new_zoom);
            $self->_update_icon_zoom();
            $self->_adjust_grid_columns(); # Add dynamic column adjustment
            # Save zoom level to config
            $self->config->{preview_size} = $self->zoom_level;
            $self->_save_config($self->config);
            print "Zoomed out to: " . $self->zoom_level . "px\n";
        });

        $self->icons_grid->signal_connect('child-activated' => sub {
            my ($widget, $child) = @_;
            $self->_set_icon_theme($child);
        });

        # Add window size change detection
        $self->window->signal_connect('size-allocate' => sub {
            my ($widget, $allocation) = @_;
            # Add small delay to avoid constant adjustments during window resize
            Glib::Timeout->add(250, sub {
                $self->_adjust_grid_columns();
                return 0; # Don't repeat
            });
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

    sub _adjust_grid_columns {
        my $self = shift;

        # Get the current window size
        my ($window_width, $window_height) = $self->window->get_size();

        # Account for left panel (280px) and margins/padding (approximately 50px total)
        my $available_width = $window_width - 280 - 50;

        # Calculate how many columns can fit based on current zoom level
        # Add some margin between items (approximately 12px spacing)
        my $item_width_with_spacing = $self->zoom_level + 12;
        my $max_columns = int($available_width / $item_width_with_spacing);

        # Ensure we have at least 1 column and at most 8 columns
        $max_columns = 1 if $max_columns < 1;
        $max_columns = 8 if $max_columns > 8;

        print "DEBUG: Window width: ${window_width}px, Available width: ${available_width}px\n";
        print "DEBUG: Zoom level: " . $self->zoom_level . "px, Item width with spacing: ${item_width_with_spacing}px\n";
        print "DEBUG: Adjusting grid to maximum $max_columns columns\n";

        # Update the FlowBox properties
        $self->icons_grid->set_max_children_per_line($max_columns);
        $self->icons_grid->set_min_children_per_line(1); # Always allow at least 1 column

        # Force a redraw to apply the changes immediately
        $self->icons_grid->queue_resize();

        return $max_columns;
    }

    sub _connect_mode_button_signals {
        my ($self, $icons_mode, $settings_mode, $content_switcher) = @_;

        # Handle clicks for icons mode button
        $icons_mode->signal_connect('toggled' => sub {
            my $widget = shift;
            if ($widget->get_active()) {
                $settings_mode->set_active(0);
                $content_switcher->set_visible_child_name('icons');
            }
        });

        # Handle clicks for settings mode button
        $settings_mode->signal_connect('toggled' => sub {
            my $widget = shift;
            if ($widget->get_active()) {
                $icons_mode->set_active(0);
                $content_switcher->set_visible_child_name('settings');
            }
        });
    }

    sub _populate_icon_directories {
        my $self = shift;

        # Default icon theme directories
        my @default_dirs = (
            { name => 'User Icons', path => $ENV{HOME} . '/.local/share/icons' },
            { name => 'User Icons (Legacy)', path => $ENV{HOME} . '/.icons' },
            { name => 'System Icons', path => '/usr/share/icons' },
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

        print "Populated icon directories\n";
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
            # The row-selected signal will automatically trigger _load_icons_from_directory
        }
    }

    sub _add_icon_directory {
        my $self = shift;

        my $dialog = Gtk3::FileChooserDialog->new(
            'Select Icon Theme Directory',
            $self->window,
            'select-folder',
            'gtk-cancel' => 'cancel',
            'gtk-open' => 'accept'
        );

        if ($dialog->run() eq 'accept') {
            my $folder = $dialog->get_filename();
            my $name = File::Basename::basename($folder);  # Use fully qualified name

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

    sub _remove_icon_directory {
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

    sub _load_icons_from_directory {
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

        # Show loading indicator
        $self->_show_loading_indicator('Scanning for complete icon themes...');

        # Clear existing icons immediately
        my $flowbox = $self->icons_grid;
        foreach my $child ($flowbox->get_children()) {
            $flowbox->remove($child);
        }

        # Clear references
        $self->theme_paths({});
        $self->theme_widgets({});
        $self->current_directory($dir_path);

        # Clear any existing loaded theme names tracking
        $self->{loaded_theme_names} = {};

        # Get or scan themes (with validation)
        my $themes_ref;
        if (exists $self->cached_theme_lists->{$dir_path}) {
            $themes_ref = $self->cached_theme_lists->{$dir_path};
            print "Using cached theme list for $dir_path (" . @$themes_ref . " complete themes)\n";
        } else {
            my @themes = $self->_scan_icon_themes($dir_path);
            @themes = sort { lc($a->{name}) cmp lc($b->{name}) } @themes;
            $themes_ref = \@themes;
            $self->cached_theme_lists->{$dir_path} = $themes_ref;
            print "Scanned $dir_path: " . @themes . " complete icon themes found\n";
        }

        if (@$themes_ref == 0) {
            $self->_hide_loading_indicator();
            print "No complete icon themes found in $dir_path\n";

            # Show a message to the user
            my $no_themes_label = Gtk3::Label->new();
            $no_themes_label->set_markup("<big><b>No Complete Icon Themes Found</b></big>\n\nThis directory doesn't contain any complete icon themes.\nComplete themes must have 'places', 'devices', and 'mimes' (or 'mimetypes') directories with icon files.");
            $no_themes_label->set_justify('center');
            $no_themes_label->set_margin_top(50);
            $no_themes_label->set_margin_bottom(50);
            $no_themes_label->set_margin_left(50);
            $no_themes_label->set_margin_right(50);

            $flowbox->add($no_themes_label);
            $flowbox->show_all();
            return;
        }

        # Start progressive loading
        $self->_start_progressive_loading($themes_ref, $dir_path);
    }

    sub _scan_icon_themes {
        my ($self, $base_dir) = @_;

        my @themes = ();
        my %seen_themes = (); # Track theme names to prevent duplicates

        opendir(my $dh, $base_dir) or return @themes;
        my @subdirs = grep { -d "$base_dir/$_" && $_ !~ /^\./ } readdir($dh);
        closedir($dh);

        foreach my $subdir (@subdirs) {
            my $theme_path = "$base_dir/$subdir";

            # Skip if we've already processed this theme name
            if (exists $seen_themes{$subdir}) {
                print "DEBUG: Skipping duplicate theme name: $subdir\n";
                next;
            }

            # Check if this directory contains an icon theme
            my $index_file = "$theme_path/index.theme";
            next unless -f $index_file;

            # Validate that this is a complete icon theme with required categories
            unless ($self->_validate_icon_theme_completeness($theme_path)) {
                print "DEBUG: Skipping incomplete icon theme: $subdir (missing required categories)\n";
                next;
            }

            # Parse theme information
            my $theme_info = $self->_parse_icon_theme_info($theme_path, $subdir);

            # Mark this theme name as seen
            $seen_themes{$subdir} = 1;

            push @themes, $theme_info;
            print "DEBUG: Including complete icon theme '$subdir'\n";
        }

        return @themes;
    }

    sub _validate_icon_theme_completeness {
        my ($self, $theme_path) = @_;

        print "DEBUG: === Validating icon theme completeness: $theme_path ===\n";

        # Required categories that must be present for a complete icon theme
        my @required_categories = ('places', 'devices');

        # For mimetypes, we need to check for both 'mimes' and 'mimetypes' since themes use either
        my @mimetype_variations = ('mimes', 'mimetypes');

        my %found_categories = ();

        # Scan the theme directory structure recursively to find category directories
        my $scan_for_categories;
        $scan_for_categories = sub {
            my ($dir_path, $depth) = @_;

            return if $depth > 6;  # Limit recursion depth
            return unless -d $dir_path;

            print "DEBUG: Scanning directory: $dir_path (depth: $depth)\n";

            # Check if current directory matches any required category
             my $dir_name = File::Basename::basename($dir_path);

            # Check for standard required categories
            foreach my $required_cat (@required_categories) {
                if ($dir_name =~ /^\Q$required_cat\E$/i) {
                    # Verify this directory actually contains icon files
                    if ($self->_directory_contains_icons($dir_path)) {
                        $found_categories{$required_cat} = 1;
                        print "DEBUG: Found required category '$required_cat' with icons at: $dir_path\n";
                    }
                }
            }

            # Check for mimetype variations
            foreach my $mime_var (@mimetype_variations) {
                if ($dir_name =~ /^\Q$mime_var\E$/i) {
                    # Verify this directory actually contains icon files
                    if ($self->_directory_contains_icons($dir_path)) {
                        $found_categories{'mimetypes'} = 1;  # Use standard name internally
                        print "DEBUG: Found mimetypes category ('$mime_var') with icons at: $dir_path\n";
                    }
                }
            }

            # Continue scanning subdirectories
            if (opendir(my $dh, $dir_path)) {
                my @subdirs = grep { -d "$dir_path/$_" && $_ !~ /^\./ } readdir($dh);
                closedir($dh);

                foreach my $subdir (@subdirs) {
                    $scan_for_categories->("$dir_path/$subdir", $depth + 1);
                }
            }
        };

        # Start scanning from theme root
        $scan_for_categories->($theme_path, 0);

        # Check if all required categories were found
        my @missing_categories = ();

        foreach my $required_cat (@required_categories) {
            unless ($found_categories{$required_cat}) {
                push @missing_categories, $required_cat;
            }
        }

        # Check for mimetypes (either 'mimes' or 'mimetypes')
        unless ($found_categories{'mimetypes'}) {
            push @missing_categories, 'mimes/mimetypes';
        }

        if (@missing_categories) {
            print "DEBUG: Theme is INCOMPLETE - missing categories: " . join(", ", @missing_categories) . "\n";
            return 0;  # Incomplete theme
        } else {
            print "DEBUG: Theme is COMPLETE - all required categories found\n";
            return 1;  # Complete theme
        }
    }

    sub _directory_contains_icons {
        my ($self, $dir_path) = @_;

        return 0 unless -d $dir_path;

        # Check if this directory contains icon files (directly or in subdirectories)
        my $has_icons = 0;

        my $check_for_icons;
        $check_for_icons = sub {
            my ($check_dir, $depth) = @_;

            return if $depth > 3;  # Limit recursion depth for icon checking
            return unless -d $check_dir;

            if (opendir(my $dh, $check_dir)) {
                my @entries = readdir($dh);
                closedir($dh);

                foreach my $entry (@entries) {
                    next if $entry =~ /^\./;  # Skip hidden files
                    my $full_path = "$check_dir/$entry";

                    if (-f $full_path) {
                        # Check if this is an icon file (and not symbolic)
                        if ($entry =~ /\.(svg|png|xpm|ico)$/i &&
                            $entry !~ /-symbolic\./i &&
                            $entry !~ /symbolic/i) {
                            $has_icons = 1;
                            print "DEBUG: Found icon file: $full_path\n";
                            return;  # Found at least one icon, that's enough
                        }
                    } elsif (-d $full_path) {
                        # Recursively check subdirectories
                        $check_for_icons->($full_path, $depth + 1);
                        return if $has_icons;  # Stop if we found icons
                    }
                }
            }
        };

        $check_for_icons->($dir_path, 0);

        print "DEBUG: Directory $dir_path " . ($has_icons ? "contains" : "does not contain") . " icon files\n";
        return $has_icons;
    }


    sub _parse_icon_theme_info {
        my ($self, $theme_path, $theme_name) = @_;

        my $theme_info = {
            name          => $theme_name,
            path          => $theme_path,
            display_name  => $theme_name,
            comment       => '',
            directories   => [],
            is_complete   => 1,  # Mark as complete since we've validated it
        };

        # Parse index.theme file
        my $index_file = "$theme_path/index.theme";
        if (-f $index_file) {
            open my $fh, '<', $index_file or return $theme_info;

            my $in_icon_theme_section = 0;
            while (my $line = <$fh>) {
                chomp $line;
                next if $line =~ /^\s*#/ || $line =~ /^\s*$/;

                if ($line =~ /^\[Icon Theme\]$/) {
                    $in_icon_theme_section = 1;
                    next;
                } elsif ($line =~ /^\[/) {
                    $in_icon_theme_section = 0;
                    next;
                }

                next unless $in_icon_theme_section;

                if ($line =~ /^Name\s*=\s*(.+)$/) {
                    $theme_info->{display_name} = $1;
                } elsif ($line =~ /^Comment\s*=\s*(.+)$/) {
                    $theme_info->{comment} = $1;
                } elsif ($line =~ /^Directories\s*=\s*(.+)$/) {
                    my $dirs = $1;
                    $theme_info->{directories} = [split(/,/, $dirs)];
                    # Clean up directory names
                    $theme_info->{directories} = [map { s/^\s+|\s+$//gr } @{$theme_info->{directories}}];
                }
            }
            close $fh;
        }

        return $theme_info;
    }

    sub _start_progressive_loading {
        my ($self, $themes_ref, $dir_path) = @_;

        my $total_themes = @$themes_ref;
        my $loaded_widgets = 0;

        print "Starting progressive loading of $total_themes themes\n";

        # Initialize tracking for loaded themes to prevent duplicates
        $self->{loaded_theme_names} = {} unless exists $self->{loaded_theme_names};

        # Phase 1: Create all theme widgets with placeholders
        $self->_update_loading_progress("Creating theme widgets...", 0);

        my $create_widgets;
        $create_widgets = sub {
            return 0 if $self->current_directory ne $dir_path;

            my $batch_size = 6;
            my $batch_end = ($loaded_widgets + $batch_size - 1 < $total_themes - 1)
                        ? $loaded_widgets + $batch_size - 1
                        : $total_themes - 1;

            # Create widgets for this batch
            for my $i ($loaded_widgets..$batch_end) {
                my $theme_info = $themes_ref->[$i];
                my $theme_name = $theme_info->{name};

                # Skip if we've already created a widget for this theme name
                if (exists $self->{loaded_theme_names}->{$theme_name}) {
                    print "DEBUG: Skipping duplicate widget creation for theme: $theme_name\n";
                    next;
                }

                # Create widget with placeholder preview
                my $theme_widget = $self->_create_icon_theme_widget($theme_info);
                $self->icons_grid->add($theme_widget);

                # Mark this theme as loaded
                $self->{loaded_theme_names}->{$theme_name} = 1;
            }

            $loaded_widgets = $batch_end + 1;

            # Update progress
            my $widget_progress = int(($loaded_widgets / $total_themes) * 100);
            $self->_update_loading_progress("Loading icon themes...", $widget_progress);

            $self->icons_grid->show_all();

            if ($loaded_widgets < $total_themes) {
                # Continue with next batch
                Glib::Timeout->add(10, $create_widgets);
                return 0;
            } else {
                # Widget creation complete
                print "All icon theme widgets created\n";
                $self->_hide_loading_indicator();
                return 0;
            }
        };

        # Start widget creation
        Glib::Timeout->add(10, $create_widgets);
    }

    sub _create_icon_theme_widget {
        my ($self, $theme_info) = @_;

        print "Creating widget for icon theme: " . $theme_info->{name} . "\n";

        # Create frame with inset shadow (like backgrounds manager)
        my $frame = Gtk3::Frame->new();
        $frame->set_shadow_type('in');

        # Create vertical box container
        my $box = Gtk3::Box->new('vertical', 6);
        $box->set_margin_left(6);
        $box->set_margin_right(6);
        $box->set_margin_top(6);
        $box->set_margin_bottom(6);

        # Create icon preview grid
        my $preview_widget = $self->_create_icon_preview($theme_info, $self->zoom_level);
        $preview_widget->set_size_request($self->zoom_level, int($self->zoom_level * 0.75));

        $box->pack_start($preview_widget, 1, 1, 0);

        # Create label
        my $theme_name = $theme_info->{display_name} || $theme_info->{name};
        my $label = Gtk3::Label->new($theme_name);
        $label->set_ellipsize('middle');
        $label->set_max_width_chars(15);

        $box->pack_start($label, 0, 0, 0);
        $frame->add($box);

        # Store references
        $self->theme_paths->{$frame + 0} = $theme_info;
        $self->theme_widgets->{$frame + 0} = $preview_widget;

        return $frame;
    }

    sub _create_icon_preview {
        my ($self, $theme_info, $size) = @_;

        my $theme_name = $theme_info->{name};
        my $theme_path = $theme_info->{path};

        # Calculate preview dimensions
        my $width = $size;
        my $height = int($size * 0.75);

        # Check cache first
        my $cache_dir = $ENV{HOME} . '/.local/share/cinnamon-icons-theme-manager/thumbnails';
        system("mkdir -p '$cache_dir'") unless -d $cache_dir;

        my $preview_path = "$cache_dir/${theme_name}-preview-${size}.png";

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

        # Generate new preview if no cached version exists
        unless ($preview_widget) {
            # Create placeholder initially
            my $pixbuf = $self->_create_placeholder_pixbuf($width, $height);
            $preview_widget = Gtk3::Image->new_from_pixbuf($pixbuf);

            # Schedule preview generation
            $self->_schedule_preview_generation($theme_info, $preview_path, $width, $height);
        }

        return $preview_widget;
    }

    sub _schedule_preview_generation {
        my ($self, $theme_info, $cache_file, $width, $height) = @_;

        # Add to generation queue if not already queued
        if (!$self->{preview_generation_queue}) {
            $self->{preview_generation_queue} = [];
        }

        # Check if already queued - handle undefined theme names and prevent duplicates
        my $current_name = $theme_info->{name} || '';
        return if $current_name eq ''; # Skip if no theme name

        foreach my $queued (@{$self->{preview_generation_queue}}) {
            my $queued_name = $queued->{theme_info}->{name} || '';
            if ($queued_name eq $current_name) {
                print "DEBUG: Theme '$current_name' already queued for preview generation\n";
                return;
            }
        }

        # Also check if preview is currently being generated
        if ($self->{currently_generating_preview} &&
            $self->{currently_generating_preview} eq $current_name) {
            print "DEBUG: Theme '$current_name' is currently being generated\n";
            return;
        }

        # Add to queue
        push @{$self->{preview_generation_queue}}, {
            theme_info => $theme_info,
            cache_file => $cache_file,
            width => $width,
            height => $height
        };

        print "DEBUG: Added '$current_name' to preview generation queue\n";

        # Start processing queue if not already running
        if (!$self->{preview_generation_active}) {
            $self->_process_preview_generation_queue();
        }
    }

    sub _scan_theme_structure {
        my ($self, $theme_path) = @_;

        print "DEBUG: === Scanning theme structure for: $theme_path ===\n";

        my @icon_directories = ();

        # Target directories we care about (updated for 4x4 grid requirements)
        my @content_dirs = ('places', 'devices', 'mimes', 'mimetypes');
        my @quality_dirs = ('scalable', '96x96', '64x64', '48x48');

        print "DEBUG: Searching for combinations of content dirs: " . join(", ", @content_dirs) . "\n";
        print "DEBUG: With quality dirs: " . join(", ", @quality_dirs) . "\n";

        # Function to recursively find directories up to depth 3
        my $find_directories;
        $find_directories = sub {
            my ($base_path, $target_names, $current_depth, $max_depth) = @_;
            my @found = ();

            return @found if $current_depth > $max_depth;
            return @found unless -d $base_path;

            opendir(my $dh, $base_path) or return @found;
            my @entries = grep { -d "$base_path/$_" && $_ !~ /^\./ } readdir($dh);
            closedir($dh);

            foreach my $entry (@entries) {
                my $full_path = "$base_path/$entry";

                # Check if this entry matches any target name
                if (grep { lc($entry) eq lc($_) } @$target_names) {
                    push @found, $full_path;
                }

                # Recursively search subdirectories
                if ($current_depth < $max_depth) {
                    push @found, $find_directories->($full_path, $target_names, $current_depth + 1, $max_depth);
                }
            }

            return @found;
        };

        # Strategy 1: Look for quality_dir/content_dir combinations
        print "DEBUG: Strategy 1 - Looking for quality/content combinations...\n";
        foreach my $quality_dir (@quality_dirs) {
            my @quality_paths = $find_directories->($theme_path, [$quality_dir], 0, 2);
            foreach my $quality_path (@quality_paths) {
                foreach my $content_dir (@content_dirs) {
                    my @content_paths = $find_directories->($quality_path, [$content_dir], 0, 2);
                    foreach my $content_path (@content_paths) {
                        # Check if this directory actually contains icon files
                        if (opendir(my $cdh, $content_path)) {
                            my @files = grep { /\.(svg|png)$/i } readdir($cdh);
                            closedir($cdh);

                            if (@files) {
                                my $relative = $content_path;
                                $relative =~ s/^\Q$theme_path\E\/?//;
                                push @icon_directories, {
                                    path => $content_path,
                                    relative => $relative,
                                    name => "$quality_dir/$content_dir",
                                    category => $content_dir,
                                    priority => ($quality_dir eq 'scalable') ? 1 : 2
                                };
                                print "DEBUG: Found icons in: $content_path (category: $content_dir)\n";
                            }
                        }
                    }
                }
            }
        }

        # Strategy 2: Look for content_dir/quality_dir combinations
        print "DEBUG: Strategy 2 - Looking for content/quality combinations...\n";
        foreach my $content_dir (@content_dirs) {
            my @content_paths = $find_directories->($theme_path, [$content_dir], 0, 2);
            foreach my $content_path (@content_paths) {
                foreach my $quality_dir (@quality_dirs) {
                    my @quality_paths = $find_directories->($content_path, [$quality_dir], 0, 2);
                    foreach my $quality_path (@quality_paths) {
                        # Check if this directory actually contains icon files
                        if (opendir(my $qdh, $quality_path)) {
                            my @files = grep { /\.(svg|png)$/i } readdir($qdh);
                            closedir($qdh);

                            if (@files) {
                                my $relative = $quality_path;
                                $relative =~ s/^\Q$theme_path\E\/?//;
                                push @icon_directories, {
                                    path => $quality_path,
                                    relative => $relative,
                                    name => "$content_dir/$quality_dir",
                                    category => $content_dir,
                                    priority => ($quality_dir eq 'scalable') ? 1 : 2
                                };
                                print "DEBUG: Found icons in: $quality_path (category: $content_dir)\n";
                            }
                        }
                    }
                }
            }
        }

        # Remove duplicates and sort by priority (scalable first)
        my %seen = ();
        @icon_directories = grep { !$seen{$_->{path}}++ } @icon_directories;
        @icon_directories = sort { $a->{priority} <=> $b->{priority} } @icon_directories;

        print "DEBUG: Total icon directories found: " . @icon_directories . "\n";
        if (@icon_directories) {
            print "DEBUG: Final directory list (scalable first):\n";
            for my $i (0..$#icon_directories) {
                my $type = $icon_directories[$i]->{priority} == 1 ? "SVG" : "PNG";
                print "DEBUG:   " . ($i+1) . ". " . $icon_directories[$i]->{path} . " ($type, " . $icon_directories[$i]->{category} . ")\n";
            }
        }

        return @icon_directories;
    }

    sub _process_preview_generation_queue {
        my $self = shift;

        return unless $self->{preview_generation_queue} && @{$self->{preview_generation_queue}};

        $self->{preview_generation_active} = 1;

        my $item = shift @{$self->{preview_generation_queue}};
        my $theme_name = $item->{theme_info}->{name} || '';

        # Mark as currently being generated
        $self->{currently_generating_preview} = $theme_name;

        print "Processing preview generation for: $theme_name\n";

        # Generate preview in background
        Glib::Timeout->add(50, sub {
            my $success = $self->_generate_icon_preview(
                $item->{theme_info},
                $item->{cache_file},
                $item->{width},
                $item->{height}
            );

            if ($success) {
                print "Generated preview for $theme_name\n";
                # Trigger a refresh of this specific theme widget
                $self->_refresh_theme_widget_if_visible($theme_name);
            }

            # Clear currently generating flag
            $self->{currently_generating_preview} = undef;

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

            return 0;
        });
    }

    sub _generate_icon_preview {
        my ($self, $theme_info, $output_file, $width, $height) = @_;

        print "DEBUG: Generating SHARP icon preview for: " . $theme_info->{name} . "\n";
        print "DEBUG: Preview dimensions: ${width}x${height}\n";

        # Extract available icons with higher resolution for sharpness
        my @icon_pixbufs = $self->_extract_high_res_theme_icons($theme_info, $width);

        # If we don't have any icons, don't generate a preview
        return 0 unless @icon_pixbufs > 0;

        print "DEBUG: Found " . @icon_pixbufs . " high-resolution icons for preview\n";

        # Use moderate scale factor to avoid excessive memory usage
        my $scale_factor = ($width >= 600) ? 2 : 1;  # 2x for large previews, 1x for smaller
        my $render_width = $width * $scale_factor;
        my $render_height = $height * $scale_factor;

        print "DEBUG: Rendering at ${render_width}x${render_height} (scale factor: ${scale_factor}x)\n";

        my $surface = Cairo::ImageSurface->create('argb32', $render_width, $render_height);
        my $cr = Cairo::Context->create($surface);

        # Enable high-quality rendering with correct Cairo values
        $cr->set_antialias('subpixel');  # Use 'subpixel' instead of 'best'
        
        # Scale the context for high-DPI rendering
        if ($scale_factor > 1) {
            $cr->scale($scale_factor, $scale_factor);
        }

        # Use transparent background instead of white - let theme show through
        $cr->set_source_rgba(0, 0, 0, 0);
        $cr->paint();

        # Draw available icons in a grid with high quality
        $self->_draw_high_quality_icon_grid($cr, \@icon_pixbufs, $width, $height);

        # Add subtle border like in backgrounds manager
        $cr->set_source_rgba(0, 0, 0, 0.2); # Semi-transparent black border
        $cr->set_line_width(1);
        $cr->rectangle(0.5, 0.5, $width - 1, $height - 1);
        $cr->stroke();

        # If we rendered at higher resolution, scale down with high quality
        if ($scale_factor > 1) {
            # Save high-res version first
            my $temp_file = "$output_file.tmp";
            $surface->write_to_png($temp_file);

            # Load and scale down with high quality
            eval {
                my $high_res_pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($temp_file);
                if ($high_res_pixbuf) {
                    my $final_pixbuf = $high_res_pixbuf->scale_simple($width, $height, 'hyper');
                    $final_pixbuf->save($output_file, 'png');
                }
            };
            unlink($temp_file);

            if ($@) {
                print "DEBUG: Error in high-quality scaling: $@\n";
                # Fallback to direct save
                $surface->write_to_png($output_file);
            }
        } else {
            # Save directly for smaller sizes
            $surface->write_to_png($output_file);
        }

        return (-f $output_file && -s $output_file);
    }

    sub _extract_ultra_high_res_theme_icons {
        my ($self, $theme_info, $preview_size) = @_;

        my @icon_pixbufs = ();
        my $theme_path = $theme_info->{path};

        print "DEBUG: Extracting ULTRA-HIGH-RESOLUTION icons from: $theme_path\n";
        print "DEBUG: Target preview size: $preview_size\n";

        # Calculate much higher icon resolution for ultra-sharp results
        my $icon_resolution;
        if ($preview_size >= 700) {
            $icon_resolution = 512;  # Ultra-high resolution for large previews
        } elsif ($preview_size >= 500) {
            $icon_resolution = 384;  # Very high resolution
        } elsif ($preview_size >= 350) {
            $icon_resolution = 256;  # High resolution
        } else {
            $icon_resolution = 192;  # Medium-high resolution
        }

        print "DEBUG: Using ULTRA-HIGH icon resolution: ${icon_resolution}px for preview size ${preview_size}px\n";

        # First, let's verify the theme path exists
        unless (-d $theme_path) {
            print "DEBUG: Theme path does not exist: $theme_path\n";
            return @icon_pixbufs;
        }

        # Search for each icon type directly in the theme with ultra-high resolution
        foreach my $icon_type (@{$self->icon_types}) {
            print "DEBUG: Searching for ULTRA-HIGH-RES icon type: " . $icon_type->{name} . "\n";
            my $pixbuf = $self->_find_ultra_high_res_icons($theme_path, $icon_type, $icon_resolution);
            if ($pixbuf) {
                push @icon_pixbufs, $pixbuf;
                print "DEBUG: Found ULTRA-HIGH-RES icon for " . $icon_type->{name} . "\n";
            } else {
                print "DEBUG: No ULTRA-HIGH-RES icon found for " . $icon_type->{name} . "\n";
            }
        }

        print "DEBUG: Total ULTRA-HIGH-RES icons found: " . @icon_pixbufs . "\n";
        return @icon_pixbufs;
    }

    sub _find_ultra_high_res_icons {
        my ($self, $theme_path, $icon_type, $target_resolution) = @_;

        # Get all possible icon names for this type
        my @icon_names = ($icon_type->{name}, @{$icon_type->{alternatives}}, @{$icon_type->{fallback_names}});
        my $icon_category = $icon_type->{category} || 'mimetypes';

        print "DEBUG: === ULTRA-HIGH-RES search for icon '" . $icon_type->{name} . "' at ${target_resolution}px ===\n";
        print "DEBUG: Theme path: $theme_path\n";
        print "DEBUG: Looking for names: " . join(", ", @icon_names) . "\n";
        print "DEBUG: Target category: $icon_category\n";

        # Handle different category name variations
        my @category_variations = ($icon_category);
        if ($icon_category eq 'mimetypes') {
            push @category_variations, 'mimes';
        } elsif ($icon_category eq 'mimes') {
            push @category_variations, 'mimetypes';
        }

        print "DEBUG: Category variations: " . join(", ", @category_variations) . "\n";

        # Prioritize scalable (SVG) directories with even higher priority
        my @quality_priorities = (
            { pattern => 'scalable', score => 2000, type => 'SVG' },    # Highest priority for SVG
            { pattern => '1024x1024', score => 1500, type => 'PNG' },
            { pattern => '512x512', score => 1400, type => 'PNG' },
            { pattern => '256x256', score => 1300, type => 'PNG' },
            { pattern => '192x192', score => 1200, type => 'PNG' },
            { pattern => '128x128', score => 1100, type => 'PNG' },
            { pattern => '96x96', score => 1000, type => 'PNG' },
            { pattern => '64x64', score => 900, type => 'PNG' },
            { pattern => '48x48', score => 800, type => 'PNG' },
            { pattern => 'direct', score => 700, type => 'MIXED' }  # For direct category directories
        );

        # Directories to NEVER scan (too low quality)
        my @blacklisted_dirs = ('16x16', '22x22', '24x24', '32x32', '16', '22', '24', '32');

        # Scan for ultra-high-quality directories
        my @quality_dirs = ();
        my $find_quality_dirs;
        $find_quality_dirs = sub {
            my ($dir_path, $depth) = @_;

            return if $depth > 6;
            return unless -d $dir_path;

            # Skip blacklisted directories completely
            foreach my $blacklisted (@blacklisted_dirs) {
                if ($dir_path =~ /\b\Q$blacklisted\E\b/i) {
                    print "DEBUG: SKIPPING low-quality directory: $dir_path\n";
                    return;
                }
            }

            # Check if current directory matches any of our category variations
            my $matches_category = 0;
            my $matched_category = '';
            foreach my $cat_var (@category_variations) {
                if ($dir_path =~ /\b\Q$cat_var\E\b/i) {
                    $matches_category = 1;
                    $matched_category = $cat_var;
                    last;
                }
            }

            if ($matches_category) {
                print "DEBUG: Found category directory: $dir_path (matches: $matched_category)\n";

                # Check quality level
                my $quality_info = undef;
                foreach my $priority_ref (@quality_priorities) {
                    if ($priority_ref->{pattern} eq 'direct') {
                        # This could be a direct category directory - check if it's at theme root or close
                        my $relative_path = $dir_path;
                        $relative_path =~ s/^\Q$theme_path\E\/?//;
                        # If the category is directly under theme or only 1-2 levels deep, treat as direct
                        my $depth_count = ($relative_path =~ tr/\///);
                        if ($depth_count <= 2) {
                            $quality_info = $priority_ref;
                            last;
                        }
                    } elsif ($dir_path =~ /\Q$priority_ref->{pattern}\E/i) {
                        $quality_info = $priority_ref;
                        last;
                    }
                }

                if ($quality_info) {
                    # Check if this directory contains NON-SYMBOLIC icon files
                    if (opendir(my $dh, $dir_path)) {
                        my @files = grep {
                            /\.(svg|png)$/i &&
                            !/-symbolic\./i &&
                            !/symbolic/i
                        } readdir($dh);
                        closedir($dh);

                        if (@files > 0) {
                            push @quality_dirs, {
                                path => $dir_path,
                                category => $matched_category,
                                quality => $quality_info->{pattern},
                                quality_score => $quality_info->{score},
                                type => $quality_info->{type},
                                file_count => scalar(@files)
                            };
                            print "DEBUG: Found ULTRA-HIGH-QUALITY directory: $dir_path (" . $quality_info->{type} . " " . $quality_info->{pattern} . ", files: " . @files . ")\n";
                        }
                    }
                }
            }

            # Continue scanning subdirectories
            if (opendir(my $dh, $dir_path)) {
                my @subdirs = grep { -d "$dir_path/$_" && $_ !~ /^\./ } readdir($dh);
                closedir($dh);

                foreach my $subdir (@subdirs) {
                    $find_quality_dirs->("$dir_path/$subdir", $depth + 1);
                }
            }
        };

        # Scan for quality directories
        print "DEBUG: Scanning for ULTRA-HIGH-QUALITY directories...\n";
        $find_quality_dirs->($theme_path, 0);

        # Sort by quality score (SVG scalable first with highest priority)
        @quality_dirs = sort { $b->{quality_score} <=> $a->{quality_score} } @quality_dirs;

        print "DEBUG: Found " . @quality_dirs . " ultra-high-quality directories, sorted by priority:\n";
        for my $i (0..$#quality_dirs) {
            my $dir = $quality_dirs[$i];
            print "DEBUG:   " . ($i+1) . ". " . $dir->{type} . " " . $dir->{quality} . ": " . $dir->{path} . " (score: " . $dir->{quality_score} . ")\n";
        }

        # Search through quality directories in priority order
        foreach my $dir_info (@quality_dirs) {
            my $dir_path = $dir_info->{path};

            print "DEBUG: Searching in ULTRA-HIGH-QUALITY directory: $dir_path\n";

            foreach my $icon_name (@icon_names) {
                # Reject symbolic icons
                if ($icon_name =~ /symbolic/i) {
                    next;
                }

                # For SVG directories, only look for SVG; for PNG, prefer larger sizes
                my @extensions;
                if ($dir_info->{type} eq 'SVG') {
                    @extensions = ('svg');  # Only SVG for scalable directories
                } else {
                    @extensions = ('png', 'svg');  # PNG first for raster directories
                }

                foreach my $ext (@extensions) {
                    my $icon_file = "$dir_path/$icon_name.$ext";

                    if ($icon_file =~ /symbolic/i) {
                        next;
                    }

                    if (-f $icon_file) {
                        print "DEBUG: *** FOUND ULTRA-HIGH-QUALITY ICON: $icon_file ***\n";

                        my $pixbuf = $self->_load_ultra_high_res_icon_file($icon_file, $target_resolution);
                        if ($pixbuf) {
                            print "DEBUG: *** SUCCESS: Loaded ULTRA-HIGH-RES icon: $icon_file ***\n";
                            return $pixbuf;
                        } else {
                            print "DEBUG: ERROR: Failed to load ULTRA-HIGH-RES icon: $icon_file\n";
                        }
                    }
                }
            }
        }

        print "DEBUG: === No ultra-high-quality icon found for " . $icon_type->{name} . " ===\n";
        return undef;
    }

    sub _load_ultra_high_res_icon_file {
        my ($self, $icon_file, $target_size) = @_;

        print "DEBUG: _load_ultra_high_res_icon_file called with: $icon_file (target size: $target_size)\n";

        # Check if file exists and is readable
        unless (-f $icon_file && -r $icon_file) {
            print "DEBUG: File does not exist or is not readable: $icon_file\n";
            return undef;
        }

        my $file_size = -s $icon_file;
        if ($file_size == 0) {
            print "DEBUG: File is empty: $icon_file\n";
            return undef;
        }

        my $pixbuf;
        eval {
            if ($icon_file =~ /\.svg$/i) {
                print "DEBUG: Loading SVG at ULTRA-HIGH RESOLUTION: ${target_size}px\n";
                # Load SVG at exact target size with sub-pixel precision
                $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale($icon_file, $target_size, $target_size, 1);
            } elsif ($icon_file =~ /\.png$/i) {
                print "DEBUG: Loading PNG file for ULTRA-HIGH-RES scaling...\n";
                # Load PNG at original resolution first
                my $original_pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon_file);
                if ($original_pixbuf) {
                    my $orig_width = $original_pixbuf->get_width();
                    my $orig_height = $original_pixbuf->get_height();
                    print "DEBUG: Original PNG size: ${orig_width}x${orig_height}, target: ${target_size}x${target_size}\n";

                    if ($orig_width != $target_size || $orig_height != $target_size) {
                        # Use the highest quality scaling algorithm available
                        print "DEBUG: ULTRA-HIGH-QUALITY scaling PNG to ${target_size}x${target_size}\n";
                        $pixbuf = $original_pixbuf->scale_simple($target_size, $target_size, 'hyper');
                    } else {
                        $pixbuf = $original_pixbuf;
                    }
                }
            } else {
                print "DEBUG: Loading other format at ULTRA-HIGH-RES...\n";
                my $original_pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon_file);
                if ($original_pixbuf) {
                    my $orig_width = $original_pixbuf->get_width();
                    my $orig_height = $original_pixbuf->get_height();

                    if ($orig_width != $target_size || $orig_height != $target_size) {
                        $pixbuf = $original_pixbuf->scale_simple($target_size, $target_size, 'hyper');
                    } else {
                        $pixbuf = $original_pixbuf;
                    }
                }
            }

            if ($pixbuf) {
                my $final_width = $pixbuf->get_width();
                my $final_height = $pixbuf->get_height();
                print "DEBUG: ULTRA-HIGH-RES pixbuf created: ${final_width}x${final_height}\n";
            }
        };

        if ($@) {
            print "DEBUG: Exception during ULTRA-HIGH-RES loading: $@\n";
            return undef;
        }

        return $pixbuf;
    }

    sub _draw_ultra_sharp_icon_grid {
        my ($self, $cr, $icon_pixbufs, $width, $height) = @_;

        return unless @$icon_pixbufs > 0;

        print "DEBUG: Drawing ULTRA-SHARP 4x4 icon grid with " . @$icon_pixbufs . " icons\n";
        print "DEBUG: Grid canvas size: ${width}x${height}\n";

        # Use light background as requested
        $cr->set_source_rgb(0.98, 0.98, 0.98); # Very light gray background
        $cr->rectangle(0, 0, $width, $height);
        $cr->fill();

        # Always use 4x4 grid layout for 16 icons
        my $cols = 4;
        my $rows = 4;

        my $cell_width = $width / $cols;  # Use floating point for precision
        my $cell_height = $height / $rows;

        print "DEBUG: ULTRA-SHARP cell size: ${cell_width}x${cell_height}\n";

        # Calculate icon size - use even more of the cell for larger previews
        my $margin_ratio = ($width >= 600) ? 0.03 : 0.05;  # Even smaller margins for ultra-sharp
        my $margin = ($cell_width < $cell_height ? $cell_width : $cell_height) * $margin_ratio;
        my $icon_size = ($cell_width < $cell_height ? $cell_width : $cell_height) - ($margin * 2);

        print "DEBUG: ULTRA-SHARP icon size: ${icon_size}px (margin: ${margin}px)\n";

        # Set highest quality rendering
        $cr->set_antialias('best');

        my $icon_index = 0;

        for my $row (0..$rows-1) {
            for my $col (0..$cols-1) {
                if ($icon_index < @$icon_pixbufs) {
                    my $pixbuf = $icon_pixbufs->[$icon_index];

                    if ($pixbuf) {
                        # Calculate precise position with sub-pixel accuracy
                        my $cell_x = $col * $cell_width;
                        my $cell_y = $row * $cell_height;
                        my $center_x = $cell_x + ($cell_width / 2);
                        my $center_y = $cell_y + ($cell_height / 2);

                        my $draw_x = $center_x - ($icon_size / 2);
                        my $draw_y = $center_y - ($icon_size / 2);

                        print "DEBUG: ULTRA-SHARP drawing icon $icon_index at (${draw_x}, ${draw_y}) size ${icon_size}px\n";

                        # Get current pixbuf dimensions
                        my $current_width = $pixbuf->get_width();
                        my $current_height = $pixbuf->get_height();

                        # Only scale if necessary, and use highest quality
                        my $final_size = int($icon_size);
                        my $scaled_pixbuf;

                        if ($current_width != $final_size || $current_height != $final_size) {
                            print "DEBUG: ULTRA-SHARP scaling from ${current_width}x${current_height} to ${final_size}x${final_size}\n";
                            $scaled_pixbuf = $pixbuf->scale_simple($final_size, $final_size, 'hyper');
                        } else {
                            $scaled_pixbuf = $pixbuf;
                        }

                        # Draw with sub-pixel precision and best quality
                        Gtk3::Gdk::cairo_set_source_pixbuf($cr, $scaled_pixbuf, $draw_x, $draw_y);
                        $cr->get_source()->set_filter('best');  # Highest quality filter
                        $cr->paint();
                    }

                    $icon_index++;
                }
            }
        }

        print "DEBUG: Finished ULTRA-SHARP 4x4 icon grid\n";
    }

    sub _draw_high_quality_icon_grid {
        my ($self, $cr, $icon_pixbufs, $width, $height) = @_;

        return unless @$icon_pixbufs > 0;

        print "DEBUG: Drawing HIGH-QUALITY 4x4 icon grid with " . @$icon_pixbufs . " icons\n";
        print "DEBUG: Grid canvas size: ${width}x${height}\n";

        # Use light background as requested
        $cr->set_source_rgb(0.98, 0.98, 0.98); # Very light gray background
        $cr->rectangle(0, 0, $width, $height);
        $cr->fill();

        # Always use 4x4 grid layout for 16 icons
        my $cols = 4;
        my $rows = 4;

        my $cell_width = $width / $cols;  # Use floating point for precision
        my $cell_height = $height / $rows;

        print "DEBUG: HIGH-QUALITY cell size: ${cell_width}x${cell_height}\n";

        # Calculate icon size - use more of the cell for larger previews
        my $margin_ratio = ($width >= 600) ? 0.05 : 0.08;  # Smaller margins for large previews
        my $margin = ($cell_width < $cell_height ? $cell_width : $cell_height) * $margin_ratio;
        my $icon_size = ($cell_width < $cell_height ? $cell_width : $cell_height) - ($margin * 2);

        print "DEBUG: HIGH-QUALITY icon size: ${icon_size}px (margin: ${margin}px)\n";

        # Set high-quality rendering with correct Cairo values
        $cr->set_antialias('subpixel');  # Use 'subpixel' instead of 'best'

        my $icon_index = 0;

        for my $row (0..$rows-1) {
            for my $col (0..$cols-1) {
                if ($icon_index < @$icon_pixbufs) {
                    my $pixbuf = $icon_pixbufs->[$icon_index];

                    if ($pixbuf) {
                        # Calculate precise position
                        my $cell_x = $col * $cell_width;
                        my $cell_y = $row * $cell_height;
                        my $center_x = $cell_x + ($cell_width / 2);
                        my $center_y = $cell_y + ($cell_height / 2);

                        my $draw_x = $center_x - ($icon_size / 2);
                        my $draw_y = $center_y - ($icon_size / 2);

                        print "DEBUG: HIGH-QUALITY drawing icon $icon_index at (${draw_x}, ${draw_y}) size ${icon_size}px\n";

                        # Get current pixbuf dimensions
                        my $current_width = $pixbuf->get_width();
                        my $current_height = $pixbuf->get_height();

                        # Scale to exact icon size with highest quality
                        my $final_size = int($icon_size);
                        my $scaled_pixbuf;

                        if ($current_width != $final_size || $current_height != $final_size) {
                            print "DEBUG: HIGH-QUALITY scaling from ${current_width}x${current_height} to ${final_size}x${final_size}\n";
                            $scaled_pixbuf = $pixbuf->scale_simple($final_size, $final_size, 'hyper');
                        } else {
                            $scaled_pixbuf = $pixbuf;
                        }

                        # Draw with sub-pixel precision
                        Gtk3::Gdk::cairo_set_source_pixbuf($cr, $scaled_pixbuf, $draw_x, $draw_y);
                        $cr->paint();
                    }

                    $icon_index++;
                }
            }
        }

        # Add very subtle grid lines for large previews
        if ($width >= 400) {
            $cr->set_source_rgba(0, 0, 0, 0.03); # Ultra-subtle grid lines
            $cr->set_line_width(0.5);

            # Draw vertical grid lines
            for my $col (1..$cols-1) {
                my $x = $col * $cell_width;
                $cr->move_to($x, 0);
                $cr->line_to($x, $height);
                $cr->stroke();
            }

            # Draw horizontal grid lines
            for my $row (1..$rows-1) {
                my $y = $row * $cell_height;
                $cr->move_to(0, $y);
                $cr->line_to($width, $y);
                $cr->stroke();
            }
        }

        print "DEBUG: Finished HIGH-QUALITY 4x4 icon grid\n";
    }

    sub _extract_high_res_theme_icons {
        my ($self, $theme_info, $preview_size) = @_;

        my @icon_pixbufs = ();
        my $theme_path = $theme_info->{path};

        print "DEBUG: Extracting HIGH-RESOLUTION icons from: $theme_path\n";
        print "DEBUG: Target preview size: $preview_size\n";

        # Calculate optimal icon resolution based on preview size
        my $icon_resolution;
        if ($preview_size >= 700) {
            $icon_resolution = 256;  # High resolution for large previews
        } elsif ($preview_size >= 500) {
            $icon_resolution = 192;  # Medium-high resolution
        } elsif ($preview_size >= 350) {
            $icon_resolution = 128;  # Medium resolution
        } else {
            $icon_resolution = 96;   # Standard resolution
        }

        print "DEBUG: Using icon resolution: ${icon_resolution}px for preview size ${preview_size}px\n";

        # First, let's verify the theme path exists
        unless (-d $theme_path) {
            print "DEBUG: Theme path does not exist: $theme_path\n";
            return @icon_pixbufs;
        }

        # Search for each icon type directly in the theme with high resolution
        foreach my $icon_type (@{$self->icon_types}) {
            print "DEBUG: Searching for HIGH-RES icon type: " . $icon_type->{name} . "\n";
            my $pixbuf = $self->_find_high_res_icons($theme_path, $icon_type, $icon_resolution);
            if ($pixbuf) {
                push @icon_pixbufs, $pixbuf;
                print "DEBUG: Found HIGH-RES icon for " . $icon_type->{name} . "\n";
            } else {
                print "DEBUG: No HIGH-RES icon found for " . $icon_type->{name} . "\n";
            }
        }

        print "DEBUG: Total HIGH-RES icons found: " . @icon_pixbufs . "\n";
        return @icon_pixbufs;
    }

    sub _find_high_res_icons {
        my ($self, $theme_path, $icon_type, $target_resolution) = @_;

        # Get all possible icon names for this type
        my @icon_names = ($icon_type->{name}, @{$icon_type->{alternatives}}, @{$icon_type->{fallback_names}});
        my $icon_category = $icon_type->{category} || 'mimetypes';

        print "DEBUG: === HIGH-RES search for icon '" . $icon_type->{name} . "' at ${target_resolution}px ===\n";
        print "DEBUG: Theme path: $theme_path\n";
        print "DEBUG: Looking for names: " . join(", ", @icon_names) . "\n";
        print "DEBUG: Target category: $icon_category\n";

        # Handle different category name variations
        my @category_variations = ($icon_category);
        if ($icon_category eq 'mimetypes') {
            push @category_variations, 'mimes';
        } elsif ($icon_category eq 'mimes') {
            push @category_variations, 'mimetypes';
        }

        print "DEBUG: Category variations: " . join(", ", @category_variations) . "\n";

        # Prioritize scalable (SVG) directories first, but also include direct category directories
        my @quality_priorities = (
            { pattern => 'scalable', score => 1000, type => 'SVG' },
            { pattern => '512x512', score => 900, type => 'PNG' },
            { pattern => '256x256', score => 800, type => 'PNG' },
            { pattern => '192x192', score => 700, type => 'PNG' },
            { pattern => '128x128', score => 600, type => 'PNG' },
            { pattern => '96x96', score => 500, type => 'PNG' },
            { pattern => '64x64', score => 400, type => 'PNG' },
            { pattern => '48x48', score => 300, type => 'PNG' },
            { pattern => 'direct', score => 200, type => 'MIXED' }  # For direct category directories
        );

        # Directories to NEVER scan (too low quality)
        my @blacklisted_dirs = ('16x16', '22x22', '24x24', '32x32', '16', '22', '24', '32');

        # Scan for high-quality directories
        my @quality_dirs = ();
        my $find_quality_dirs;
        $find_quality_dirs = sub {
            my ($dir_path, $depth) = @_;

            return if $depth > 6;  # Keep original depth for complex structures
            return unless -d $dir_path;

            # Skip blacklisted directories completely
            foreach my $blacklisted (@blacklisted_dirs) {
                if ($dir_path =~ /\b\Q$blacklisted\E\b/i) {
                    print "DEBUG: SKIPPING low-quality directory: $dir_path\n";
                    return;
                }
            }

            # Check if current directory matches any of our category variations
            my $matches_category = 0;
            my $matched_category = '';
            foreach my $cat_var (@category_variations) {
                if ($dir_path =~ /\b\Q$cat_var\E\b/i) {
                    $matches_category = 1;
                    $matched_category = $cat_var;
                    last;
                }
            }

            if ($matches_category) {
                print "DEBUG: Found category directory: $dir_path (matches: $matched_category)\n";

                # Check quality level
                my $quality_info = undef;
                foreach my $priority_ref (@quality_priorities) {
                    if ($priority_ref->{pattern} eq 'direct') {
                        # This could be a direct category directory - check if it's at theme root or close
                        my $relative_path = $dir_path;
                        $relative_path =~ s/^\Q$theme_path\E\/?//;
                        # If the category is directly under theme or only 1-2 levels deep, treat as direct
                        my $depth_count = ($relative_path =~ tr/\///);
                        if ($depth_count <= 2) {
                            $quality_info = $priority_ref;
                            last;
                        }
                    } elsif ($dir_path =~ /\Q$priority_ref->{pattern}\E/i) {
                        $quality_info = $priority_ref;
                        last;
                    }
                }

                if ($quality_info) {
                    # Check if this directory contains NON-SYMBOLIC icon files
                    if (opendir(my $dh, $dir_path)) {
                        my @files = grep {
                            /\.(svg|png)$/i &&
                            !/-symbolic\./i &&
                            !/symbolic/i
                        } readdir($dh);
                        closedir($dh);

                        if (@files > 0) {
                            push @quality_dirs, {
                                path => $dir_path,
                                category => $matched_category,
                                quality => $quality_info->{pattern},
                                quality_score => $quality_info->{score},
                                type => $quality_info->{type},
                                file_count => scalar(@files)
                            };
                            print "DEBUG: Found HIGH-QUALITY directory: $dir_path (" . $quality_info->{type} . " " . $quality_info->{pattern} . ", files: " . @files . ")\n";
                        }
                    }
                }
            }

            # Continue scanning subdirectories
            if (opendir(my $dh, $dir_path)) {
                my @subdirs = grep { -d "$dir_path/$_" && $_ !~ /^\./ } readdir($dh);
                closedir($dh);

                foreach my $subdir (@subdirs) {
                    $find_quality_dirs->("$dir_path/$subdir", $depth + 1);
                }
            }
        };

        # Scan for quality directories
        print "DEBUG: Scanning for HIGH-QUALITY directories...\n";
        $find_quality_dirs->($theme_path, 0);

        # Sort by quality score (SVG scalable first, then highest resolution, then direct)
        @quality_dirs = sort { $b->{quality_score} <=> $a->{quality_score} } @quality_dirs;

        print "DEBUG: Found " . @quality_dirs . " high-quality directories, sorted by priority:\n";
        for my $i (0..$#quality_dirs) {
            my $dir = $quality_dirs[$i];
            print "DEBUG:   " . ($i+1) . ". " . $dir->{type} . " " . $dir->{quality} . ": " . $dir->{path} . " (score: " . $dir->{quality_score} . ")\n";
        }

        # Search through quality directories in priority order
        foreach my $dir_info (@quality_dirs) {
            my $dir_path = $dir_info->{path};

            print "DEBUG: Searching in HIGH-QUALITY directory: $dir_path\n";

            foreach my $icon_name (@icon_names) {
                # Reject symbolic icons
                if ($icon_name =~ /symbolic/i) {
                    next;
                }

                # For mixed or SVG directories, prefer SVG; for PNG directories, prefer PNG
                my @extensions;
                if ($dir_info->{type} eq 'SVG') {
                    @extensions = ('svg', 'png');
                } elsif ($dir_info->{type} eq 'PNG') {
                    @extensions = ('png', 'svg');
                } else {  # MIXED or direct
                    @extensions = ('svg', 'png');
                }

                foreach my $ext (@extensions) {
                    my $icon_file = "$dir_path/$icon_name.$ext";

                    if ($icon_file =~ /symbolic/i) {
                        next;
                    }

                    if (-f $icon_file) {
                        print "DEBUG: *** FOUND HIGH-QUALITY ICON: $icon_file ***\n";

                        my $pixbuf = $self->_load_high_res_icon_file($icon_file, $target_resolution);
                        if ($pixbuf) {
                            print "DEBUG: *** SUCCESS: Loaded HIGH-RES icon: $icon_file ***\n";
                            return $pixbuf;
                        } else {
                            print "DEBUG: ERROR: Failed to load HIGH-RES icon: $icon_file\n";
                        }
                    }
                }
            }
        }

        print "DEBUG: === No high-quality icon found for " . $icon_type->{name} . " ===\n";
        return undef;
    }


    sub _load_high_res_icon_file {
        my ($self, $icon_file, $target_size) = @_;

        print "DEBUG: _load_high_res_icon_file called with: $icon_file (target size: $target_size)\n";

        # Check if file exists and is readable
        unless (-f $icon_file && -r $icon_file) {
            print "DEBUG: File does not exist or is not readable: $icon_file\n";
            return undef;
        }

        my $file_size = -s $icon_file;
        if ($file_size == 0) {
            print "DEBUG: File is empty: $icon_file\n";
            return undef;
        }

        my $pixbuf;
        eval {
            if ($icon_file =~ /\.svg$/i) {
                print "DEBUG: Loading SVG at HIGH RESOLUTION: ${target_size}px\n";
                # Load SVG at exact target size for maximum sharpness
                $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale($icon_file, $target_size, $target_size, 1);
            } elsif ($icon_file =~ /\.png$/i) {
                print "DEBUG: Loading PNG file for HIGH-RES scaling...\n";
                # Load PNG at original resolution first
                my $original_pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon_file);
                if ($original_pixbuf) {
                    my $orig_width = $original_pixbuf->get_width();
                    my $orig_height = $original_pixbuf->get_height();
                    print "DEBUG: Original PNG size: ${orig_width}x${orig_height}, target: ${target_size}x${target_size}\n";

                    if ($orig_width != $target_size || $orig_height != $target_size) {
                        # Use highest quality scaling algorithm
                        print "DEBUG: HIGH-QUALITY scaling PNG to ${target_size}x${target_size}\n";
                        $pixbuf = $original_pixbuf->scale_simple($target_size, $target_size, 'hyper');
                    } else {
                        $pixbuf = $original_pixbuf;
                    }
                }
            } else {
                print "DEBUG: Loading other format at HIGH-RES...\n";
                my $original_pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon_file);
                if ($original_pixbuf) {
                    my $orig_width = $original_pixbuf->get_width();
                    my $orig_height = $original_pixbuf->get_height();

                    if ($orig_width != $target_size || $orig_height != $target_size) {
                        $pixbuf = $original_pixbuf->scale_simple($target_size, $target_size, 'hyper');
                    } else {
                        $pixbuf = $original_pixbuf;
                    }
                }
            }

            if ($pixbuf) {
                my $final_width = $pixbuf->get_width();
                my $final_height = $pixbuf->get_height();
                print "DEBUG: HIGH-RES pixbuf created: ${final_width}x${final_height}\n";
            }
        };

        if ($@) {
            print "DEBUG: Exception during HIGH-RES loading: $@\n";
            return undef;
        }

        return $pixbuf;
    }

    sub _extract_theme_icons {
        my ($self, $theme_info) = @_;

        my @icon_pixbufs = ();
        my $theme_path = $theme_info->{path};

        print "DEBUG: Extracting icons from: $theme_path\n";

        # First, let's verify the theme path exists
        unless (-d $theme_path) {
            print "DEBUG: Theme path does not exist: $theme_path\n";
            return @icon_pixbufs;
        }

        # Search for each icon type directly in the theme
        foreach my $icon_type (@{$self->icon_types}) {
            print "DEBUG: Searching for icon type: " . $icon_type->{name} . "\n";
            my $pixbuf = $self->_find_icons($theme_path, $icon_type);
            if ($pixbuf) {
                push @icon_pixbufs, $pixbuf;
                print "DEBUG: Found icon for " . $icon_type->{name} . "\n";
            } else {
                print "DEBUG: No icon found for " . $icon_type->{name} . "\n";
            }
        }

        print "DEBUG: Total icons found: " . @icon_pixbufs . "\n";
        return @icon_pixbufs;
    }

    sub _find_icons {
        my ($self, $theme_path, $icon_type) = @_;

        # Get all possible icon names for this type
        my @icon_names = ($icon_type->{name}, @{$icon_type->{alternatives}}, @{$icon_type->{fallback_names}});
        my $icon_category = $icon_type->{category} || 'mimetypes';

        print "DEBUG: === Searching for icon '" . $icon_type->{name} . "' in category '$icon_category' ===\n";
        print "DEBUG: Theme path: $theme_path\n";
        print "DEBUG: Looking for names: " . join(", ", @icon_names) . "\n";

        # Handle different category name variations - support both mimes and mimetypes
        my @category_variations = ($icon_category);
        if ($icon_category eq 'mimetypes') {
            push @category_variations, 'mimes';
        } elsif ($icon_category eq 'mimes') {
            push @category_variations, 'mimetypes';
        }

        print "DEBUG: Category variations: " . join(", ", @category_variations) . "\n";

        # Keywords that indicate high-quality directories we care about
        my @quality_keywords = ('scalable', '64x64', '96x96', '48x48');

        # Directories to NEVER scan (low quality)
        my @blacklisted_dirs = ('16x16', '22x22', '24x24', '32x32', '16', '22', '24', '32');

        # First, let's scan and list directories that match our category
        my @category_dirs = ();
        my $find_category_dirs;
        $find_category_dirs = sub {
            my ($dir_path, $depth) = @_;

            return if $depth > 6;  # Keep original depth for complex structures
            return unless -d $dir_path;

            # Check if this directory path contains blacklisted sizes - SKIP COMPLETELY
            foreach my $blacklisted (@blacklisted_dirs) {
                if ($dir_path =~ /\b\Q$blacklisted\E\b/i) {
                    print "DEBUG: SKIPPING blacklisted directory: $dir_path (contains $blacklisted)\n";
                    return;
                }
            }

            # Check if current directory path contains any of our target category variations
            my $matches_category = 0;
            my $matched_category = '';
            foreach my $cat_var (@category_variations) {
                if ($dir_path =~ /\b\Q$cat_var\E\b/i) {
                    $matches_category = 1;
                    $matched_category = $cat_var;
                    last;
                }
            }

            if ($matches_category) {
                # Also check if it contains quality indicators
                my $quality_score = 0;
                my $matched_quality = '';

                if ($dir_path =~ /scalable/i) {
                    $quality_score = 100;
                    $matched_quality = 'scalable';
                } elsif ($dir_path =~ /96x96/i) {
                    $quality_score = 90;
                    $matched_quality = '96x96';
                } elsif ($dir_path =~ /64x64/i) {
                    $quality_score = 80;
                    $matched_quality = '64x64';
                } elsif ($dir_path =~ /48x48/i) {
                    $quality_score = 70;
                    $matched_quality = '48x48';
                } else {
                    # This could be a direct category directory - check depth from theme root
                    my $relative_path = $dir_path;
                    $relative_path =~ s/^\Q$theme_path\E\/?//;
                    my $depth_count = ($relative_path =~ tr/\///);

                    if ($depth_count <= 2) {
                        # This is likely a direct category directory (shallow depth)
                        $quality_score = 50;
                        $matched_quality = 'direct';
                    } else {
                        # This is a deeper category directory, lower priority
                        $quality_score = 25;
                        $matched_quality = 'nested';
                    }
                }

                # Check if this directory actually contains NON-SYMBOLIC icon files
                if (opendir(my $dh, $dir_path)) {
                    my @files = grep {
                        /\.(svg|png)$/i &&
                        !/-symbolic\./i &&
                        !/symbolic/i
                    } readdir($dh);
                    closedir($dh);

                    if (@files > 0) {
                        push @category_dirs, {
                            path => $dir_path,
                            category => $matched_category,
                            quality => $matched_quality,
                            quality_score => $quality_score,
                            file_count => scalar(@files)
                        };
                        print "DEBUG: Found category directory: $dir_path (quality: $matched_quality, score: $quality_score, files: " . @files . ")\n";
                    }
                }
            }

            # Continue scanning subdirectories
            if (opendir(my $dh, $dir_path)) {
                my @subdirs = grep { -d "$dir_path/$_" && $_ !~ /^\./ } readdir($dh);
                closedir($dh);

                foreach my $subdir (@subdirs) {
                    $find_category_dirs->("$dir_path/$subdir", $depth + 1);
                }
            }
        };

        # Scan for category directories
        print "DEBUG: Scanning for category directories...\n";
        $find_category_dirs->($theme_path, 0);

        print "DEBUG: Found " . @category_dirs . " directories for category '$icon_category'\n";

        # Sort directories by quality score (scalable first, then by size descending, then direct, then nested)
        @category_dirs = sort { $b->{quality_score} <=> $a->{quality_score} } @category_dirs;

        print "DEBUG: Sorted directories by quality:\n";
        for my $i (0..$#category_dirs) {
            my $dir = $category_dirs[$i];
            print "DEBUG:   " . ($i+1) . ". " . $dir->{quality} . ": " . $dir->{path} . " (score: " . $dir->{quality_score} . ")\n";
        }

        # Now search through the category directories we found, in priority order
        foreach my $dir_info (@category_dirs) {
            my $dir_path = $dir_info->{path};

            print "DEBUG: Searching in category directory: $dir_path\n";

            foreach my $icon_name (@icon_names) {
                # STRICTLY reject ANY symbolic icons
                if ($icon_name =~ /symbolic/i) {
                    print "DEBUG: Rejecting symbolic icon name: $icon_name\n";
                    next;
                }

                # Look for SVG first, then PNG
                foreach my $ext ('svg', 'png') {
                    my $icon_file = "$dir_path/$icon_name.$ext";

                    # STRICTLY reject ANY files with 'symbolic' in the name
                    if ($icon_file =~ /symbolic/i) {
                        print "DEBUG: Rejecting symbolic file path: $icon_file\n";
                        next;
                    }

                    if (-f $icon_file) {
                        print "DEBUG: *** FOUND ICON FILE: $icon_file ***\n";

                        print "DEBUG: Attempting to load icon file...\n";
                        my $pixbuf = $self->_load_icon_file($icon_file, 64);
                        if ($pixbuf) {
                            print "DEBUG: *** SUCCESS: Successfully loaded icon: $icon_file ***\n";
                            return $pixbuf;
                        } else {
                            print "DEBUG: ERROR: Failed to load icon: $icon_file\n";
                        }
                    }
                }
            }
        }

        print "DEBUG: === No suitable icon found for " . $icon_type->{name} . " in category '$icon_category' ===\n";
        return undef;
    }

    sub _find_icon_in_directories {
        my ($self, $icon_type, $icon_directories) = @_;

        # Get all possible icon names for this type
        my @icon_names = ($icon_type->{name}, @{$icon_type->{alternatives}}, @{$icon_type->{fallback_names}});

        print "DEBUG: === Searching for icon '" . $icon_type->{name} . "' ===\n";
        print "DEBUG: Looking for names: " . join(", ", @icon_names) . "\n";

        # Search through all discovered icon directories
        foreach my $dir_info (@$icon_directories) {
            my $icon_dir = $dir_info->{path};

            print "DEBUG: Searching in directory: $icon_dir\n";

            foreach my $icon_name (@icon_names) {
                # Look for SVG first, then PNG, then other formats
                foreach my $ext ('svg', 'png', 'xpm', 'ico') {
                    my $icon_file = "$icon_dir/$icon_name.$ext";

                    if (-f $icon_file) {
                        print "DEBUG: *** FOUND ICON FILE: $icon_file ***\n";

                        # Skip symbolic icons unless specifically looking for them
                        if ($icon_name =~ /-symbolic$/ && $icon_type->{name} !~ /-symbolic$/) {
                            print "DEBUG: Skipping symbolic icon\n";
                            next;
                        }

                        print "DEBUG: Attempting to load icon file...\n";
                        my $pixbuf = $self->_load_icon_file($icon_file, 48);
                        if ($pixbuf) {
                            print "DEBUG: *** SUCCESS: Successfully loaded icon: $icon_file ***\n";
                            return $pixbuf;
                        } else {
                            print "DEBUG: ERROR: Failed to load icon: $icon_file\n";
                        }
                    }
                }
            }
        }

        print "DEBUG: === No icon found for " . $icon_type->{name} . " in any directory ===\n";
        return undef;
    }

    sub _load_icon_file {
        my ($self, $icon_file, $target_size) = @_;

        print "DEBUG: _load_icon_file called with: $icon_file (target size: $target_size)\n";

        # Check if file exists and is readable
        unless (-f $icon_file && -r $icon_file) {
            print "DEBUG: File does not exist or is not readable: $icon_file\n";
            return undef;
        }

        my $file_size = -s $icon_file;
        print "DEBUG: File size: $file_size bytes\n";

        if ($file_size == 0) {
            print "DEBUG: File is empty: $icon_file\n";
            return undef;
        }

        # Increase target size for better quality at high zoom levels
        my $load_size = ($target_size > 96) ? 128 : $target_size;

        my $pixbuf;
        eval {
            if ($icon_file =~ /\.svg$/i) {
                print "DEBUG: Loading SVG file at size $load_size...\n";
                # Load SVG at higher resolution for better quality
                $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale($icon_file, $load_size, $load_size, 1);
            } elsif ($icon_file =~ /\.png$/i) {
                print "DEBUG: Loading PNG file...\n";
                # Load PNG and scale if necessary
                $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon_file);
                if ($pixbuf) {
                    my $width = $pixbuf->get_width();
                    my $height = $pixbuf->get_height();
                    print "DEBUG: Original PNG size: ${width}x${height}\n";

                    if ($width != $load_size || $height != $load_size) {
                        print "DEBUG: Scaling PNG from ${width}x${height} to ${load_size}x${load_size}\n";
                        $pixbuf = $pixbuf->scale_simple($load_size, $load_size, 'bilinear');
                    }
                }
            } elsif ($icon_file =~ /\.xpm$/i) {
                print "DEBUG: Loading XPM file...\n";
                # Load XPM
                $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon_file);
                if ($pixbuf) {
                    my $width = $pixbuf->get_width();
                    my $height = $pixbuf->get_height();
                    print "DEBUG: Original XPM size: ${width}x${height}\n";

                    if ($width != $load_size || $height != $load_size) {
                        print "DEBUG: Scaling XPM from ${width}x${height} to ${load_size}x${load_size}\n";
                        $pixbuf = $pixbuf->scale_simple($load_size, $load_size, 'bilinear');
                    }
                }
            } else {
                print "DEBUG: Loading other format file...\n";
                # Try to load other formats
                $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon_file);
                if ($pixbuf) {
                    my $width = $pixbuf->get_width();
                    my $height = $pixbuf->get_height();
                    print "DEBUG: Original size: ${width}x${height}\n";

                    if ($width != $load_size || $height != $load_size) {
                        print "DEBUG: Scaling from ${width}x${height} to ${load_size}x${load_size}\n";
                        $pixbuf = $pixbuf->scale_simple($load_size, $load_size, 'bilinear');
                    }
                }
            }

            if ($pixbuf) {
                my $final_width = $pixbuf->get_width();
                my $final_height = $pixbuf->get_height();
                print "DEBUG: Successfully created pixbuf: ${final_width}x${final_height}\n";
            } else {
                print "DEBUG: Pixbuf creation returned undef\n";
            }
        };

        if ($@) {
            print "DEBUG: Exception during pixbuf loading: $@\n";
            return undef;
        }

        unless ($pixbuf) {
            print "DEBUG: No pixbuf created (no exception, but result is undef)\n";
            return undef;
        }

        print "DEBUG: Successfully loaded and processed icon file: $icon_file\n";
        return $pixbuf;
    }

    sub _draw_icon_grid {
        my ($self, $cr, $icon_pixbufs, $width, $height) = @_;

        return unless @$icon_pixbufs > 0;

        print "DEBUG: Drawing 4x4 icon grid with " . @$icon_pixbufs . " icons\n";
        print "DEBUG: Grid canvas size: ${width}x${height}\n";

        # Use light background as requested
        $cr->set_source_rgb(0.98, 0.98, 0.98); # Very light gray background
        $cr->rectangle(0, 0, $width, $height);
        $cr->fill();

        # Always use 4x4 grid layout for 16 icons
        my $cols = 4;
        my $rows = 4;

        print "DEBUG: Using fixed ${cols}x${rows} grid layout\n";

        my $cell_width = int($width / $cols);
        my $cell_height = int($height / $rows);

        print "DEBUG: Cell size: ${cell_width}x${cell_height}\n";

        # Make icons fill the cells with small margin
        my $margin = 4; # Small 4px margin for better spacing
        my $icon_size = ($cell_width < $cell_height ? $cell_width : $cell_height) - ($margin * 2);

        print "DEBUG: Icon size (fills cell): ${icon_size}px\n";

        my $icon_index = 0;
        my $total_cells = $cols * $rows; # 16 cells total

        for my $row (0..$rows-1) {
            for my $col (0..$cols-1) {
                # We should have exactly 16 icons, but handle fewer gracefully
                if ($icon_index < @$icon_pixbufs) {
                    my $pixbuf = $icon_pixbufs->[$icon_index];

                    if ($pixbuf) {
                        # Calculate position to center icon in cell
                        my $cell_x = $col * $cell_width;
                        my $cell_y = $row * $cell_height;
                        my $center_x = $cell_x + int($cell_width / 2);
                        my $center_y = $cell_y + int($cell_height / 2);

                        my $draw_x = $center_x - int($icon_size / 2);
                        my $draw_y = $center_y - int($icon_size / 2);

                        print "DEBUG: Drawing icon $icon_index (row $row, col $col) at position (${draw_x}, ${draw_y}) with size ${icon_size}px\n";

                        # Scale pixbuf to fill the cell
                        my $current_width = $pixbuf->get_width();
                        my $current_height = $pixbuf->get_height();

                        print "DEBUG: Scaling icon from ${current_width}x${current_height} to ${icon_size}x${icon_size}\n";
                        my $scaled_pixbuf = $pixbuf->scale_simple($icon_size, $icon_size, 'bilinear');

                        # Draw the icon
                        Gtk3::Gdk::cairo_set_source_pixbuf($cr, $scaled_pixbuf, $draw_x, $draw_y);
                        $cr->paint();
                    }

                    $icon_index++;
                } else {
                    # If we have fewer than 16 icons, draw placeholder or leave empty
                    print "DEBUG: No icon available for position (row $row, col $col)\n";
                }
            }
        }

        # Add subtle grid lines for better visual separation
        $cr->set_source_rgba(0, 0, 0, 0.05); # Very subtle grid lines
        $cr->set_line_width(1);

        # Draw vertical grid lines
        for my $col (1..$cols-1) {
            my $x = $col * $cell_width;
            $cr->move_to($x, 0);
            $cr->line_to($x, $height);
            $cr->stroke();
        }

        # Draw horizontal grid lines
        for my $row (1..$rows-1) {
            my $y = $row * $cell_height;
            $cr->move_to(0, $y);
            $cr->line_to($width, $y);
            $cr->stroke();
        }

        print "DEBUG: Finished drawing 4x4 icon grid with light background\n";
    }

    sub _create_placeholder_pixbuf {
        my ($self, $width, $height) = @_;

        # Create a placeholder pixbuf with light background to match the icon grid
        my $surface = Cairo::ImageSurface->create('argb32', $width, $height);
        my $cr = Cairo::Context->create($surface);

        # Draw light gray background (matching the icon grid background)
        $cr->set_source_rgb(0.98, 0.98, 0.98);
        $cr->rectangle(0, 0, $width, $height);
        $cr->fill();

        # Draw border
        $cr->set_source_rgb(0.7, 0.7, 0.7);
        $cr->set_line_width(1);
        $cr->rectangle(0.5, 0.5, $width - 1, $height - 1);
        $cr->stroke();

        # Draw loading text
        $cr->set_source_rgb(0.5, 0.5, 0.5);
        $cr->select_font_face("Sans", 'normal', 'normal');
        $cr->set_font_size(12);

        my $text = "Loading...";
        my $text_extents = $cr->text_extents($text);
        my $x = ($width - $text_extents->{width}) / 2;
        my $y = ($height + $text_extents->{height}) / 2;

        $cr->move_to($x, $y);
        $cr->show_text($text);

        # Convert to pixbuf using a unique temporary file
        my $temp_file = "/tmp/placeholder_$$.png";
        $surface->write_to_png($temp_file);
        my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($temp_file);
        unlink($temp_file);

        return $pixbuf;
    }

    sub _refresh_theme_widget_if_visible {
        my ($self, $theme_name) = @_;

        # Return if theme_name is not defined
        return unless defined $theme_name && $theme_name ne '';

        # Check if this theme is currently visible and refresh its widget
        my $flowbox = $self->icons_grid;
        my $widget_found = 0;

        foreach my $child ($flowbox->get_children()) {
            my $container = $child->get_child();
            my $theme_info = $self->theme_paths->{$container + 0};

            if ($theme_info && defined $theme_info->{name} && $theme_info->{name} eq $theme_name) {
                # Only refresh the first matching widget to prevent duplicates
                if (!$widget_found) {
                    print "Refreshing widget for $theme_name\n";

                    # Replace the placeholder with the new preview
                    my $cache_file = $ENV{HOME} . "/.local/share/cinnamon-icons-theme-manager/thumbnails/${theme_name}-preview-" . $self->zoom_level . ".png";
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

                            # Get the container's children - it should be a Gtk3::Box inside the Frame
                            my @frame_children = $container->get_children();
                            if (@frame_children > 0) {
                                my $box = $frame_children[0];  # This should be the Gtk3::Box
                                if ($box && $box->isa('Gtk3::Box')) {
                                    my @box_children = $box->get_children();
                                    if (@box_children > 0) {
                                        my $old_preview = $box_children[0];  # First child should be the preview

                                        # Replace the old preview widget
                                        $box->remove($old_preview);
                                        $box->pack_start($new_preview, 1, 1, 0);
                                        $box->reorder_child($new_preview, 0); # Put it first
                                        $box->show_all();

                                        # Update widget reference
                                        $self->theme_widgets->{$container + 0} = $new_preview;
                                    }
                                }
                            }
                        }
                    }
                    $widget_found = 1;
                } else {
                    print "DEBUG: Found duplicate widget for $theme_name - this should not happen\n";
                }
            }
        }
    }

    sub _update_icon_zoom {
        my $self = shift;

        my $flowbox = $self->icons_grid;
        my $size = $self->zoom_level;

        print "DEBUG: Updating zoom to $size (fast scaling, max 800px)\n";

        # Get all children
        my @children = $flowbox->get_children();
        my $total_children = @children;

        return unless $total_children > 0;

        # Process all children immediately for instant visual feedback
        foreach my $child (@children) {
            my $frame = $child->get_child();  # FlowBoxChild -> Frame
            my $preview_widget = $self->theme_widgets->{$frame + 0};
            my $theme_info = $self->theme_paths->{$frame + 0};

            if ($preview_widget && $theme_info) {
                # Immediately update the widget size for instant visual response
                $preview_widget->set_size_request($size, int($size * 0.75));

                # Check if we already have a cached preview at this zoom level
                my $cache_file = $ENV{HOME} . "/.local/share/cinnamon-icons-theme-manager/thumbnails/" .
                            $theme_info->{name} . "-preview-$size.png";

                if (-f $cache_file && -s $cache_file) {
                    # Load existing cached preview immediately
                    eval {
                        my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale(
                            $cache_file, $size, int($size * 0.75), 1
                        );
                        if ($pixbuf) {
                            $preview_widget->set_from_pixbuf($pixbuf);
                        }
                    };
                } else {
                    # If no cached version exists, scale the current preview temporarily
                    # for immediate feedback, then schedule high-quality regeneration
                    $self->_scale_existing_preview($preview_widget, $size);

                    # Schedule high-quality preview generation in background
                    $self->_schedule_preview_generation($theme_info, $cache_file, $size, int($size * 0.75));
                }
            }
        }

        print "Zoom update completed instantly for $total_children theme previews (zoom level: $size)\n";
    }

    sub _scale_existing_preview {
        my ($self, $preview_widget, $new_size) = @_;

        # Get the current pixbuf from the preview widget
        my $current_pixbuf = $preview_widget->get_pixbuf();

        if ($current_pixbuf) {
            eval {
                # Scale the existing pixbuf to the new size for immediate feedback
                my $scaled_pixbuf = $current_pixbuf->scale_simple(
                    $new_size,
                    int($new_size * 0.75),
                    'bilinear'  # Fast scaling
                );

                if ($scaled_pixbuf) {
                    $preview_widget->set_from_pixbuf($scaled_pixbuf);
                }
            };
            if ($@) {
                print "DEBUG: Error scaling existing preview: $@\n";
            }
        }
    }

    sub _set_icon_theme {
        my ($self, $child) = @_;

        my $frame = $child->get_child();  # FlowBoxChild -> Frame
        my $theme_info = $self->theme_paths->{$frame + 0};

        return unless $theme_info;

        my $theme_name = $theme_info->{name};
        print "Setting icon theme: $theme_name\n";

        # Verify the theme exists and has proper structure
        my $index_file = $theme_info->{path} . "/index.theme";

        unless (-f $index_file) {
            my $dialog = Gtk3::MessageDialog->new(
                $self->window,
                'modal',
                'error',
                'ok',
                "Error: Theme '$theme_name' does not contain a valid index.theme file."
            );
            $dialog->run();
            $dialog->destroy();
            return;
        }

        # Apply the icon theme
        print "Applying icon theme: $theme_name\n";
        system("gsettings set org.cinnamon.desktop.interface icon-theme '$theme_name'");

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

    sub _cleanup_background_processes {
        my $self = shift;

        # Clear cached theme lists to free memory
        $self->cached_theme_lists({});

        # Clear icon cache
        $self->icon_cache({});

        print "Background processes cleaned up\n";
    }

    sub _init_config_system {
        my $self = shift;

        # Create config directory structure
        my $config_dir = $ENV{HOME} . '/.local/share/cinnamon-icons-theme-manager/config';

        unless (-d $config_dir) {
            system("mkdir -p '$config_dir'");
            print "Created config directory: $config_dir\n";
        }
    }

    sub _get_config_file_path {
        my $self = shift;
        return $ENV{HOME} . '/.local/share/cinnamon-icons-theme-manager/config/settings.json';
    }

    sub _load_config {
        my $self = shift;

        my $config_file = $self->_get_config_file_path();
        my $config = {
            preview_size => 250,
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

                    # Validate preview_size range (updated to support 800px max)
                    if ($config->{preview_size} < 200 || $config->{preview_size} > 800) {
                        print "Invalid preview size in config ($config->{preview_size}), using default\n";
                        $config->{preview_size} = 250;
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
        print "Cinnamon Icons Theme Manager started\n";
        Gtk3::main();
    }
}

# Main execution
if (!caller) {
    my $app = CinnamonIconsThemeManager->new();
    $app->run();
}

1;
