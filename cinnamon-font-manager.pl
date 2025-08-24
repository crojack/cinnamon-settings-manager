#!/usr/bin/perl
use strict;
use warnings;
use utf8;

# Cinnamon Font Manager - Standalone Application
# A dedicated font management application for Linux Mint Cinnamon
# Written in Perl with GTK3

use Gtk3 -init;
use Glib 'TRUE', 'FALSE';
use File::Spec;
use JSON qw(encode_json decode_json);
use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use File::Find qw(find);

$SIG{__WARN__} = sub {
    my $warning = shift;
    return if $warning =~ /Theme parsing error/;
    warn $warning;
};

# Main application class
package CinnamonFontManager {
    use Moo;

    has 'window' => (is => 'rw');
    has 'directory_list' => (is => 'rw');
    has 'font_list' => (is => 'rw');
    has 'search_entry' => (is => 'rw');
    has 'preview_text_view' => (is => 'rw');
    has 'preview_size' => (is => 'rw', default => sub { 24 });
    has 'directory_paths' => (is => 'rw', default => sub { {} });
    has 'font_info_cache' => (is => 'rw', default => sub { {} });
    has 'current_directory' => (is => 'rw');
    has 'config' => (is => 'rw');
    has 'last_selected_directory_path' => (is => 'rw');
    has 'loading_spinner' => (is => 'rw');
    has 'loading_label' => (is => 'rw');
    has 'loading_box' => (is => 'rw');
    has 'content_switcher' => (is => 'rw');
    has 'fonts_mode' => (is => 'rw');
    has 'settings_mode' => (is => 'rw');
    has 'sample_text' => (is => 'rw', default => sub { "The quick brown fox jumps over the lazy dog\nTHE QUICK BROWN FOX JUMPS OVER THE LAZY DOG\nABCDEF GHIJKL MNOPQR STUVWX YZ\nabcdef ghijkl mnopqr stuvwx yz\n0123456789\n! @ # \$ % ^ & * ( ) _ + - = [ ] { } | ; ' : \" , . / < > ?" });

    sub BUILD {
        my $self = shift;

        # FIXED: Ensure UTF-8 support is enabled
        binmode(STDOUT, ":utf8");
        binmode(STDERR, ":utf8");

        # Initialize font file cache
        $self->{font_file_cache} = {};

        $self->_initialize_configuration();
        $self->_setup_ui();
        $self->_populate_font_directories();
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

        # Set preview size from config
        $self->preview_size($config->{preview_size} || 24);
        $self->last_selected_directory_path($config->{last_selected_directory});

        print "Configuration initialized\n";
        print "  Preview size: " . $self->preview_size . "\n";
        print "  Custom directories: " . @{$config->{custom_directories} || []} . "\n";
        print "  Last directory: " . ($self->last_selected_directory_path || 'none') . "\n";
    }

    sub _initialize_directory_structure {
        my $self = shift;

        # Create main application directory for Cinnamon Font Manager
        my $app_dir = $ENV{HOME} . '/.local/share/cinnamon-font-manager';
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

        print "Directory structure initialized for Cinnamon Font Manager\n";
    }

    sub _setup_ui {
        my $self = shift;

        # Create main window
        my $window = Gtk3::Window->new('toplevel');
        $window->set_title('Cinnamon Font Manager');
        $window->set_default_size(1200, 900);
        $window->set_position('center');
        $window->set_icon_name('preferences-desktop-font');

        # Create header bar
        my $header = Gtk3::HeaderBar->new();
        $header->set_show_close_button(1);
        $header->set_title('Cinnamon Font Manager');
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

        # Right panel - Font display and preview
        my $right_panel = Gtk3::Frame->new();
        $right_panel->set_shadow_type('in');

        my $right_container = Gtk3::Box->new('vertical', 0);

        # Top buttons (Fonts/Settings) - above search field
        my $mode_buttons = Gtk3::Box->new('horizontal', 0);
        $mode_buttons->set_margin_left(12);
        $mode_buttons->set_margin_right(12);
        $mode_buttons->set_margin_top(12);
        $mode_buttons->set_margin_bottom(6);

        my ($fonts_mode, $settings_mode) = $self->_create_mode_buttons();

        $mode_buttons->pack_start($fonts_mode, 1, 1, 0);
        $mode_buttons->pack_start($settings_mode, 1, 1, 0);

        $right_container->pack_start($mode_buttons, 0, 0, 0);

        # Search field (only visible in Fonts tab)
        my $search_container = Gtk3::Box->new('horizontal', 6);
        $search_container->set_margin_left(12);
        $search_container->set_margin_right(12);
        $search_container->set_margin_top(6);
        $search_container->set_margin_bottom(6);

        my $search_entry = Gtk3::SearchEntry->new();
        $search_entry->set_placeholder_text('Search fonts by family, style...');
        $search_entry->set_hexpand(1);

        $search_container->pack_start($search_entry, 1, 1, 0);
        $right_container->pack_start($search_container, 0, 0, 0);

        # Content area (fonts or settings)
        my $content_switcher = Gtk3::Stack->new();
        $content_switcher->set_transition_type('slide-left-right');

        # Fonts content
        my $fonts_view = $self->_create_fonts_view();
        $content_switcher->add_named($fonts_view, 'fonts');

        # Settings content
        my $settings_view = Gtk3::ScrolledWindow->new();
        $settings_view->set_policy('automatic', 'automatic');
        my $settings_content = $self->_create_font_settings();
        $settings_view->add($settings_content);
        $content_switcher->add_named($settings_view, 'settings');

        $right_container->pack_start($content_switcher, 1, 1, 0);

        # Bottom loading indicator
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

        $right_container->pack_start($bottom_container, 0, 0, 0);

        $right_panel->add($right_container);
        $main_container->pack_start($right_panel, 1, 1, 0);

        # Store references
        $self->window($window);
        $self->directory_list($directory_list);
        $self->search_entry($search_entry);
        $self->loading_spinner($loading_spinner);
        $self->loading_label($loading_label);
        $self->loading_box($loading_box);
        $self->content_switcher($content_switcher);
        $self->fonts_mode($fonts_mode);
        $self->settings_mode($settings_mode);

        # Connect signals
        $self->_connect_signals($add_dir_button, $remove_dir_button);

        print "UI setup completed\n";
    }

    sub _create_fonts_view {
        my $self = shift;

        # Main content area - horizontal paned
        my $content_paned = Gtk3::Paned->new('horizontal');
        $content_paned->set_position(280); # Set position to exact width of font list

        # Left side - Font list with TRULY FIXED WIDTH matching left panel
        my $font_list_frame = Gtk3::Frame->new();
        $font_list_frame->set_shadow_type('in');
        $font_list_frame->set_size_request(280, -1); # Set minimum width
        $font_list_frame->set_hexpand(0); # Prevent horizontal expansion
        $font_list_frame->set_vexpand(1); # Allow vertical expansion

        my $font_scroll_window = Gtk3::ScrolledWindow->new();
        $font_scroll_window->set_policy('automatic', 'automatic');
        $font_scroll_window->set_vexpand(1);
        $font_scroll_window->set_hexpand(1); # Fill the frame
        $font_scroll_window->set_size_request(280, -1); # Set exact size

        my $font_list = Gtk3::ListBox->new();
        $font_list->set_selection_mode('single');
        $font_list->set_activate_on_single_click(1);

        $font_scroll_window->add($font_list);
        $font_list_frame->add($font_scroll_window);
        $content_paned->pack1($font_list_frame, 0, 0); # resize=0, shrink=0 for fixed width

        # Right side - Font preview
        my $preview_frame = Gtk3::Frame->new();
        $preview_frame->set_shadow_type('in');

        my $preview_container = Gtk3::Box->new('vertical', 6);
        $preview_container->set_margin_left(12);
        $preview_container->set_margin_right(12);
        $preview_container->set_margin_top(12);
        $preview_container->set_margin_bottom(12);

        # REMOVED: No more hardcoded "Preview: Sans Regular" header

        # Preview text area
        my $preview_scroll = Gtk3::ScrolledWindow->new();
        $preview_scroll->set_policy('never', 'automatic');  # Disable horizontal scrolling
        $preview_scroll->set_vexpand(1);

        my $preview_text_view = Gtk3::TextView->new();
        $preview_text_view->set_editable(1);
        $preview_text_view->set_wrap_mode('word');
        $preview_text_view->set_left_margin(10);
        $preview_text_view->set_right_margin(10);
        $preview_text_view->get_buffer()->set_text($self->sample_text);

        # REMOVED: No initial font set - will be set when first font is selected

        $preview_scroll->add($preview_text_view);
        $preview_container->pack_start($preview_scroll, 1, 1, 0);

        # Preview controls header bar (between preview and bottom panels)
        my $preview_controls_bar = Gtk3::Box->new('horizontal', 6);
        $preview_controls_bar->set_margin_left(6);
        $preview_controls_bar->set_margin_right(6);
        $preview_controls_bar->set_margin_top(6);
        $preview_controls_bar->set_margin_bottom(6);

        # Add some visual separation
        my $separator_left = Gtk3::Separator->new('horizontal');
        my $separator_right = Gtk3::Separator->new('horizontal');

        # Zoom controls (centered)
        my $preview_controls = Gtk3::Box->new('horizontal', 6);
        $preview_controls->set_halign('center');

        my ($size_decrease, $size_increase) = $self->_create_size_buttons();
        my $size_label = Gtk3::Label->new();
        $size_label->set_markup("<b>" . $self->preview_size . "pt</b>");

        $preview_controls->pack_start($size_decrease, 0, 0, 0);
        $preview_controls->pack_start($size_label, 0, 0, 0);
        $preview_controls->pack_start($size_increase, 0, 0, 0);

        $preview_controls_bar->pack_start($separator_left, 1, 1, 0);
        $preview_controls_bar->pack_start($preview_controls, 0, 0, 0);
        $preview_controls_bar->pack_start($separator_right, 1, 1, 0);

        $preview_container->pack_start($preview_controls_bar, 0, 0, 0);

        # Font Selection centered under the zoom controls
        my $font_selection_frame = Gtk3::Frame->new();
        $font_selection_frame->set_label('Font Selection');
        $font_selection_frame->set_label_align(0.02, 0.5);
        $font_selection_frame->set_halign('center');
        $font_selection_frame->set_margin_top(6);

        my $font_selection_grid = Gtk3::Grid->new();
        $font_selection_grid->set_row_spacing(8);
        $font_selection_grid->set_column_spacing(12);
        $font_selection_grid->set_margin_left(12);
        $font_selection_grid->set_margin_right(12);
        $font_selection_grid->set_margin_top(12);
        $font_selection_grid->set_margin_bottom(12);

        # Default font
        my $default_font_label = Gtk3::Label->new('Default font');
        $default_font_label->set_halign('start');
        my $default_font_button = Gtk3::FontButton->new();
        $default_font_button->set_font_name('Inter Regular 14');

        $font_selection_grid->attach($default_font_label, 0, 0, 1, 1);
        $font_selection_grid->attach($default_font_button, 1, 0, 1, 1);

        # Desktop font
        my $desktop_font_label = Gtk3::Label->new('Desktop font');
        $desktop_font_label->set_halign('start');
        my $desktop_font_button = Gtk3::FontButton->new();
        $desktop_font_button->set_font_name('Inter Display Light 14');

        $font_selection_grid->attach($desktop_font_label, 0, 1, 1, 1);
        $font_selection_grid->attach($desktop_font_button, 1, 1, 1, 1);

        # Document font
        my $document_font_label = Gtk3::Label->new('Document font');
        $document_font_label->set_halign('start');
        my $document_font_button = Gtk3::FontButton->new();
        $document_font_button->set_font_name('Sans Regular 10');

        $font_selection_grid->attach($document_font_label, 0, 2, 1, 1);
        $font_selection_grid->attach($document_font_button, 1, 2, 1, 1);

        # Monospace font
        my $monospace_font_label = Gtk3::Label->new('Monospace font');
        $monospace_font_label->set_halign('start');
        my $monospace_font_button = Gtk3::FontButton->new();
        $monospace_font_button->set_font_name('DejaVu Sans Mono Book 10');

        $font_selection_grid->attach($monospace_font_label, 0, 3, 1, 1);
        $font_selection_grid->attach($monospace_font_button, 1, 3, 1, 1);

        # Window title font
        my $window_title_font_label = Gtk3::Label->new('Window title font');
        $window_title_font_label->set_halign('start');
        my $window_title_font_button = Gtk3::FontButton->new();
        $window_title_font_button->set_font_name('Sans Regular 12');

        $font_selection_grid->attach($window_title_font_label, 0, 4, 1, 1);
        $font_selection_grid->attach($window_title_font_button, 1, 4, 1, 1);

        $font_selection_frame->add($font_selection_grid);
        $preview_container->pack_start($font_selection_frame, 0, 0, 0);

        $preview_frame->add($preview_container);
        $content_paned->pack2($preview_frame, 1, 0);

        # Store additional references
        $self->font_list($font_list);
        $self->preview_text_view($preview_text_view);
        # REMOVED: No more current_font_label reference
        $self->{default_font_button} = $default_font_button;
        $self->{desktop_font_button} = $desktop_font_button;
        $self->{document_font_button} = $document_font_button;
        $self->{monospace_font_button} = $monospace_font_button;
        $self->{window_title_font_button} = $window_title_font_button;

        # Connect font-specific signals AFTER storing references
        $self->_connect_font_signals($size_increase, $size_decrease, $size_label);

        # Connect font selection signals AFTER creating all buttons
        $self->_connect_font_selection_signals();

        # Load current system fonts into the buttons
        $self->_load_current_system_fonts();

        return $content_paned;
    }

    sub _load_current_system_fonts {
        my $self = shift;

        eval {
            # FIXED: Load current default font from Cinnamon schema
            my $default_font = `gsettings get org.cinnamon.desktop.interface font-name 2>/dev/null`;
            chomp $default_font;
            $default_font =~ s/^'|'$//g; # Remove quotes
            if ($default_font && $default_font ne '') {
                $self->{default_font_button}->set_font_name($default_font);
                print "Loaded current default font: $default_font\n";
            }

            # FIXED: Load current desktop font (same as default in Cinnamon)
            my $desktop_font = `gsettings get org.cinnamon.desktop.interface font-name 2>/dev/null`;
            chomp $desktop_font;
            $desktop_font =~ s/^'|'$//g; # Remove quotes
            if ($desktop_font && $desktop_font ne '') {
                $self->{desktop_font_button}->set_font_name($desktop_font);
                print "Loaded current desktop font: $desktop_font\n";
            }

            # Load current document font (from GNOME schema)
            my $document_font = `gsettings get org.gnome.desktop.interface document-font-name 2>/dev/null`;
            chomp $document_font;
            $document_font =~ s/^'|'$//g; # Remove quotes
            if ($document_font && $document_font ne '') {
                $self->{document_font_button}->set_font_name($document_font);
                print "Loaded current document font: $document_font\n";
            }

            # Load current monospace font (from GNOME schema)
            my $monospace_font = `gsettings get org.gnome.desktop.interface monospace-font-name 2>/dev/null`;
            chomp $monospace_font;
            $monospace_font =~ s/^'|'$//g; # Remove quotes
            if ($monospace_font && $monospace_font ne '') {
                $self->{monospace_font_button}->set_font_name($monospace_font);
                print "Loaded current monospace font: $monospace_font\n";
            }

            # FIXED: Load current window title font from Cinnamon schema
            my $title_font = `gsettings get org.cinnamon.desktop.wm.preferences titlebar-font 2>/dev/null`;
            chomp $title_font;
            $title_font =~ s/^'|'$//g; # Remove quotes
            if ($title_font && $title_font ne '') {
                $self->{window_title_font_button}->set_font_name($title_font);
                print "Loaded current window title font: $title_font\n";
            }

            print "Successfully loaded current system fonts\n";
        };
        if ($@) {
            print "Error loading current system fonts: $@\n";
        }
    }

    sub _create_font_settings_content {
        my $self = shift;

        my $font_settings_grid = Gtk3::Grid->new();
        $font_settings_grid->set_row_spacing(8);
        $font_settings_grid->set_column_spacing(12);
        $font_settings_grid->set_margin_left(12);
        $font_settings_grid->set_margin_right(12);
        $font_settings_grid->set_margin_top(12);
        $font_settings_grid->set_margin_bottom(12);

        # Text scaling factor
        my $scaling_label = Gtk3::Label->new('Text scaling factor');
        $scaling_label->set_halign('start');

        my $scaling_box = Gtk3::Box->new('horizontal', 6);
        my $scaling_spin = Gtk3::SpinButton->new_with_range(0.5, 3.0, 0.1);
        $scaling_spin->set_value(1.0);
        $scaling_spin->set_digits(1);

        my $scaling_decrease = Gtk3::Button->new_with_label('-');
        my $scaling_increase = Gtk3::Button->new_with_label('+');

        $scaling_decrease->signal_connect('clicked' => sub {
            my $current = $scaling_spin->get_value();
            $scaling_spin->set_value($current - 0.1) if $current > 0.5;
        });

        $scaling_increase->signal_connect('clicked' => sub {
            my $current = $scaling_spin->get_value();
            $scaling_spin->set_value($current + 0.1) if $current < 3.0;
        });

        $scaling_box->pack_start($scaling_spin, 0, 0, 0);
        $scaling_box->pack_start($scaling_decrease, 0, 0, 0);
        $scaling_box->pack_start($scaling_increase, 0, 0, 0);

        $font_settings_grid->attach($scaling_label, 0, 0, 1, 1);
        $font_settings_grid->attach($scaling_box, 1, 0, 1, 1);

        # Hinting
        my $hinting_label = Gtk3::Label->new('Hinting');
        $hinting_label->set_halign('start');
        my $hinting_combo = Gtk3::ComboBoxText->new();
        $hinting_combo->append_text('None');
        $hinting_combo->append_text('Slight');
        $hinting_combo->append_text('Medium');
        $hinting_combo->append_text('Full');
        $hinting_combo->set_active(1); # Slight by default

        $font_settings_grid->attach($hinting_label, 0, 1, 1, 1);
        $font_settings_grid->attach($hinting_combo, 1, 1, 1, 1);

        # Antialiasing
        my $antialiasing_label = Gtk3::Label->new('Antialiasing');
        $antialiasing_label->set_halign('start');
        my $antialiasing_combo = Gtk3::ComboBoxText->new();
        $antialiasing_combo->append_text('None');
        $antialiasing_combo->append_text('Grayscale');
        $antialiasing_combo->append_text('Subpixel');
        $antialiasing_combo->set_active(1); # Grayscale by default

        $font_settings_grid->attach($antialiasing_label, 0, 2, 1, 1);
        $font_settings_grid->attach($antialiasing_combo, 1, 2, 1, 1);

        # RGBA Order
        my $rgba_label = Gtk3::Label->new('RGBA Order');
        $rgba_label->set_halign('start');
        my $rgba_combo = Gtk3::ComboBoxText->new();
        $rgba_combo->append_text('RGB');
        $rgba_combo->append_text('BGR');
        $rgba_combo->append_text('VRGB');
        $rgba_combo->append_text('VBGR');
        $rgba_combo->set_active(0); # RGB by default

        $font_settings_grid->attach($rgba_label, 0, 3, 1, 1);
        $font_settings_grid->attach($rgba_combo, 1, 3, 1, 1);

        # Apply button
        my $apply_button = Gtk3::Button->new_with_label('Apply Settings');
        $apply_button->set_halign('center');
        $apply_button->set_margin_top(6);

        # Connect apply button signal
        $apply_button->signal_connect('clicked' => sub {
            my $scaling = $scaling_spin->get_value();
            my $hinting = $hinting_combo->get_active_text();
            my $antialiasing = $antialiasing_combo->get_active_text();
            my $rgba = $rgba_combo->get_active_text();

            print "Applying font settings:\n";
            print "  Text scaling: $scaling\n";
            print "  Hinting: $hinting\n";
            print "  Antialiasing: $antialiasing\n";
            print "  RGBA Order: $rgba\n";

            # Apply settings using gsettings
            system("gsettings set org.gnome.desktop.interface text-scaling-factor $scaling");

            # Map hinting values
            my %hinting_map = (
                'None' => 'none',
                'Slight' => 'slight',
                'Medium' => 'medium',
                'Full' => 'full'
            );
            my $hinting_value = $hinting_map{$hinting} || 'slight';
            system("gsettings set org.gnome.desktop.interface font-hinting '$hinting_value'");

            # Map antialiasing values
            my %antialiasing_map = (
                'None' => 'none',
                'Grayscale' => 'grayscale',
                'Subpixel' => 'rgba'
            );
            my $antialiasing_value = $antialiasing_map{$antialiasing} || 'grayscale';
            system("gsettings set org.gnome.desktop.interface font-antialiasing '$antialiasing_value'");

            # Map RGBA order values
            my %rgba_map = (
                'RGB' => 'rgb',
                'BGR' => 'bgr',
                'VRGB' => 'vrgb',
                'VBGR' => 'vbgr'
            );
            my $rgba_value = $rgba_map{$rgba} || 'rgb';
            system("gsettings set org.gnome.desktop.interface font-rgba-order '$rgba_value'");

            # Show confirmation
            my $info_dialog = Gtk3::MessageDialog->new(
                $self->window,
                'modal',
                'info',
                'ok',
                'Font settings have been applied successfully!'
            );
            $info_dialog->run();
            $info_dialog->destroy();
        });

        $font_settings_grid->attach($apply_button, 0, 4, 2, 1);

        return $font_settings_grid;
    }

    sub _connect_signals {
        my ($self, $add_dir_button, $remove_dir_button) = @_;

        # Connect signals for mode buttons
        $self->_connect_mode_button_signals($self->fonts_mode, $self->settings_mode, $self->content_switcher, $self->search_entry->get_parent());

        # FIXED: Add a flag to prevent duplicate directory loading
        my $loading_in_progress = 0;

        $self->directory_list->signal_connect('row-selected' => sub {
            my ($widget, $row) = @_;
            return unless $row;

            # Prevent duplicate loading
            return if $loading_in_progress;
            $loading_in_progress = 1;

            # Save the selected directory to config
            my $dir_path = $self->directory_paths->{$row + 0};
            if ($dir_path) {
                $self->config->{last_selected_directory} = $dir_path;
                $self->_save_config($self->config);
            }

            $self->_load_fonts_from_directory_async($row);

            # Reset the flag after a delay
            Glib::Timeout->add(1000, sub {
                $loading_in_progress = 0;
                return 0;
            });
        });

        $self->search_entry->signal_connect('search-changed' => sub {
            $self->_filter_fonts();
        });

        $add_dir_button->signal_connect('clicked' => sub {
            $self->_add_font_directory();
        });

        $remove_dir_button->signal_connect('clicked' => sub {
            $self->_remove_font_directory();
        });

        $self->window->signal_connect('destroy' => sub {
            # Save configuration before closing
            $self->_save_config($self->config);
            Gtk3::main_quit();
        });

        print "Signal connections completed\n";
    }

    sub _connect_mode_button_signals {
        my ($self, $fonts_mode, $settings_mode, $content_switcher, $search_container) = @_;

        # Handle clicks for fonts mode button
        $fonts_mode->signal_connect('toggled' => sub {
            my $widget = shift;
            if ($widget->get_active()) {
                $settings_mode->set_active(0);
                $content_switcher->set_visible_child_name('fonts');
                $search_container->show(); # Show search field in Fonts tab
            }
        });

        # Handle clicks for settings mode button
        $settings_mode->signal_connect('toggled' => sub {
            my $widget = shift;
            if ($widget->get_active()) {
                $fonts_mode->set_active(0);
                $content_switcher->set_visible_child_name('settings');
                $search_container->hide(); # Hide search field in Settings tab
            }
        });
    }

    sub _connect_font_signals {
        my ($self, $size_increase, $size_decrease, $size_label) = @_;

        $self->font_list->signal_connect('row-selected' => sub {
            my ($widget, $row) = @_;
            return unless $row;
            $self->_update_font_preview($row);
        });

        $size_increase->signal_connect('clicked' => sub {
            # Changed increment from 4 to 2 for gradual size increase
            my $new_size = ($self->preview_size < 72) ? $self->preview_size + 2 : 72;
            $self->preview_size($new_size);
            $size_label->set_markup("<b>${new_size}pt</b>");
            $self->_update_preview_font_size();
            # Save size to config
            $self->config->{preview_size} = $self->preview_size;
            $self->_save_config($self->config);
        });

        $size_decrease->signal_connect('clicked' => sub {
            # Changed decrement from 4 to 2 for gradual size decrease
            my $new_size = ($self->preview_size > 8) ? $self->preview_size - 2 : 8;
            $self->preview_size($new_size);
            $size_label->set_markup("<b>${new_size}pt</b>");
            $self->_update_preview_font_size();
            # Save size to config
            $self->config->{preview_size} = $self->preview_size;
            $self->_save_config($self->config);
        });
    }

    sub _connect_font_selection_signals {
        my $self = shift;

        # Connect signal to apply default font globally
        $self->{default_font_button}->signal_connect('font-set' => sub {
            my $widget = shift;
            my $font_name = $widget->get_font_name();
            print "Applying default font: $font_name\n";

            # Apply to both Cinnamon and GNOME schemas for maximum compatibility
            my $cinnamon_result = system("gsettings set org.cinnamon.desktop.interface font-name '$font_name' 2>/dev/null");
            my $gnome_result = system("gsettings set org.gnome.desktop.interface font-name '$font_name' 2>/dev/null");

            # Also try the legacy GTK schema
            my $gtk_result = system("gsettings set org.gnome.desktop.interface gtk-font-name '$font_name' 2>/dev/null");

            if ($cinnamon_result == 0 || $gnome_result == 0 || $gtk_result == 0) {
                print "Successfully applied default font: $font_name\n";

                # Force font cache refresh
                system("fc-cache -f 2>/dev/null &");

                # Try to restart Cinnamon's font rendering (non-blocking)
                system("dbus-send --type=method_call --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ReloadConfig 2>/dev/null &");

                # Show confirmation with instructions
                my $info_dialog = Gtk3::MessageDialog->new(
                    $self->window,
                    'modal',
                    'info',
                    'ok',
                    "Default font set to: $font_name\n\n" .
                    "Note: Some applications may require a restart to show the new font.\n" .
                    "If changes don't appear immediately, try:\n" .
                    "• Log out and log back in\n" .
                    "• Restart specific applications\n" .
                    "• Run 'fc-cache -f' in terminal"
                );
                $info_dialog->run();
                $info_dialog->destroy();
            } else {
                print "ERROR: Failed to apply default font\n";
                my $error_dialog = Gtk3::MessageDialog->new(
                    $self->window,
                    'modal',
                    'error',
                    'ok',
                    "Failed to apply default font. Please check if gsettings is available and you have proper permissions."
                );
                $error_dialog->run();
                $error_dialog->destroy();
            }
        });

        # Connect signal to apply desktop font globally (same as default for Cinnamon)
        $self->{desktop_font_button}->signal_connect('font-set' => sub {
            my $widget = shift;
            my $font_name = $widget->get_font_name();
            print "Applying desktop font: $font_name\n";

            # Apply to both Cinnamon and GNOME schemas
            my $cinnamon_result = system("gsettings set org.cinnamon.desktop.interface font-name '$font_name' 2>/dev/null");
            my $gnome_result = system("gsettings set org.gnome.desktop.interface font-name '$font_name' 2>/dev/null");

            # Also apply to Nemo file manager specifically
            my $nemo_result = system("gsettings set org.nemo.desktop font '$font_name' 2>/dev/null");

            if ($cinnamon_result == 0 || $gnome_result == 0) {
                print "Successfully applied desktop font: $font_name\n";

                # Force font cache refresh
                system("fc-cache -f 2>/dev/null &");

                # Try to refresh desktop (non-blocking)
                system("dbus-send --type=method_call --dest=org.Cinnamon /org/Cinnamon org.Cinnamon.RestartCinnamon 2>/dev/null &");

                # Show confirmation
                my $info_dialog = Gtk3::MessageDialog->new(
                    $self->window,
                    'modal',
                    'info',
                    'ok',
                    "Desktop font set to: $font_name\n\n" .
                    "Desktop elements should update shortly.\n" .
                    "If changes don't appear, try pressing Alt+F2 and type 'r' to restart Cinnamon."
                );
                $info_dialog->run();
                $info_dialog->destroy();
            } else {
                print "ERROR: Failed to apply desktop font\n";
                my $error_dialog = Gtk3::MessageDialog->new(
                    $self->window,
                    'modal',
                    'error',
                    'ok',
                    "Failed to apply desktop font. Please check your Cinnamon installation."
                );
                $error_dialog->run();
                $error_dialog->destroy();
            }
        });

        # Connect signal to apply document font globally
        $self->{document_font_button}->signal_connect('font-set' => sub {
            my $widget = shift;
            my $font_name = $widget->get_font_name();
            print "Applying document font: $font_name\n";

            # Apply to GNOME schema (Cinnamon inherits this)
            my $result = system("gsettings set org.gnome.desktop.interface document-font-name '$font_name' 2>/dev/null");

            # Also try setting it for LibreOffice if available
            system("gsettings set org.libreoffice.registry.org.openoffice.Office.Common.Font DefaultFontName '$font_name' 2>/dev/null");

            if ($result == 0) {
                print "Successfully applied document font: $font_name\n";

                # Force font cache refresh
                system("fc-cache -f 2>/dev/null &");

                # Show confirmation
                my $info_dialog = Gtk3::MessageDialog->new(
                    $self->window,
                    'modal',
                    'info',
                    'ok',
                    "Document font set to: $font_name\n\n" .
                    "This affects text editors, office applications, and other document viewers.\n" .
                    "You may need to restart applications to see the changes."
                );
                $info_dialog->run();
                $info_dialog->destroy();
            } else {
                print "ERROR: Failed to apply document font\n";
                my $error_dialog = Gtk3::MessageDialog->new(
                    $self->window,
                    'modal',
                    'error',
                    'ok',
                    "Failed to apply document font."
                );
                $error_dialog->run();
                $error_dialog->destroy();
            }
        });

        # Connect signal to apply monospace font globally
        $self->{monospace_font_button}->signal_connect('font-set' => sub {
            my $widget = shift;
            my $font_name = $widget->get_font_name();
            print "Applying monospace font: $font_name\n";

            # Apply to GNOME schema (Cinnamon inherits this)
            my $result = system("gsettings set org.gnome.desktop.interface monospace-font-name '$font_name' 2>/dev/null");

            # Also try setting it for terminal applications
            system("gsettings set org.gnome.desktop.default-applications.terminal exec-arg '--font=\"$font_name\"' 2>/dev/null");

            if ($result == 0) {
                print "Successfully applied monospace font: $font_name\n";

                # Force font cache refresh
                system("fc-cache -f 2>/dev/null &");

                # Show confirmation
                my $info_dialog = Gtk3::MessageDialog->new(
                    $self->window,
                    'modal',
                    'info',
                    'ok',
                    "Monospace font set to: $font_name\n\n" .
                    "This affects terminals, code editors, and fixed-width text.\n" .
                    "Open a new terminal window to see the changes."
                );
                $info_dialog->run();
                $info_dialog->destroy();
            } else {
                print "ERROR: Failed to apply monospace font\n";
                my $error_dialog = Gtk3::MessageDialog->new(
                    $self->window,
                    'modal',
                    'error',
                    'ok',
                    "Failed to apply monospace font."
                );
                $error_dialog->run();
                $error_dialog->destroy();
            }
        });

        # Connect signal to apply window title font globally
        $self->{window_title_font_button}->signal_connect('font-set' => sub {
            my $widget = shift;
            my $font_name = $widget->get_font_name();
            print "Applying window title font: $font_name\n";

            # Apply to Cinnamon window manager schema
            my $cinnamon_result = system("gsettings set org.cinnamon.desktop.wm.preferences titlebar-font '$font_name' 2>/dev/null");

            # Also try the GNOME WM schema as fallback
            my $gnome_result = system("gsettings set org.gnome.desktop.wm.preferences titlebar-font '$font_name' 2>/dev/null");

            if ($cinnamon_result == 0 || $gnome_result == 0) {
                print "Successfully applied window title font: $font_name\n";

                # Force font cache refresh
                system("fc-cache -f 2>/dev/null &");

                # Try to refresh window manager (non-blocking)
                system("dbus-send --type=method_call --dest=org.Cinnamon /org/Cinnamon org.Cinnamon.RestartCinnamon 2>/dev/null &");

                # Show confirmation
                my $info_dialog = Gtk3::MessageDialog->new(
                    $self->window,
                    'modal',
                    'info',
                    'ok',
                    "Window title font set to: $font_name\n\n" .
                    "Window titles should update shortly.\n" .
                    "If changes don't appear, try pressing Alt+F2 and type 'r' to restart Cinnamon."
                );
                $info_dialog->run();
                $info_dialog->destroy();
            } else {
                print "ERROR: Failed to apply window title font\n";
                my $error_dialog = Gtk3::MessageDialog->new(
                    $self->window,
                    'modal',
                    'error',
                    'ok',
                    "Failed to apply window title font."
                );
                $error_dialog->run();
                $error_dialog->destroy();
            }
        });

        print "Font selection signals connected\n";
    }

    sub _create_directory_buttons {
        my $self = shift;

        my $add_button = Gtk3::Button->new();
        $add_button->set_relief('none');
        $add_button->set_size_request(32, 32);
        $add_button->set_tooltip_text('Add font directory');

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

    sub _create_size_buttons {
        my $self = shift;

        my $size_decrease = Gtk3::Button->new();
        $size_decrease->set_relief('none');
        $size_decrease->set_size_request(32, 32);
        $size_decrease->set_tooltip_text('Decrease font preview size');

        my $size_increase = Gtk3::Button->new();
        $size_increase->set_relief('none');
        $size_increase->set_size_request(32, 32);
        $size_increase->set_tooltip_text('Increase font preview size');

        my $decrease_icon = Gtk3::Image->new_from_icon_name('zoom-out-symbolic', 1);
        $size_decrease->add($decrease_icon);

        my $increase_icon = Gtk3::Image->new_from_icon_name('zoom-in-symbolic', 1);
        $size_increase->add($increase_icon);

        return ($size_decrease, $size_increase);
    }

    sub _create_mode_buttons {
        my $self = shift;

        my $fonts_mode = Gtk3::ToggleButton->new_with_label('Fonts');
        my $settings_mode = Gtk3::ToggleButton->new_with_label('Settings');

        $fonts_mode->set_active(1); # Active by default

        return ($fonts_mode, $settings_mode);
    }

    sub _create_font_settings {
        my $self = shift;

        my $settings_box = Gtk3::Box->new('vertical', 12);
        $settings_box->set_margin_left(20);
        $settings_box->set_margin_right(20);
        $settings_box->set_margin_top(20);
        $settings_box->set_margin_bottom(20);

        # Font Settings section
        my $font_settings_frame = Gtk3::Frame->new();
        $font_settings_frame->set_label('Font Rendering Settings');
        $font_settings_frame->set_label_align(0.02, 0.5);

        my $font_settings_grid = Gtk3::Grid->new();
        $font_settings_grid->set_row_spacing(12);
        $font_settings_grid->set_column_spacing(12);
        $font_settings_grid->set_margin_left(12);
        $font_settings_grid->set_margin_right(12);
        $font_settings_grid->set_margin_top(12);
        $font_settings_grid->set_margin_bottom(12);

        # Text scaling factor
        my $scaling_label = Gtk3::Label->new('Text scaling factor');
        $scaling_label->set_halign('start');

        my $scaling_box = Gtk3::Box->new('horizontal', 6);
        my $scaling_spin = Gtk3::SpinButton->new_with_range(0.5, 3.0, 0.1);
        $scaling_spin->set_digits(1);

        # FIXED: Load current scaling value from Cinnamon schema
        my $current_scaling = `gsettings get org.cinnamon.desktop.interface text-scaling-factor 2>/dev/null`;
        chomp $current_scaling;
        if ($current_scaling && $current_scaling ne '') {
            $scaling_spin->set_value($current_scaling);
        } else {
            $scaling_spin->set_value(1.0);
        }

        my $scaling_decrease = Gtk3::Button->new_with_label('-');
        my $scaling_increase = Gtk3::Button->new_with_label('+');

        $scaling_decrease->signal_connect('clicked' => sub {
            my $current = $scaling_spin->get_value();
            $scaling_spin->set_value($current - 0.1) if $current > 0.5;
        });

        $scaling_increase->signal_connect('clicked' => sub {
            my $current = $scaling_spin->get_value();
            $scaling_spin->set_value($current + 0.1) if $current < 3.0;
        });

        $scaling_box->pack_start($scaling_spin, 0, 0, 0);
        $scaling_box->pack_start($scaling_decrease, 0, 0, 0);
        $scaling_box->pack_start($scaling_increase, 0, 0, 0);

        $font_settings_grid->attach($scaling_label, 0, 0, 1, 1);
        $font_settings_grid->attach($scaling_box, 1, 0, 1, 1);

        # Hinting
        my $hinting_label = Gtk3::Label->new('Hinting');
        $hinting_label->set_halign('start');
        my $hinting_combo = Gtk3::ComboBoxText->new();
        $hinting_combo->append_text('None');
        $hinting_combo->append_text('Slight');
        $hinting_combo->append_text('Medium');
        $hinting_combo->append_text('Full');

        # Load current hinting value
        my $current_hinting = `gsettings get org.gnome.desktop.interface font-hinting 2>/dev/null`;
        chomp $current_hinting;
        $current_hinting =~ s/^'|'$//g; # Remove quotes
        my %hinting_index = ('none' => 0, 'slight' => 1, 'medium' => 2, 'full' => 3);
        if ($current_hinting && exists $hinting_index{$current_hinting}) {
            $hinting_combo->set_active($hinting_index{$current_hinting});
        } else {
            $hinting_combo->set_active(1); # Default to slight
        }

        $font_settings_grid->attach($hinting_label, 0, 1, 1, 1);
        $font_settings_grid->attach($hinting_combo, 1, 1, 1, 1);

        # Antialiasing
        my $antialiasing_label = Gtk3::Label->new('Antialiasing');
        $antialiasing_label->set_halign('start');
        my $antialiasing_combo = Gtk3::ComboBoxText->new();
        $antialiasing_combo->append_text('None');
        $antialiasing_combo->append_text('Grayscale');
        $antialiasing_combo->append_text('Subpixel');

        # Load current antialiasing value
        my $current_antialiasing = `gsettings get org.gnome.desktop.interface font-antialiasing 2>/dev/null`;
        chomp $current_antialiasing;
        $current_antialiasing =~ s/^'|'$//g; # Remove quotes
        my %antialiasing_index = ('none' => 0, 'grayscale' => 1, 'rgba' => 2);
        if ($current_antialiasing && exists $antialiasing_index{$current_antialiasing}) {
            $antialiasing_combo->set_active($antialiasing_index{$current_antialiasing});
        } else {
            $antialiasing_combo->set_active(1); # Default to grayscale
        }

        $font_settings_grid->attach($antialiasing_label, 0, 2, 1, 1);
        $font_settings_grid->attach($antialiasing_combo, 1, 2, 1, 1);

        # RGBA Order
        my $rgba_label = Gtk3::Label->new('RGBA Order');
        $rgba_label->set_halign('start');
        my $rgba_combo = Gtk3::ComboBoxText->new();
        $rgba_combo->append_text('RGB');
        $rgba_combo->append_text('BGR');
        $rgba_combo->append_text('VRGB');
        $rgba_combo->append_text('VBGR');

        # Load current RGBA order value
        my $current_rgba = `gsettings get org.gnome.desktop.interface font-rgba-order 2>/dev/null`;
        chomp $current_rgba;
        $current_rgba =~ s/^'|'$//g; # Remove quotes
        my %rgba_index = ('rgb' => 0, 'bgr' => 1, 'vrgb' => 2, 'vbgr' => 3);
        if ($current_rgba && exists $rgba_index{$current_rgba}) {
            $rgba_combo->set_active($rgba_index{$current_rgba});
        } else {
            $rgba_combo->set_active(0); # Default to RGB
        }

        $font_settings_grid->attach($rgba_label, 0, 3, 1, 1);
        $font_settings_grid->attach($rgba_combo, 1, 3, 1, 1);

        $font_settings_frame->add($font_settings_grid);
        $settings_box->pack_start($font_settings_frame, 0, 0, 0);

        # FIXED: Apply button with proper Cinnamon schema support
        my $apply_button = Gtk3::Button->new_with_label('Apply Settings');
        $apply_button->set_halign('center');

        # Connect apply button signal
        $apply_button->signal_connect('clicked' => sub {
            my $scaling = $scaling_spin->get_value();
            my $hinting = $hinting_combo->get_active_text();
            my $antialiasing = $antialiasing_combo->get_active_text();
            my $rgba = $rgba_combo->get_active_text();

            print "Applying font rendering settings:\n";
            print "  Text scaling: $scaling\n";
            print "  Hinting: $hinting\n";
            print "  Antialiasing: $antialiasing\n";
            print "  RGBA Order: $rgba\n";

            my $all_success = 1;
            my @errors = ();

            # FIXED: Apply text scaling factor to both Cinnamon and GNOME schemas
            my $cinnamon_scaling_result = system("gsettings set org.cinnamon.desktop.interface text-scaling-factor $scaling");
            my $gnome_scaling_result = system("gsettings set org.gnome.desktop.interface text-scaling-factor $scaling");

            if ($cinnamon_scaling_result != 0) {
                push @errors, "Failed to set Cinnamon text scaling factor";
                $all_success = 0;
            }
            if ($gnome_scaling_result != 0) {
                push @errors, "Failed to set GNOME text scaling factor";
                $all_success = 0;
            }

            # Apply hinting settings
            my %hinting_map = (
                'None' => 'none',
                'Slight' => 'slight',
                'Medium' => 'medium',
                'Full' => 'full'
            );
            my $hinting_value = $hinting_map{$hinting} || 'slight';
            my $hinting_result = system("gsettings set org.gnome.desktop.interface font-hinting '$hinting_value'");
            if ($hinting_result != 0) {
                push @errors, "Failed to set font hinting";
                $all_success = 0;
            }

            # Apply antialiasing settings
            my %antialiasing_map = (
                'None' => 'none',
                'Grayscale' => 'grayscale',
                'Subpixel' => 'rgba'
            );
            my $antialiasing_value = $antialiasing_map{$antialiasing} || 'grayscale';
            my $antialiasing_result = system("gsettings set org.gnome.desktop.interface font-antialiasing '$antialiasing_value'");
            if ($antialiasing_result != 0) {
                push @errors, "Failed to set font antialiasing";
                $all_success = 0;
            }

            # Apply RGBA order settings
            my %rgba_map = (
                'RGB' => 'rgb',
                'BGR' => 'bgr',
                'VRGB' => 'vrgb',
                'VBGR' => 'vbgr'
            );
            my $rgba_value = $rgba_map{$rgba} || 'rgb';
            my $rgba_result = system("gsettings set org.gnome.desktop.interface font-rgba-order '$rgba_value'");
            if ($rgba_result != 0) {
                push @errors, "Failed to set RGBA order";
                $all_success = 0;
            }

            # Show appropriate confirmation or error message
            if ($all_success) {
                my $info_dialog = Gtk3::MessageDialog->new(
                    $self->window,
                    'modal',
                    'info',
                    'ok',
                    "Font rendering settings applied successfully!\n\n" .
                    "Text scaling: ${scaling}x\n" .
                    "Hinting: $hinting\n" .
                    "Antialiasing: $antialiasing\n" .
                    "RGBA Order: $rgba\n\n" .
                    "• Text scaling changes take effect immediately\n" .
                    "• Hinting/antialiasing improve for new applications\n" .
                    "• Test by opening a new text editor or terminal"
                );
                $info_dialog->run();
                $info_dialog->destroy();
            } else {
                my $error_msg = "Some settings failed to apply:\n" . join("\n", @errors);
                my $error_dialog = Gtk3::MessageDialog->new(
                    $self->window,
                    'modal',
                    'error',
                    'ok',
                    $error_msg
                );
                $error_dialog->run();
                $error_dialog->destroy();
            }
        });

        $settings_box->pack_start($apply_button, 0, 0, 12);

        # Reset to Defaults button
        my $reset_button = Gtk3::Button->new_with_label('Reset to Defaults');
        $reset_button->set_halign('center');

        $reset_button->signal_connect('clicked' => sub {
            print "Resetting font rendering settings to defaults\n";

            # Reset all settings to their defaults
            system("gsettings reset org.cinnamon.desktop.interface text-scaling-factor");
            system("gsettings reset org.gnome.desktop.interface text-scaling-factor");
            system("gsettings reset org.gnome.desktop.interface font-hinting");
            system("gsettings reset org.gnome.desktop.interface font-antialiasing");
            system("gsettings reset org.gnome.desktop.interface font-rgba-order");

            # Update the UI controls to reflect the defaults
            $scaling_spin->set_value(1.0);
            $hinting_combo->set_active(1);        # Slight
            $antialiasing_combo->set_active(1);   # Grayscale
            $rgba_combo->set_active(0);           # RGB

            my $info_dialog = Gtk3::MessageDialog->new(
                $self->window,
                'modal',
                'info',
                'ok',
                "Font rendering settings have been reset to defaults."
            );
            $info_dialog->run();
            $info_dialog->destroy();
        });

        $settings_box->pack_start($reset_button, 0, 0, 0);

        # FIXED: Enhanced testing section with better examples
        my $testing_frame = Gtk3::Frame->new();
        $testing_frame->set_label('Testing Instructions');
        $testing_frame->set_label_align(0.02, 0.5);
        $testing_frame->set_margin_top(12);

        my $testing_container = Gtk3::Box->new('vertical', 8);
        $testing_container->set_margin_left(12);
        $testing_container->set_margin_right(12);
        $testing_container->set_margin_top(12);
        $testing_container->set_margin_bottom(12);

        # Text scaling test instructions
        my $scaling_test_label = Gtk3::Label->new();
        $scaling_test_label->set_markup(
            "<b>Text Scaling Test:</b>\n" .
            "• Change the scaling factor above and click Apply\n" .
            "• Text in this dialog and menus should resize immediately\n" .
            "• Open a new application (text editor, terminal) to see the effect\n" .
            "• Values: 1.0 = normal, 1.2 = 20% larger, 1.5 = 50% larger"
        );
        $scaling_test_label->set_halign('start');
        $scaling_test_label->set_line_wrap(1);

        $testing_container->pack_start($scaling_test_label, 0, 0, 0);

        # Hinting/Antialiasing test instructions
        my $rendering_test_label = Gtk3::Label->new();
        $rendering_test_label->set_markup(
            "<b>Hinting/Antialiasing Test:</b>\n" .
            "• Best tested with small fonts (8-12pt) at high zoom\n" .
            "• Open a text editor and type: 'lp db qg' in small font\n" .
            "• Hinting: None=fuzzy, Slight=sharp, Medium=sharper, Full=sharpest\n" .
            "• Antialiasing: None=jagged, Grayscale=smooth, Subpixel=LCD optimized\n" .
            "• RGBA Order: Depends on your LCD panel (most use RGB)"
        );
        $rendering_test_label->set_halign('start');
        $rendering_test_label->set_line_wrap(1);

        $testing_container->pack_start($rendering_test_label, 0, 0, 0);

        # Quick test buttons
        my $test_buttons_box = Gtk3::Box->new('horizontal', 6);
        $test_buttons_box->set_halign('center');
        $test_buttons_box->set_margin_top(8);

        my $test_editor_button = Gtk3::Button->new_with_label('Open Text Editor');
        $test_editor_button->signal_connect('clicked' => sub {
            system("xed &");
        });

        my $test_terminal_button = Gtk3::Button->new_with_label('Open Terminal');
        $test_terminal_button->signal_connect('clicked' => sub {
            system("gnome-terminal &");
        });

        $test_buttons_box->pack_start($test_editor_button, 0, 0, 0);
        $test_buttons_box->pack_start($test_terminal_button, 0, 0, 0);

        $testing_container->pack_start($test_buttons_box, 0, 0, 0);

        $testing_frame->add($testing_container);
        $settings_box->pack_start($testing_frame, 0, 0, 0);

        return $settings_box;
    }

    sub _populate_font_directories {
        my $self = shift;

        # Default font directories
        my @default_dirs = (
            { name => 'System Fonts', path => '/usr/share/fonts' },
            { name => 'Local Fonts', path => '/usr/local/share/fonts' },
            { name => 'User Fonts', path => $ENV{HOME} . '/.fonts' },
            { name => 'User Local Fonts', path => $ENV{HOME} . '/.local/share/fonts' },
        );

        # Add default directories that exist
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

        print "Populated font directories\n";
    }

    sub _create_directory_row {
        my ($self, $name, $path) = @_;

        my $row = Gtk3::ListBoxRow->new();
        $row->set_size_request(-1, 40); # Reduced from 48 to make smaller

        my $box = Gtk3::Box->new('horizontal', 8);
        $box->set_margin_left(8);
        $box->set_margin_right(8);
        $box->set_margin_top(4); # Reduced margins
        $box->set_margin_bottom(4);

        # Folder icon
        my $icon = Gtk3::Image->new_from_icon_name('folder', 'menu'); # Smaller icon size
        $box->pack_start($icon, 0, 0, 0);

        # Text content
        my $text_box = Gtk3::Box->new('vertical', 1); # Reduced spacing

        my $name_label = Gtk3::Label->new($name);
        $name_label->set_halign('start');
        $name_label->set_text($name); # Removed bold markup

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
            foreach my $child ($self->directory_list->get_children()) {
                my $path = $self->directory_paths->{$child + 0};
                if ($path && $path eq $target_path) {
                    $target_row = $child;
                    last;
                }
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
            # FIXED: Use a delay to ensure UI is ready and prevent duplicate loading
            Glib::Timeout->add(200, sub {
                # Check if a directory is already selected to prevent duplicate loading
                my $current_selected = $self->directory_list->get_selected_row();
                if (!$current_selected) {
                    $self->directory_list->select_row($target_row);
                }
                return 0; # Don't repeat
            });
        }
    }

    sub _load_fonts_from_directory_async {
        my ($self, $row) = @_;

        return unless $row;

        my $dir_path = $self->directory_paths->{$row + 0};
        return unless $dir_path && -d $dir_path;

        print "Loading fonts from directory: $dir_path\n";

        # Show loading indicator
        $self->loading_box->show_all();
        $self->loading_spinner->start();
        $self->loading_label->set_text('Scanning fonts...');

        # Clear existing font list and duplicates tracker
        my $listbox = $self->font_list;
        foreach my $child ($listbox->get_children()) {
            # Clean up font info cache for removed rows
            my $row_key = $child + 0;
            delete $self->font_info_cache->{$row_key};
            $listbox->remove($child);
        }

        # Store current directory
        $self->current_directory($dir_path);

        # Use Glib::Timeout to process fonts in chunks to avoid blocking the UI
        my @font_files = ();
        my %seen_families = ();
        my @processed_fonts = ();
        my $font_index = 0;
        my $chunk_size = 20; # Process 20 fonts at a time
        my $first_font_row = undef;

        # First, quickly scan for font files without processing them
        File::Find::find(sub {
            return unless -f $_;
            return unless /\.(ttf|otf|woff|woff2)$/i;
            push @font_files, $File::Find::name;
        }, $dir_path);

        # Sort font files alphabetically by filename (quick operation)
        @font_files = sort {
            my $a_base = $a;
            my $b_base = $b;
            $a_base =~ s/.*\///;
            $b_base =~ s/.*\///;
            lc($a_base) cmp lc($b_base);
        } @font_files;

        my $total_files = @font_files;
        print "Found $total_files font files, processing in chunks...\n";

        return unless $total_files > 0;

        # Process fonts in chunks using a timer
        my $process_chunk; # Forward declaration
        $process_chunk = sub {
            my $chunk_end = $font_index + $chunk_size - 1;
            $chunk_end = $total_files - 1 if $chunk_end >= $total_files;

            # Update progress
            my $progress = int(($font_index / $total_files) * 100);
            $self->loading_label->set_text("Processing fonts... $progress% ($font_index/$total_files)");

            # Process this chunk of fonts
            for my $i ($font_index..$chunk_end) {
                my $font_file = $font_files[$i];
                my $font_info = $self->_get_font_info_fast($font_file);

                if ($font_info) {
                    # Create unique key for family + style combination
                    my $unique_key = lc($font_info->{family}) . '|' . lc($font_info->{style});

                    # Only add if we haven't seen this family+style combination
                    if (!exists $seen_families{$unique_key}) {
                        $seen_families{$unique_key} = 1;
                        push @processed_fonts, $font_info;

                        # Create and add the font row immediately
                        my $font_row = $self->_create_font_row($font_info);
                        $listbox->add($font_row);
                        $font_row->show_all();

                        # Track the first font row for auto-selection
                        if (!$first_font_row) {
                            $first_font_row = $font_row;
                        }
                    }
                }
            }

            # Force UI update
            $listbox->queue_draw();
            Gtk3::main_iteration() while Gtk3::events_pending();

            $font_index = $chunk_end + 1;

            # Continue processing if there are more fonts
            if ($font_index < $total_files) {
                # Schedule next chunk
                return 1; # Continue timer
            } else {
                # Finished processing all fonts
                print "Finished processing " . @processed_fonts . " unique fonts from $dir_path\n";

                # Hide loading indicator
                $self->loading_spinner->stop();
                $self->loading_box->hide();

                # Auto-select and preview the first font
                if ($first_font_row) {
                    print "Auto-selecting first font\n";
                    Glib::Timeout->add(50, sub {
                        $listbox->select_row($first_font_row);
                        $self->_update_font_preview($first_font_row);
                        return 0; # Don't repeat
                    });
                }

                return 0; # Stop timer
            }
        };

        # Start processing with a very short delay (10ms)
        Glib::Timeout->add(10, $process_chunk);
    }

    sub _get_font_info_fast {
        my ($self, $font_file) = @_;

        # Cache font info to avoid re-processing the same files
        my $file_key = $font_file;
        if (exists $self->{font_file_cache}->{$file_key}) {
            return $self->{font_file_cache}->{$file_key};
        }

        my ($family, $style) = ('Unknown Font', 'Regular');

        # Try fontconfig first (fastest method)
        my $fc_output = `fc-query '$font_file' 2>/dev/null | head -10`; # Limit output for speed

        if ($fc_output) {
            # FIXED: Ensure proper UTF-8 handling
            utf8::decode($fc_output) unless utf8::is_utf8($fc_output);

            # Extract family from fc-query output (optimized regex)
            if ($fc_output =~ /family:\s*"([^"]+)"/i) {
                $family = $1;
                # Quick cleanup - only handle obvious problems
                $family =~ s/[^\x20-\x7E\x{80}-\x{FFFF}]/?/g;
                utf8::decode($family) unless utf8::is_utf8($family);
            }

            # Extract style from fc-query output (optimized regex)
            if ($fc_output =~ /style:\s*"([^"]+)"/i) {
                $style = $1;
                # Quick cleanup - only handle obvious problems
                $style =~ s/[^\x20-\x7E\x{80}-\x{FFFF}]/?/g;
                utf8::decode($style) unless utf8::is_utf8($style);
            }
        }

        # Only do filename parsing if fontconfig completely failed
        if ($family eq 'Unknown Font') {
            my $filename = $font_file;
            $filename =~ s/.*\///;
            $filename =~ s/\.[^.]*$//;

            # Quick family/style extraction
            my ($parsed_family, $parsed_style) = split /-/, $filename, 2;
            $parsed_style ||= 'Regular';

            # Minimal cleanup for speed
            $parsed_family ||= $filename;
            $parsed_family =~ s/^(ttf-|otf-)//i;
            $parsed_family =~ s/_/ /g;
            $parsed_style =~ s/_/ /g;

            # ASCII-safe fallback
            $parsed_family =~ s/[^\x20-\x7E]/?/g;
            $parsed_style =~ s/[^\x20-\x7E]/?/g;

            $family = $parsed_family;
            $style = $parsed_style;
        }

        # Final cleanup
        $family =~ s/^\s+|\s+$//g;
        $style =~ s/^\s+|\s+$//g;
        $family =~ s/\s+/ /g;
        $style =~ s/\s+/ /g;

        # Ensure valid strings
        $family = 'Unknown Font' if !$family || $family eq '';
        $style = 'Regular' if !$style || $style eq '';

        my $result = {
            family => $family,
            style => $style,
            file => $font_file,
            filename => $font_file =~ s/.*\///r =~ s/\.[^.]*$//r
        };

        # Cache the result
        $self->{font_file_cache}->{$file_key} = $result;

        return $result;
    }

    sub _get_font_info {
        my ($self, $font_file) = @_;

        # First try to use fontconfig to get proper font information with UTF-8 support
        my $fc_output = `fc-query '$font_file' 2>/dev/null`;

        my ($family, $style) = ('Unknown Font', 'Regular');

        if ($fc_output) {
            # FIXED: Ensure proper UTF-8 handling
            utf8::decode($fc_output) unless utf8::is_utf8($fc_output);

            # Extract family from fc-query output
            if ($fc_output =~ /family:\s*"([^"]+)"/i) {
                $family = $1;
                # FIXED: Clean up any problematic characters and ensure valid UTF-8
                $family =~ s/[^\x20-\x7E\x{80}-\x{FFFF}]/?/g; # Replace invalid chars with ?
                utf8::decode($family) unless utf8::is_utf8($family);
            }

            # Extract style from fc-query output
            if ($fc_output =~ /style:\s*"([^"]+)"/i) {
                $style = $1;
                # FIXED: Clean up any problematic characters and ensure valid UTF-8
                $style =~ s/[^\x20-\x7E\x{80}-\x{FFFF}]/?/g; # Replace invalid chars with ?
                utf8::decode($style) unless utf8::is_utf8($style);
            }
        }

        # Fallback to filename parsing if fontconfig didn't work or returned bad data
        if ($family eq 'Unknown Font' || $family =~ /[^\x20-\x7E\x{80}-\x{FFFF}]/) {
            my $filename = $font_file;
            $filename =~ s/.*\///;
            $filename =~ s/\.[^.]*$//;

            # Try to extract family and style from filename
            my ($parsed_family, $parsed_style) = split /-/, $filename, 2;
            $parsed_style ||= 'Regular';

            # Clean up family name - remove common prefixes and make readable
            $parsed_family ||= $filename;
            $parsed_family =~ s/^(ttf-|otf-)//i;  # Remove common prefixes
            $parsed_family =~ s/_/ /g;            # Replace underscores with spaces
            $parsed_family =~ s/([a-z])([A-Z])/$1 $2/g;  # Add spaces before capitals

            # Clean up style name
            $parsed_style =~ s/_/ /g;
            $parsed_style =~ s/([a-z])([A-Z])/$1 $2/g;

            # FIXED: Ensure ASCII-safe fallback
            $parsed_family =~ s/[^\x20-\x7E]/?/g; # Replace non-ASCII with ?
            $parsed_style =~ s/[^\x20-\x7E]/?/g;  # Replace non-ASCII with ?

            $family = $parsed_family;
            $style = $parsed_style;
        }

        # FIXED: Final cleanup to ensure clean display
        $family =~ s/^\s+|\s+$//g; # Trim whitespace
        $style =~ s/^\s+|\s+$//g;  # Trim whitespace

        # Replace multiple spaces with single space
        $family =~ s/\s+/ /g;
        $style =~ s/\s+/ /g;

        # Ensure we have valid strings
        $family = 'Unknown Font' if !$family || $family eq '';
        $style = 'Regular' if !$style || $style eq '';

        my $result = {
            family => $family,
            style => $style,
            file => $font_file,
            filename => $font_file =~ s/.*\///r =~ s/\.[^.]*$//r
        };

        # Debug output for first few fonts using a package variable
        our $debug_count //= 0;
        if ($debug_count < 5) {
            print "DEBUG Font Info: Family='$family', Style='$style', File='$font_file'\n";
            $debug_count++;
        }

        return $result;
    }

    sub _create_font_row {
        my ($self, $font_info) = @_;

        my $row = Gtk3::ListBoxRow->new();
        $row->set_size_request(-1, 36); # Reduced from 48 to make smaller
        $row->set_can_focus(1);
        $row->set_selectable(1);

        my $box = Gtk3::Box->new('horizontal', 6); # Reduced spacing
        $box->set_margin_left(8);
        $box->set_margin_right(8);
        $box->set_margin_top(3); # Reduced margins
        $box->set_margin_bottom(3);

        # Text content
        my $text_box = Gtk3::Box->new('vertical', 1); # Reduced spacing

        my $family_label = Gtk3::Label->new();
        $family_label->set_halign('start');

        # FIXED: Ensure UTF-8 safe text setting
        my $family_text = $font_info->{family} || 'Unknown Font';
        eval {
            $family_label->set_text($family_text);
        };
        if ($@) {
            # Fallback if text setting fails
            $family_text =~ s/[^\x20-\x7E]/?/g; # ASCII only fallback
            $family_label->set_text($family_text);
        }

        $family_label->set_ellipsize('end');
        $family_label->set_max_width_chars(30); # Increased for better visibility

        my $style_label = Gtk3::Label->new();
        $style_label->set_halign('start');

        # FIXED: Ensure UTF-8 safe text setting
        my $style_text = $font_info->{style} || 'Regular';
        eval {
            $style_label->set_text($style_text);
        };
        if ($@) {
            # Fallback if text setting fails
            $style_text =~ s/[^\x20-\x7E]/?/g; # ASCII only fallback
            $style_label->set_text($style_text);
        }

        $style_label->set_ellipsize('end');
        $style_label->set_max_width_chars(30);

        $text_box->pack_start($family_label, 0, 0, 0);
        $text_box->pack_start($style_label, 0, 0, 0);

        $box->pack_start($text_box, 1, 1, 0);
        $row->add($box);

        # Ensure all widgets are visible
        $family_label->show();
        $style_label->show();
        $text_box->show_all();
        $box->show_all();
        $row->show_all();

        # Store font info using the row's memory address as key
        my $row_key = $row + 0;
        $self->font_info_cache->{$row_key} = $font_info;

        return $row;
    }

    sub _update_font_preview {
            my ($self, $row) = @_;

            my $row_key = $row + 0;
            my $font_info = $self->font_info_cache->{$row_key};
            return unless $font_info;

            print "Updating preview for font: " . $font_info->{family} . " " . $font_info->{style} . "\n";
            print "Font file: " . $font_info->{file} . "\n";

            # REMOVED: No more current_font_label updates

            # Update the preview text view with the selected font
            my $text_view = $self->preview_text_view;

            # IMPORTANT: Clear any existing font override first to prevent state issues
            $text_view->override_font(undef);

            # Force a redraw to clear previous font state
            $text_view->queue_draw();

            # Small delay to ensure the clearing takes effect
            Glib::Timeout->add(10, sub {
                # Now apply the new font
                eval {
                    # Create font description from the actual font file
                    my $font_desc = $self->_create_font_description_from_file($font_info->{file}, $self->preview_size);

                    if ($font_desc) {
                        # Apply font to text view
                        $text_view->override_font($font_desc);
                        print "Successfully applied font from file\n";
                    } else {
                        # Fallback to family name only with explicit reset
                        print "Falling back to family name: " . $font_info->{family} . "\n";
                        my $fallback_desc = Pango::FontDescription->new();
                        $fallback_desc->set_family($font_info->{family});
                        $fallback_desc->set_size($self->preview_size * Pango::SCALE);
                        # Explicitly set normal weight and style for fallback
                        $fallback_desc->set_weight('normal');
                        $fallback_desc->set_style('normal');
                        $text_view->override_font($fallback_desc);
                    }
                };
                if ($@) {
                    print "Error loading font: $@\n";
                    # Fallback to system font with explicit normal style
                    my $fallback_desc = Pango::FontDescription->new();
                    $fallback_desc->set_family("Sans");
                    $fallback_desc->set_size($self->preview_size * Pango::SCALE);
                    $fallback_desc->set_weight('normal');
                    $fallback_desc->set_style('normal');
                    $text_view->override_font($fallback_desc);
                }

                # Force another redraw after applying the new font
                $text_view->queue_draw();
                return 0; # Don't repeat timeout
        });
    }

    sub _create_font_description_from_file {
        my ($self, $font_file, $size) = @_;

        # Try to use fontconfig to get the proper font description
        my $fc_output = `fc-query '$font_file' 2>/dev/null`;

        if ($fc_output && $fc_output =~ /family:\s*"([^"]+)"/i) {
            my $family = $1;

            # Create font description with explicit defaults
            my $font_desc = Pango::FontDescription->new();
            $font_desc->set_family($family);
            $font_desc->set_size($size * Pango::SCALE);

            # IMPORTANT: Always explicitly set defaults first to clear any previous state
            $font_desc->set_weight('normal');
            $font_desc->set_style('normal');
            $font_desc->set_stretch('normal');
            $font_desc->set_variant('normal');

            # Try to determine style from fc-query output
            if ($fc_output =~ /style:\s*"([^"]+)"/i) {
                my $style = $1;
                print "FC-Query found style: $style for family: $family\n";

                # Map fontconfig styles to Pango styles using proper constants
                # Check for combined styles first (bold + italic)
                if ($style =~ /(?:bold|black|heavy|extrabold).*(?:italic|oblique)|(?:italic|oblique).*(?:bold|black|heavy|extrabold)/i) {
                    print "Applying bold + italic\n";
                    if ($style =~ /black|heavy|extrabold/i) {
                        $font_desc->set_weight('heavy');
                    } else {
                        $font_desc->set_weight('bold');
                    }
                    $font_desc->set_style('italic');
                }
                # Check for bold variations
                elsif ($style =~ /black|heavy/i) {
                    print "Applying heavy weight\n";
                    $font_desc->set_weight('heavy');
                }
                elsif ($style =~ /extrabold/i) {
                    print "Applying heavy weight (extrabold)\n";
                    $font_desc->set_weight('heavy');
                }
                elsif ($style =~ /bold/i) {
                    print "Applying bold weight\n";
                    $font_desc->set_weight('bold');
                }
                # Check for light variations
                elsif ($style =~ /extralight|thin/i) {
                    print "Applying ultralight weight\n";
                    $font_desc->set_weight('ultralight');
                }
                elsif ($style =~ /light/i) {
                    print "Applying light weight\n";
                    $font_desc->set_weight('light');
                }
                elsif ($style =~ /medium/i) {
                    print "Applying medium weight\n";
                    $font_desc->set_weight('medium');
                }
                # Check for italic/oblique (only if not already set above)
                elsif ($style =~ /italic|oblique/i) {
                    print "Applying italic style\n";
                    $font_desc->set_style('italic');
                }
                # For regular/normal, we've already set the defaults
                elsif ($style =~ /regular|normal/i) {
                    print "Applying regular/normal style (defaults already set)\n";
                }
            }

            return $font_desc;
        }

        # Fallback: create a basic font description with explicit defaults
        eval {
            my $basename = $font_file;
            $basename =~ s/.*\///;
            $basename =~ s/\.[^.]*$//;

            my $font_desc = Pango::FontDescription->new();

            # Set defaults first
            $font_desc->set_family($basename);
            $font_desc->set_size($size * Pango::SCALE);
            $font_desc->set_weight('normal');
            $font_desc->set_style('normal');
            $font_desc->set_stretch('normal');
            $font_desc->set_variant('normal');

            # Try to guess style from filename using string constants
            if ($basename =~ /bold.*italic|italic.*bold/i) {
                $font_desc->set_weight('bold');
                $font_desc->set_style('italic');
            } elsif ($basename =~ /bold/i) {
                $font_desc->set_weight('bold');
            } elsif ($basename =~ /italic|oblique/i) {
                $font_desc->set_style('italic');
            }

            return $font_desc;
        };

        return undef;
    }

    sub _update_preview_font_size {
        my $self = shift;

        # Get currently selected font and update its size
        my $selected_row = $self->font_list->get_selected_row();
        if ($selected_row) {
            $self->_update_font_preview($selected_row);
        } else {
            # No font selected, just update the text view with current font at new size
            my $text_view = $self->preview_text_view;
            my $current_font = $text_view->get_style_context()->get_font(Gtk3::StateFlags->new('normal'));

            if ($current_font) {
                $current_font->set_size($self->preview_size * Pango::SCALE);
                $text_view->override_font($current_font);
            }
        }
    }

    sub _filter_fonts {
        my $self = shift;

        my $search_text = $self->search_entry->get_text();
        return unless defined $search_text;

        $search_text = lc($search_text);

        my $listbox = $self->font_list;
        foreach my $child ($listbox->get_children()) {
            my $row_key = $child + 0;
            my $font_info = $self->font_info_cache->{$row_key};
            next unless $font_info;

            my $family = lc($font_info->{family} || '');
            my $style = lc($font_info->{style} || '');

            if ($search_text eq '' ||
                $family =~ /\Q$search_text\E/ ||
                $style =~ /\Q$search_text\E/) {
                $child->show();
            } else {
                $child->hide();
            }
        }
    }

    sub _add_font_directory {
        my $self = shift;

        my $dialog = Gtk3::FileChooserDialog->new(
            'Select Font Directory',
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

                # Save to config
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

    sub _remove_font_directory {
        my $self = shift;

        my $selected_row = $self->directory_list->get_selected_row();
        return unless $selected_row;

        # Don't remove if it's one of the first 4 default directories
        my $row_index = $selected_row->get_index();
        if ($row_index < 4) {
            my $dialog = Gtk3::MessageDialog->new(
                $self->window,
                'modal',
                'warning',
                'ok',
                'Cannot remove default font directories.'
            );
            $dialog->run();
            $dialog->destroy();
            return;
        }

        # Get the directory path being removed
        my $removed_path = $self->directory_paths->{$selected_row + 0};

        # Remove from config
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

    sub _init_config_system {
        my $self = shift;

        # Create config directory structure
        my $config_dir = $ENV{HOME} . '/.local/share/cinnamon-font-manager/config';

        unless (-d $config_dir) {
            system("mkdir -p '$config_dir'");
            print "Created config directory: $config_dir\n";
        }
    }

    sub _get_config_file_path {
        my $self = shift;
        return $ENV{HOME} . '/.local/share/cinnamon-font-manager/config/settings.json';
    }

    sub _load_config {
        my $self = shift;

        my $config_file = $self->_get_config_file_path();
        my $config = {
            preview_size => 24,
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
                    if ($config->{preview_size} < 8 || $config->{preview_size} > 72) {
                        print "Invalid preview size in config, using default\n";
                        $config->{preview_size} = 24;
                    }

                    # Ensure custom_directories is an array ref
                    if (!ref($config->{custom_directories}) || ref($config->{custom_directories}) ne 'ARRAY') {
                        $config->{custom_directories} = [];
                    }

                    print "Loaded configuration from $config_file\n";
                    print "  Preview size: " . $config->{preview_size} . "\n";
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

            # Verify the final file exists and has content
            unless (-f $config_file && -s $config_file) {
                die "Final config file was not created or is empty";
            }

            print "Successfully saved configuration to $config_file\n";

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
        print "Cinnamon Font Manager started\n";
        Gtk3::main();
    }
}

# Main execution
if (!caller) {
    my $app = CinnamonFontManager->new();
    $app->run();
}

1;
