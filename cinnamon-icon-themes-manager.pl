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
        
    # Count icons in a specific directory
    sub _count_icons_in_directory {
        my ($self, $dir_path) = @_;

        return 0 unless -d $dir_path;

        my $icon_count = 0;
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
                            $icon_count++;
                            return if $icon_count >= 20;  # Stop counting after 20 per directory (optimization)
                        }
                    } elsif (-d $full_path) {
                        # Recursively check subdirectories
                        $check_for_icons->($full_path, $depth + 1);
                        return if $icon_count >= 20;  # Stop if we found enough
                    }
                }
            }
        };

        $check_for_icons->($dir_path, 0);
        return $icon_count;
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

        return $has_icons;
    }
        
    sub _find_high_res_icons {
        my ($self, $theme_path, $icon_type, $target_resolution) = @_;

        # Get all possible icon names for this type
        my @icon_names = ($icon_type->{name}, @{$icon_type->{alternatives}}, @{$icon_type->{fallback_names}});
        my $icon_category = $icon_type->{category} || 'mimetypes';

        # Handle different category name variations
        my @category_variations = ($icon_category);
        if ($icon_category eq 'mimetypes') {
            push @category_variations, 'mimes';
        } elsif ($icon_category eq 'mimes') {
            push @category_variations, 'mimetypes';
        }

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
        $find_quality_dirs->($theme_path, 0);

        # Sort by quality score (SVG scalable first, then highest resolution, then direct)
        @quality_dirs = sort { $b->{quality_score} <=> $a->{quality_score} } @quality_dirs;

        for my $i (0..$#quality_dirs) {
            my $dir = $quality_dirs[$i];
        }

        # Search through quality directories in priority order
        foreach my $dir_info (@quality_dirs) {
            my $dir_path = $dir_info->{path};

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


                        my $pixbuf = $self->_load_high_res_icon_file($icon_file, $target_resolution);
                        if ($pixbuf) {
                   
                            return $pixbuf;
                        } else {
                        }
                    }
                }
            }
        }

        return undef;
    }        
        
    sub _find_icon_in_directories {
        my ($self, $icon_type, $icon_directories) = @_;

        # Get all possible icon names for this type
        my @icon_names = ($icon_type->{name}, @{$icon_type->{alternatives}}, @{$icon_type->{fallback_names}});


        # Search through all discovered icon directories
        foreach my $dir_info (@$icon_directories) {
            my $icon_dir = $dir_info->{path};


            foreach my $icon_name (@icon_names) {
                # Look for SVG first, then PNG, then other formats
                foreach my $ext ('svg', 'png', 'xpm', 'ico') {
                    my $icon_file = "$icon_dir/$icon_name.$ext";

                    if (-f $icon_file) {

                        # Skip symbolic icons unless specifically looking for them
                        if ($icon_name =~ /-symbolic$/ && $icon_type->{name} !~ /-symbolic$/) {
              
                            next;
                        }

                        my $pixbuf = $self->_load_icon_file($icon_file, 48);
                        if ($pixbuf) {

                            return $pixbuf;
                        } else {
                        }
                    }
                }
            }
        }

        return undef;
    }
        
    sub _find_icons {
        my ($self, $theme_path, $icon_type) = @_;

        # Get all possible icon names for this type
        my @icon_names = ($icon_type->{name}, @{$icon_type->{alternatives}}, @{$icon_type->{fallback_names}});
        my $icon_category = $icon_type->{category} || 'mimetypes';

        # Handle different category name variations - support both mimes and mimetypes
        my @category_variations = ($icon_category);
        if ($icon_category eq 'mimetypes') {
            push @category_variations, 'mimes';
        } elsif ($icon_category eq 'mimes') {
            push @category_variations, 'mimetypes';
        }

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
        $find_category_dirs->($theme_path, 0);

        # Sort directories by quality score (scalable first, then by size descending, then direct, then nested)
        @category_dirs = sort { $b->{quality_score} <=> $a->{quality_score} } @category_dirs;

        for my $i (0..$#category_dirs) {
            my $dir = $category_dirs[$i];
        }

        # Now search through the category directories we found, in priority order
        foreach my $dir_info (@category_dirs) {
            my $dir_path = $dir_info->{path};

            foreach my $icon_name (@icon_names) {
                # STRICTLY reject ANY symbolic icons
                if ($icon_name =~ /symbolic/i) {
            
                    next;
                }

                # Look for SVG first, then PNG
                foreach my $ext ('svg', 'png') {
                    my $icon_file = "$dir_path/$icon_name.$ext";

                    # STRICTLY reject ANY files with 'symbolic' in the name
                    if ($icon_file =~ /symbolic/i) {
              
                        next;
                    }

                    if (-f $icon_file) {
          
                        my $pixbuf = $self->_load_icon_file($icon_file, 64);
                        if ($pixbuf) {
                 
                            return $pixbuf;
                        } else {
                        }
                    }
                }
            }
        }

        return undef;
    }                

    sub _find_ultra_high_res_icons {
        my ($self, $theme_path, $icon_type, $target_resolution) = @_;

        # Get all possible icon names for this type
        my @icon_names = ($icon_type->{name}, @{$icon_type->{alternatives}}, @{$icon_type->{fallback_names}});
        my $icon_category = $icon_type->{category} || 'mimetypes';

        # Handle different category name variations
        my @category_variations = ($icon_category);
        if ($icon_category eq 'mimetypes') {
            push @category_variations, 'mimes';
        } elsif ($icon_category eq 'mimes') {
            push @category_variations, 'mimetypes';
        }

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
        $find_quality_dirs->($theme_path, 0);

        # Sort by quality score (SVG scalable first with highest priority)
        @quality_dirs = sort { $b->{quality_score} <=> $a->{quality_score} } @quality_dirs;

        for my $i (0..$#quality_dirs) {
            my $dir = $quality_dirs[$i];
        }

        # Search through quality directories in priority order
        foreach my $dir_info (@quality_dirs) {
            my $dir_path = $dir_info->{path};

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

                        my $pixbuf = $self->_load_ultra_high_res_icon_file($icon_file, $target_resolution);
                        if ($pixbuf) {

                            return $pixbuf;
                        } else {
                        }
                    }
                }
            }
        }

        return undef;
    }
        
    sub _generate_icon_preview {
        my ($self, $theme_info, $output_file, $width, $height) = @_;


        # Check if already exists for this specific size
        if (-f $output_file && -s $output_file > 1000) {

            return 1;
        }

        # Double-check theme quality before generating preview
        unless ($self->_validate_theme_quality($theme_info->{path}, $theme_info->{name})) {

            return 0;
        }

        my @icon_pixbufs = $self->_extract_theme_icons($theme_info);
        unless (@icon_pixbufs >= 6) {  # Require at least 6 icons for a decent preview
            return 0;
        }

        #  Generate ONLY the requested size, not all sizes
        
        my $surface = Cairo::ImageSurface->create('argb32', $width, $height);
        my $cr = Cairo::Context->create($surface);
        
        $self->_draw_icon_grid($cr, \@icon_pixbufs, $width, $height);
        $surface->write_to_png($output_file);
        
        if (-f $output_file && -s $output_file > 1000) {
            print "Generated preview: $output_file\n";
            return 1;
        } else {
            print "ERROR: Failed to generate preview: $output_file\n";
            return 0;
        }
    }

    sub _get_config_file_path {
        my $self = shift;
        return $ENV{HOME} . '/.local/share/cinnamon-icons-theme-manager/config/settings.json';
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

    sub _is_valid_cached_preview {
        my ($self, $cache_file) = @_;
        
        # Check if file exists
        return 0 unless -f $cache_file;
        
        # Check if file has reasonable size (at least 1KB)
        my $file_size = -s $cache_file;
        return 0 unless $file_size > 1000;
        
        # Check if file is recent enough (optional: skip very old cache files)
        my $file_age = time() - (stat($cache_file))[9];
        if ($file_age > (30 * 24 * 60 * 60)) {  # 30 days old
  
            return 0;
        }
        
        return 1;
    }

    sub _load_cached_preview_for_widget {
        my ($self, $theme_info, $cache_file, $width, $height) = @_;
        
        my $theme_name = $theme_info->{name};
        
        #  Ensure cache is valid
        unless ($self->_is_valid_cached_preview($cache_file)) {
   
            return;
        }
        
        # Find the widget for this theme
        my $flowbox = $self->icons_grid;
        foreach my $child ($flowbox->get_children()) {
            my $frame = $child->get_child();
            my $stored_theme_info = $self->theme_paths->{$frame + 0};
            
            if ($stored_theme_info && $stored_theme_info->{name} eq $theme_name) {
                my $preview_widget = $self->theme_widgets->{$frame + 0};
                
                if ($preview_widget) {
                    eval {
                        my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale(
                            $cache_file, $width, $height, 1
                        );
                        if ($pixbuf) {
                            # If it's an Image widget, update directly
                            if ($preview_widget->isa('Gtk3::Image')) {
                                $preview_widget->set_from_pixbuf($pixbuf);
                                $preview_widget->set_size_request($width, $height);
          
                            } else {
                                # If it's a DrawingArea (placeholder), replace it with Image
                                my $new_image = Gtk3::Image->new_from_pixbuf($pixbuf);
                                $new_image->set_size_request($width, $height);
                                
                                my $box = $preview_widget->get_parent();
                                if ($box && $box->isa('Gtk3::Box')) {
                                    $box->remove($preview_widget);
                                    $box->pack_start($new_image, 1, 1, 0);
                                    $box->reorder_child($new_image, 0);
                                    $box->show_all();
                                    
                                    # Update reference
                                    $self->theme_widgets->{$frame + 0} = $new_image;
                           
                                }
                            }
                        }
                    };
                    if ($@) {
                        print "Error loading cached zoom preview for $theme_name: $@\n";
                    }
                }
                last;
            }
        }
    }

    sub _load_high_res_icon_file {
        my ($self, $icon_file, $target_size) = @_;


        # Check if file exists and is readable
        unless (-f $icon_file && -r $icon_file) {
       
            return undef;
        }

        my $file_size = -s $icon_file;
        if ($file_size == 0) {
  
            return undef;
        }

        my $pixbuf;
        eval {
            if ($icon_file =~ /\.svg$/i) {
            
                # Load SVG at exact target size for maximum sharpness
                $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale($icon_file, $target_size, $target_size, 1);
            } elsif ($icon_file =~ /\.png$/i) {
  
                # Load PNG at original resolution first
                my $original_pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon_file);
                if ($original_pixbuf) {
                    my $orig_width = $original_pixbuf->get_width();
                    my $orig_height = $original_pixbuf->get_height();
           

                    if ($orig_width != $target_size || $orig_height != $target_size) {
                        # Use highest quality scaling algorithm
        
                        $pixbuf = $original_pixbuf->scale_simple($target_size, $target_size, 'hyper');
                    } else {
                        $pixbuf = $original_pixbuf;
                    }
                }
            } else {

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
 
            }
        };

        if ($@) {
 
            return undef;
        }

        return $pixbuf;
    }

    sub _load_high_resolution_icon {
        my ($self, $icon_file, $target_size) = @_;

        # Check if file exists and is readable
        unless (-f $icon_file && -r $icon_file) {

            return undef;
        }

        my $file_size = -s $icon_file;
        if ($file_size == 0) {

            return undef;
        }

        my $pixbuf;
        eval {
            if ($icon_file =~ /\.svg$/i) {
          
                # SVGs can be loaded at exact target size with perfect sharpness
                $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale($icon_file, $target_size, $target_size, 1);
            } elsif ($icon_file =~ /\.png$/i) {

                # Load PNG at original resolution first
                my $original_pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon_file);
                if ($original_pixbuf) {
                    my $orig_width = $original_pixbuf->get_width();
                    my $orig_height = $original_pixbuf->get_height();
        

                    if ($orig_width != $target_size || $orig_height != $target_size) {
                        #  Use highest quality scaling algorithm for sharpest results
               
                        $pixbuf = $original_pixbuf->scale_simple($target_size, $target_size, 'hyper');
                    } else {
                        $pixbuf = $original_pixbuf;
                    }
                }
            } else {

                my $original_pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon_file);
                if ($original_pixbuf) {
                    my $orig_width = $original_pixbuf->get_width();
                    my $orig_height = $original_pixbuf->get_height();

                    if ($orig_width != $target_size || $orig_height != $target_size) {
                        # Use highest quality scaling
                        $pixbuf = $original_pixbuf->scale_simple($target_size, $target_size, 'hyper');
                    } else {
                        $pixbuf = $original_pixbuf;
                    }
                }
            }

            if ($pixbuf) {
                my $final_width = $pixbuf->get_width();
                my $final_height = $pixbuf->get_height();
  
            }
        };

        if ($@) {

            return undef;
        }

        return $pixbuf;
    }

    sub _load_icon_file {
        my ($self, $icon_file, $target_size) = @_;


        # Check if file exists and is readable
        unless (-f $icon_file && -r $icon_file) {
 
            return undef;
        }

        my $file_size = -s $icon_file;


        if ($file_size == 0) {

            return undef;
        }

        # Increase target size for better quality at high zoom levels
        my $load_size = ($target_size > 96) ? 128 : $target_size;

        my $pixbuf;
        eval {
            if ($icon_file =~ /\.svg$/i) {

                # Load SVG at higher resolution for better quality
                $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale($icon_file, $load_size, $load_size, 1);
            } elsif ($icon_file =~ /\.png$/i) {

                # Load PNG and scale if necessary
                $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon_file);
                if ($pixbuf) {
                    my $width = $pixbuf->get_width();
                    my $height = $pixbuf->get_height();
          

                    if ($width != $load_size || $height != $load_size) {
          
                        $pixbuf = $pixbuf->scale_simple($load_size, $load_size, 'bilinear');
                    }
                }
            } elsif ($icon_file =~ /\.xpm$/i) {

                # Load XPM
                $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon_file);
                if ($pixbuf) {
                    my $width = $pixbuf->get_width();
                    my $height = $pixbuf->get_height();
    

                    if ($width != $load_size || $height != $load_size) {

                        $pixbuf = $pixbuf->scale_simple($load_size, $load_size, 'bilinear');
                    }
                }
            } else {

                # Try to load other formats
                $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon_file);
                if ($pixbuf) {
                    my $width = $pixbuf->get_width();
                    my $height = $pixbuf->get_height();


                    if ($width != $load_size || $height != $load_size) {
     
                        $pixbuf = $pixbuf->scale_simple($load_size, $load_size, 'bilinear');
                    }
                }
            }

            if ($pixbuf) {
                my $final_width = $pixbuf->get_width();
                my $final_height = $pixbuf->get_height();

            } else {

            }
        };

        if ($@) {
  
            return undef;
        }

        unless ($pixbuf) {
        
            return undef;
        }
        return $pixbuf;
    }

    sub _load_ultra_high_res_icon_file {
        my ($self, $icon_file, $target_size) = @_;

        # Check if file exists and is readable
        unless (-f $icon_file && -r $icon_file) {
   
            return undef;
        }

        my $file_size = -s $icon_file;
        if ($file_size == 0) {

            return undef;
        }

        my $pixbuf;
        eval {
            if ($icon_file =~ /\.svg$/i) {
      
                # Load SVG at exact target size with sub-pixel precision
                $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale($icon_file, $target_size, $target_size, 1);
            } elsif ($icon_file =~ /\.png$/i) {
       
                # Load PNG at original resolution first
                my $original_pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon_file);
                if ($original_pixbuf) {
                    my $orig_width = $original_pixbuf->get_width();
                    my $orig_height = $original_pixbuf->get_height();
               

                    if ($orig_width != $target_size || $orig_height != $target_size) {
                        # Use the highest quality scaling algorithm available
         
                        $pixbuf = $original_pixbuf->scale_simple($target_size, $target_size, 'hyper');
                    } else {
                        $pixbuf = $original_pixbuf;
                    }
                }
            } else {

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

            }
        };

        if ($@) {

            return undef;
        }

        return $pixbuf;
    }

    sub _parse_directory_pattern {
        my ($self, $pattern) = @_;
        
        my $category = undef;
        my $size = undef;
        
        # Determine category (standardize mimes to mimetypes)
        if ($pattern =~ /\bplaces\b/) {
            $category = 'places';
        } elsif ($pattern =~ /\bdevices\b/) {
            $category = 'devices';
        } elsif ($pattern =~ /\bmimes\b/) {
            $category = 'mimetypes';  # Standardize mimes to mimetypes
        } elsif ($pattern =~ /\bmimetypes\b/) {
            $category = 'mimetypes';
        }
        
        # Determine size/type - EXPANDED to catch all sizes
        if ($pattern =~ /\bscalable\b/) {
            $size = 'scalable';
        } elsif ($pattern =~ /\b512x512\b/) {
            $size = '512x512';
        } elsif ($pattern =~ /\b512\b/) {
            $size = '512';
        } elsif ($pattern =~ /\b256x256\b/) {
            $size = '256x256';
        } elsif ($pattern =~ /\b256\b/) {
            $size = '256';
        } elsif ($pattern =~ /\b192x192\b/) {
            $size = '192x192';
        } elsif ($pattern =~ /\b192\b/) {
            $size = '192';
        } elsif ($pattern =~ /\b128x128\b/) {
            $size = '128x128';
        } elsif ($pattern =~ /\b128\b/) {
            $size = '128';
        } elsif ($pattern =~ /\b96x96\b/) {
            $size = '96x96';
        } elsif ($pattern =~ /\b96\b/) {
            $size = '96';
        } elsif ($pattern =~ /\b64x64\b/) {
            $size = '64x64';
        } elsif ($pattern =~ /\b64\b/) {
            $size = '64';
        } elsif ($pattern =~ /\b48x48\b/) {
            $size = '48x48';
        } elsif ($pattern =~ /\b48\b/) {
            $size = '48';
        } elsif ($pattern =~ /\b32x32\b/) {
            $size = '32x32';
        } elsif ($pattern =~ /\b32\b/) {
            $size = '32';
        } elsif ($pattern =~ /\b24x24\b/) {
            $size = '24x24';
        } elsif ($pattern =~ /\b24\b/) {
            $size = '24';
        } elsif ($pattern =~ /\b22x22\b/) {
            $size = '22x22';
        } elsif ($pattern =~ /\b22\b/) {
            $size = '22';
        } elsif ($pattern =~ /\b16x16\b/) {
            $size = '16x16';
        } elsif ($pattern =~ /\b16\b/) {
            $size = '16';
        } else {
            # DIRECT category directory (no size subdirectory)
            $size = 'direct';
        }
        
        return ($category, $size);
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

    sub _quick_theme_validation {
        my ($self, $theme_path) = @_;
        
        # FIRST: Check if this is a blacklisted theme by path
        my $theme_name = File::Basename::basename($theme_path);
        my @blacklisted_themes = (
            'hicolor', 'Hicolor', 'HICOLOR', 'HiColor', 'hiColor', 'Hi-Color',
            'default', 'Default', 'DEFAULT'
        );
        
        foreach my $blacklisted (@blacklisted_themes) {
            if (lc($theme_name) eq lc($blacklisted)) {
    
                return 0;
            }
        }
        
        # ADDITIONAL CHECK: Reject if theme name contains hicolor anywhere
        if ($theme_name =~ /hicolor/i) {
   
            return 0;
        }
        
        # Very quick check - just look for key directories without deep scanning
        my @required = ('places', 'devices');
        my @mime_variations = ('mimes', 'mimetypes');
        
        my $found_places = 0;
        my $found_devices = 0;
        my $found_mimes = 0;
        
        # Only scan 2 levels deep max
        my $dh1;
        unless (opendir($dh1, $theme_path)) {
            return 0;
        }
        
        my @level1_dirs = grep { -d "$theme_path/$_" && $_ !~ /^\./ } readdir($dh1);
        closedir($dh1);
        
        foreach my $dir1 (@level1_dirs) {
            my $path1 = "$theme_path/$dir1";
            
            # Check level 1
            $found_places = 1 if $dir1 =~ /^places$/i;
            $found_devices = 1 if $dir1 =~ /^devices$/i;
            $found_mimes = 1 if $dir1 =~ /^(mimes|mimetypes)$/i;
            
            last if ($found_places && $found_devices && $found_mimes);
            
            # Check level 2 only if needed
            my $dh2;
            if (opendir($dh2, $path1)) {
                my @level2_dirs = grep { -d "$path1/$_" && $_ !~ /^\./ } readdir($dh2);
                closedir($dh2);
                
                foreach my $dir2 (@level2_dirs) {
                    $found_places = 1 if $dir2 =~ /^places$/i;
                    $found_devices = 1 if $dir2 =~ /^devices$/i;
                    $found_mimes = 1 if $dir2 =~ /^(mimes|mimetypes)$/i;
                    
                    last if ($found_places && $found_devices && $found_mimes);
                }
            }
            
            last if ($found_places && $found_devices && $found_mimes);
        }
        
        my $is_valid = ($found_places && $found_devices && $found_mimes);
        
        if ($is_valid) {

        } else {

        }
        
        return $is_valid;
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

    sub _scan_theme_directories_optimized {
        my ($self, $theme_path) = @_;
        
        my @found_directories = ();
        
        # EXPANDED search patterns to catch ALL themes including Humanity, Hicolor, Yaru
        my @search_patterns = (
            # Pattern 0: DIRECT category directories (most common)
            'places', 'mimetypes', 'devices', 'mimes',
            
            # Pattern 1: category/size/ - EXPANDED with more sizes
            'places/scalable', 'mimetypes/scalable', 'devices/scalable', 'mimes/scalable',
            'places/512', 'mimetypes/512', 'devices/512', 'mimes/512',
            'places/256', 'mimetypes/256', 'devices/256', 'mimes/256',
            'places/192', 'mimetypes/192', 'devices/192', 'mimes/192',
            'places/128', 'mimetypes/128', 'devices/128', 'mimes/128',
            'places/96', 'mimetypes/96', 'devices/96', 'mimes/96', 
            'places/64', 'mimetypes/64', 'devices/64', 'mimes/64',
            'places/48', 'mimetypes/48', 'devices/48', 'mimes/48',
            'places/32', 'mimetypes/32', 'devices/32', 'mimes/32',
            'places/24', 'mimetypes/24', 'devices/24', 'mimes/24',
            'places/22', 'mimetypes/22', 'devices/22', 'mimes/22',
            'places/16', 'mimetypes/16', 'devices/16', 'mimes/16',
            
            # Pattern 2: size/category/ - EXPANDED with more sizes
            'scalable/places', 'scalable/mimetypes', 'scalable/devices', 'scalable/mimes',
            '512x512/places', '512x512/mimetypes', '512x512/devices', '512x512/mimes',
            '256x256/places', '256x256/mimetypes', '256x256/devices', '256x256/mimes',
            '192x192/places', '192x192/mimetypes', '192x192/devices', '192x192/mimes',
            '128x128/places', '128x128/mimetypes', '128x128/devices', '128x128/mimes',
            '96x96/places', '96x96/mimetypes', '96x96/devices', '96x96/mimes',
            '64x64/places', '64x64/mimetypes', '64x64/devices', '64x64/mimes',
            '48x48/places', '48x48/mimetypes', '48x48/devices', '48x48/mimes',
            '32x32/places', '32x32/mimetypes', '32x32/devices', '32x32/mimes',
            '24x24/places', '24x24/mimetypes', '24x24/devices', '24x24/mimes',
            '22x22/places', '22x22/mimetypes', '22x22/devices', '22x22/mimes',
            '16x16/places', '16x16/mimetypes', '16x16/devices', '16x16/mimes',
            
            # Pattern 3: simple size/category/ (elementary-xfce style)
            '512/places', '512/mimetypes', '512/devices', '512/mimes',
            '256/places', '256/mimetypes', '256/devices', '256/mimes',
            '192/places', '192/mimetypes', '192/devices', '192/mimes',
            '128/places', '128/mimetypes', '128/devices', '128/mimes',
            '96/places', '96/mimetypes', '96/devices', '96/mimes',
            '64/places', '64/mimetypes', '64/devices', '64/mimes',
            '48/places', '48/mimetypes', '48/devices', '48/mimes',
            '32/places', '32/mimetypes', '32/devices', '32/mimes',
            '24/places', '24/mimetypes', '24/devices', '24/mimes',
            '22/places', '22/mimetypes', '22/devices', '22/mimes',
            '16/places', '16/mimetypes', '16/devices', '16/mimes',
        );
        
        # EXPANDED priority mapping for ALL sizes
        my %priority_map = (
            'direct' => 1200,    # DIRECT category dirs get HIGHEST priority
            'scalable' => 1000,  # SVG always high priority
            '512x512' => 980, '512' => 970,     # Very very large PNG
            '256x256' => 950, '256' => 940,     # Very large PNG (Yaru)
            '192x192' => 920, '192' => 910,     # Large PNG
            '128x128' => 900, '128' => 890,     # Large PNG
            '96x96' => 800,   '96' => 790,      # Medium PNG  
            '64x64' => 700,   '64' => 690,      # Small PNG
            '48x48' => 600,   '48' => 590,      # Smaller PNG (Humanity)
            '32x32' => 500,   '32' => 490,      # Very small PNG
            '24x24' => 400,   '24' => 390,      # Tiny PNG
            '22x22' => 300,   '22' => 290,      # Tiny PNG
            '16x16' => 200,   '16' => 190,      # Micro PNG
        );
        
        # Search for each pattern in the theme
        foreach my $pattern (@search_patterns) {
            my $full_path = "$theme_path/$pattern";
            
            if (-d $full_path) {
                # Extract category and size from pattern
                my ($category, $size) = $self->_parse_directory_pattern($pattern);
                if (!$category) {
                    next;
                }
                
                # Check if directory contains actual icon files (be more lenient)
                if (opendir(my $dh, $full_path)) {
                    my @all_files = readdir($dh);
                    closedir($dh);
                    
                    my @icon_files = grep { 
                        /\.(svg|png|xpm|ico)$/i &&    # Any icon format
                        !/-symbolic\./i &&            # Not symbolic
                        !/symbolic/i &&               # Not symbolic
                        $_ !~ /^\./                   # Not hidden
                    } @all_files;
                    
                    if (@icon_files > 0) {
                        my $priority = $priority_map{$size} || 100;
                        my $type = ($size eq 'scalable') ? 'SVG' : 'PNG';
                        
                        push @found_directories, {
                            path => $full_path,
                            category => $category,
                            size => $size,
                            priority => $priority,
                            type => $type,
                            icon_count => scalar(@icon_files),
                            pattern => $pattern
                        };
                    }
                }
            }
        }
        
        # Sort by priority (highest first)
        @found_directories = sort { $b->{priority} <=> $a->{priority} } @found_directories;
        
        return @found_directories;
    }

    sub _schedule_single_size_preview_generation {
        my ($self, $theme_info, $cache_file, $width, $height) = @_;

        # Add to generation queue if not already queued
        if (!$self->{preview_generation_queue}) {
            $self->{preview_generation_queue} = [];
        }

        my $current_name = $theme_info->{name} || '';
        return if $current_name eq ''; # Skip if no theme name

        # Create unique key for this specific size
        my $queue_key = "${current_name}-${width}x${height}";
        
        # Check if already queued for this exact size
        foreach my $queued (@{$self->{preview_generation_queue}}) {
            my $queued_name = $queued->{theme_info}->{name} || '';
            my $queued_key = "${queued_name}-$queued->{width}x$queued->{height}";
            if ($queued_key eq $queue_key) {
     
                return;
            }
        }

        # Add to queue for this specific size only
        push @{$self->{preview_generation_queue}}, {
            theme_info => $theme_info,
            cache_file => $cache_file,
            width => $width,
            height => $height
        };

        # Start processing queue if not already running
        if (!$self->{preview_generation_active}) {
            $self->_process_preview_generation_queue();
        }
    }
    
    sub _search_icon_in_directories {
        my ($self, $icon_name, $directories_ref) = @_;

        
        #  Try SVG directories first, but don't skip PNG if SVG doesn't work
        my @svg_directories = grep { $_->{type} eq 'SVG' } @$directories_ref;
        
        if (@svg_directories > 0) {

            
            # Search SVG directories first
            foreach my $dir_info (@svg_directories) {
                my $icon_path = "$dir_info->{path}/$icon_name.svg";
                if (-f $icon_path) {
         
                    return $icon_path;
                }
            }
        }
        
        # Always search PNG/MIXED directories (don't skip them like before)       
        my @png_directories = grep { $_->{type} eq 'PNG' || $_->{type} eq 'MIXED' } @$directories_ref;
        
        foreach my $dir_info (@png_directories) {
            # Try PNG first, then SVG for MIXED directories
            foreach my $ext ('png', 'svg') {
                my $icon_path = "$dir_info->{path}/$icon_name.$ext";
                if (-f $icon_path) {
   
                    return $icon_path;
                }
            }
        }

        return undef;
    }    

    sub _show_no_themes_message {
        my $self = shift;
        
        $self->_hide_loading_indicator();
        
        my $no_themes_label = Gtk3::Label->new();
        $no_themes_label->set_markup("<big><b>No Complete Icon Themes Found</b></big>\n\nThis directory doesn't contain any complete icon themes.\nComplete themes must have 'places', 'devices', and 'mimes' directories.");
        $no_themes_label->set_justify('center');
        $no_themes_label->set_margin_top(50);
        $no_themes_label->set_margin_bottom(50);
        
        $self->icons_grid->add($no_themes_label);
        $self->icons_grid->show_all();
    }

    sub _update_icon_zoom_non_blocking {
        my $self = shift;
        
        my $new_width = $self->zoom_level;
        my $new_height = int($self->zoom_level * 0.75);
        
        my $flowbox = $self->icons_grid;
        my @children = $flowbox->get_children();
        
        # Get current themes
        my @current_themes = ();
        foreach my $child (@children) {
            my $frame = $child->get_child();
            my $theme_info = $self->theme_paths->{$frame + 0};
            if ($theme_info) {
                push @current_themes, $theme_info;
            }
        }
        
        # Update widget sizes immediately for visual feedback
        foreach my $child (@children) {
            my $frame = $child->get_child();
            my $preview_widget = $self->theme_widgets->{$frame + 0};
            
            if ($preview_widget) {
                $preview_widget->set_size_request($new_width, $new_height);
                
                # Quick scale existing preview if available
                if ($preview_widget->isa('Gtk3::Image')) {
                    my $current_pixbuf = $preview_widget->get_pixbuf();
                    if ($current_pixbuf) {
                        eval {
                            my $scaled_pixbuf = $current_pixbuf->scale_simple($new_width, $new_height, 'fast');
                            if ($scaled_pixbuf) {
                                $preview_widget->set_from_pixbuf($scaled_pixbuf);
                            }
                        };
                    }
                }
            }
        }
        
        $flowbox->show_all();
        
        # Use the SAME lazy loading method that works for directories
        $self->_start_lazy_preview_loading_at_zoom(\@current_themes, $self->current_directory, $self->zoom_level);
    }     

    sub _update_theme_widget_with_preview {
        my ($self, $theme_info) = @_;
        
        my $theme_name = $theme_info->{name};
        my $cache_dir = $ENV{HOME} . '/.local/share/cinnamon-icons-theme-manager/thumbnails';
        my $cache_file = "$cache_dir/${theme_name}-preview-" . $self->zoom_level . ".png";
        
        # Find the widget for this theme
        my $flowbox = $self->icons_grid;
        foreach my $child ($flowbox->get_children()) {
            my $frame = $child->get_child();
            my $stored_theme_info = $self->theme_paths->{$frame + 0};
            
            if ($stored_theme_info && $stored_theme_info->{name} eq $theme_name) {
                my $preview_widget = $self->theme_widgets->{$frame + 0};
                
                if ($preview_widget && -f $cache_file && -s $cache_file > 1000) {
                    eval {
                        my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale(
                            $cache_file, $self->zoom_level, int($self->zoom_level * 0.75), 1
                        );
                        if ($pixbuf) {
                            $preview_widget->set_from_pixbuf($pixbuf);
                            print "Updated widget with preview for: $theme_name\n";
                        }
                    };
                    if ($@) {
                        print "Error updating widget preview: $@\n";
                    }
                }
                last;
            }
        }
    }
    
    sub _update_widget_with_cached_preview {
        my ($self, $theme_info, $cache_file) = @_;
        
        unless (-f $cache_file && -s $cache_file > 100) {

            return;
        }
        
        my $theme_name = $theme_info->{name};
        my $flowbox = $self->icons_grid;
        
        foreach my $child ($flowbox->get_children()) {
            my $frame = $child->get_child();
            my $stored_info = $self->theme_paths->{$frame + 0};
            
            if ($stored_info && $stored_info->{name} eq $theme_name) {
                my $placeholder = $self->theme_widgets->{$frame + 0};
                
                if ($placeholder) {
                    eval {
                        # Load the cached preview
                        my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale($cache_file, 400, 300, 1);
                        if ($pixbuf) {
                            # Replace the DrawingArea with an Image
                            my $image = Gtk3::Image->new_from_pixbuf($pixbuf);
                            $image->set_size_request(400, 300);
                            
                            # Get the parent box
                            my $box = $placeholder->get_parent();
                            if ($box && $box->isa('Gtk3::Box')) {
                                $box->remove($placeholder);
                                $box->pack_start($image, 1, 1, 0);
                                $box->reorder_child($image, 0);
                                $box->show_all();
                                
                                # Update reference
                                $self->theme_widgets->{$frame + 0} = $image;
             
                            }
                        }
                    };
                    if ($@) {
                        print "Error updating preview for $theme_name: $@\n";
                    }
                }
                last;
            }
        }
    }    

    sub _update_widget_with_cached_preview_at_zoom {
        my ($self, $theme_info, $cache_file, $zoom_level) = @_;
        
        #  Additional validation
        unless ($self->_is_valid_cached_preview($cache_file)) {

            return;
        }
        
        my $theme_name = $theme_info->{name};
        my $flowbox = $self->icons_grid;
        my $height = int($zoom_level * 0.75);
        
        foreach my $child ($flowbox->get_children()) {
            my $frame = $child->get_child();
            my $stored_info = $self->theme_paths->{$frame + 0};
            
            if ($stored_info && $stored_info->{name} eq $theme_name) {
                my $placeholder = $self->theme_widgets->{$frame + 0};
                
                if ($placeholder) {
                    eval {
                        # Load the cached preview at correct zoom level
                        my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale($cache_file, $zoom_level, $height, 1);
                        if ($pixbuf) {
                            # Replace the DrawingArea with an Image
                            my $image = Gtk3::Image->new_from_pixbuf($pixbuf);
                            $image->set_size_request($zoom_level, $height);
                            
                            # Get the parent box
                            my $box = $placeholder->get_parent();
                            if ($box && $box->isa('Gtk3::Box')) {
                                $box->remove($placeholder);
                                $box->pack_start($image, 1, 1, 0);
                                $box->reorder_child($image, 0);
                                $box->show_all();
                                
                                # Update reference
                                $self->theme_widgets->{$frame + 0} = $image;
                                print "Updated widget with cached preview for: $theme_name at ${zoom_level}px\n";
                            }
                        }
                    };
                    if ($@) {
                        print "Error updating cached preview for $theme_name: $@\n";
                    }
                }
                last;
            }
        }
    }

    sub _validate_theme_quality {
        my ($self, $theme_path, $theme_name) = @_;

        # EXPANDED BLACKLIST: Skip known problematic themes first (comprehensive check)
        my @blacklisted_themes = (
            'hicolor', 'Hicolor', 'HICOLOR', 'HiColor', 'hiColor', 'Hi-Color',
            'default', 'Default', 'DEFAULT'
        );
        foreach my $blacklisted (@blacklisted_themes) {
            if (lc($theme_name) eq lc($blacklisted)) {
           
                return 0;
            }
        }

        # ADDITIONAL CHECK: Reject if theme name contains hicolor anywhere
        if ($theme_name =~ /hicolor/i) {
     
            return 0;
        }

        # ADDITIONAL CHECK: Check the index.theme file for internal references
        my $index_file = "$theme_path/index.theme";
        if (-f $index_file && open my $fh, '<', $index_file) {
            while (my $line = <$fh>) {
                chomp $line;
                # Check Name field
                if ($line =~ /^Name\s*=\s*(.+)$/i) {
                    my $internal_name = $1;
                    $internal_name =~ s/^["']|["']$//g; # Remove quotes
                    if (lc($internal_name) =~ /hicolor|default/i) {
          
                        close $fh;
                        return 0;
                    }
                }
                # Check Comment field for additional hints
                if ($line =~ /^Comment\s*=\s*(.+)$/i) {
                    my $comment = $1;
                    if (lc($comment) =~ /fallback|default.*fallback|hicolor/i) {
                   
                        close $fh;
                        return 0;
                    }
                }
            }
            close $fh;
        }

        # Required categories that must be present for a complete icon theme
        my @required_categories = ('places', 'devices');
        # For mimetypes, we need to check for both 'mimes' and 'mimetypes' since themes use either
        my @mimetype_variations = ('mimes', 'mimetypes');

        my %found_categories = ();
        my $total_icons = 0;

        # Scan the theme directory structure recursively to find category directories and count icons
        my $scan_theme;
        $scan_theme = sub {
            my ($dir_path, $depth) = @_;

            return if $depth > 6;  # Limit recursion depth
            return unless -d $dir_path;

            # Check if current directory matches any required category
            my $dir_name = File::Basename::basename($dir_path);

            # Check for standard required categories
            foreach my $required_cat (@required_categories) {
                if ($dir_name =~ /^\Q$required_cat\E$/i) {
                    # Verify this directory actually contains icon files
                    my $icon_count = $self->_count_icons_in_directory($dir_path);
                    if ($icon_count > 0) {
                        $found_categories{$required_cat} = 1;
                        $total_icons += $icon_count;
            
                    }
                }
            }

            # Check for mimetype variations
            foreach my $mime_var (@mimetype_variations) {
                if ($dir_name =~ /^\Q$mime_var\E$/i) {
                    # Verify this directory actually contains icon files
                    my $icon_count = $self->_count_icons_in_directory($dir_path);
                    if ($icon_count > 0) {
                        $found_categories{'mimetypes'} = 1;  # Use standard name internally
                        $total_icons += $icon_count;
           
                    }
                }
            }

            # Continue scanning subdirectories if we haven't found everything yet
            if (keys(%found_categories) < 3 || $total_icons < 50) {  # Stop early if we have enough
                if (opendir(my $dh, $dir_path)) {
                    my @subdirs = grep { -d "$dir_path/$_" && $_ !~ /^\./ } readdir($dh);
                    closedir($dh);

                    foreach my $subdir (@subdirs) {
                        $scan_theme->("$dir_path/$subdir", $depth + 1);
                        last if (keys(%found_categories) >= 3 && $total_icons >= 50);  # Early exit optimization
                    }
                }
            }
        };

        # Start scanning from theme root
        $scan_theme->($theme_path, 0);


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
     
            return 0;  # Incomplete theme
        }

        # Require at least 20 icons for a decent preview
        if ($total_icons < 20) {
        
            return 0;
        }

        return 1;  # Complete and quality theme
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

        #  Zoom In Button - ensure we read current zoom level correctly
        $zoom_in->signal_connect('clicked' => sub {
            my $current_zoom = $self->zoom_level;
            
            my $new_zoom;
            if ($current_zoom == 400) {
                $new_zoom = 500;
              
            } elsif ($current_zoom == 500) {
                $new_zoom = 600;
             
            } else {
              
                return; # Don't do anything if already at max
            }
            
            $self->zoom_level($new_zoom);
            $self->_update_icon_zoom_non_blocking();
            $self->_adjust_grid_columns();  # This will always set 4 columns now
            
            # Save config
            $self->config->{preview_size} = $new_zoom;
            $self->_save_config($self->config);

        });

        #  Zoom Out Button
        $zoom_out->signal_connect('clicked' => sub {
            my $current_zoom = $self->zoom_level;
 
            
            my $new_zoom;
            if ($current_zoom == 600) {
                $new_zoom = 500;
              
            } elsif ($current_zoom == 500) {
                $new_zoom = 400;
         
            } else {
           
                return; # Don't do anything if already at min
            }
            
            $self->zoom_level($new_zoom);
            $self->_update_icon_zoom_non_blocking();
            $self->_adjust_grid_columns();  # This will always set 4 columns now
            
            # Save config
            $self->config->{preview_size} = $new_zoom;
            $self->_save_config($self->config);
            
        });

        $self->icons_grid->signal_connect('child-activated' => sub {
            my ($widget, $child) = @_;
            $self->_set_icon_theme($child);
        });

        # REDUCED: Less frequent window size adjustments
        $self->window->signal_connect('size-allocate' => sub {
            my ($widget, $allocation) = @_;
            # Add longer delay and only adjust if really needed
            Glib::Timeout->add(500, sub {
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

        # Account for left panel and margins
        my $available_width = $window_width - 280 - 50;
        my $item_width_with_spacing = 400 + 12;
        my $max_columns = int($available_width / $item_width_with_spacing);

        # Ensure reasonable bounds
        $max_columns = 1 if $max_columns < 1;
        $max_columns = 6 if $max_columns > 6; # Reduced max for better performance


        # Update immediately - no blocking operations
        $self->icons_grid->set_max_children_per_line($max_columns);
        $self->icons_grid->set_min_children_per_line(1);

        return $max_columns;
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

    sub _display_themes_non_blocking {
        my ($self, $themes_ref, $dir_path) = @_;

        my $total_themes = @$themes_ref;
        print "Displaying $total_themes themes non-blocking\n";

        # Create placeholders for all themes immediately - this is fast
        my $themes_displayed = 0;
        
        # Display themes in small batches to keep UI responsive
        my $display_batch;
        $display_batch = sub {
            # Stop if directory changed
            return 0 if $self->current_directory ne $dir_path;
            
            my $batch_size = 4; # Small batches
            my $batch_end = ($themes_displayed + $batch_size - 1 < $total_themes - 1) 
                           ? $themes_displayed + $batch_size - 1 
                           : $total_themes - 1;

            # Create widgets for this batch
            for my $i ($themes_displayed..$batch_end) {
                my $theme_info = $themes_ref->[$i];
                
                # Create widget with placeholder immediately (fast)
                my $theme_widget = $self->_create_placeholder_widget($theme_info);
                $self->icons_grid->add($theme_widget);
            }

            $themes_displayed = $batch_end + 1;
            $self->icons_grid->show_all();

            # Update loading progress
            my $progress = int(($themes_displayed / $total_themes) * 100);
            $self->_update_loading_progress("Loading themes...", $progress);

            if ($themes_displayed < $total_themes) {
                # Continue with next batch after short delay
                Glib::Timeout->add(20, $display_batch); # Very short delay
                return 0;
            } else {
                # All placeholders created, hide loading and start preview generation
                print "All theme placeholders created, starting preview generation\n";
                $self->_hide_loading_indicator();
                $self->_start_non_blocking_preview_generation($themes_ref, $dir_path);
                return 0;
            }
        };

        # Start displaying
        Glib::Timeout->add(10, $display_batch);
    }

    sub _load_icons_from_directory {
        my ($self, $row) = @_;

        return unless $row;

        my $dir_path = $self->directory_paths->{$row + 0};
        unless ($dir_path && -d $dir_path && -r $dir_path) {
            print "ERROR: Invalid or unreadable directory path: " . ($dir_path || 'undefined') . "\n";
            return;
        }

        #  Check if this is the same directory we just loaded
        if ($self->current_directory && $self->current_directory eq $dir_path) {
            return;
        }

        # Guard against rapid consecutive calls
        my $current_time = time();
        if ($self->{last_load_call_time} && ($current_time - $self->{last_load_call_time}) < 1) {
            return;
        }
        $self->{last_load_call_time} = $current_time;


        # Show loading indicator immediately
        $self->_show_loading_indicator('Preparing to scan...');

        # Clear existing icons immediately for instant feedback
        my $flowbox = $self->icons_grid;
        foreach my $child ($flowbox->get_children()) {
            $flowbox->remove($child);
        }
        $flowbox->show_all();

        # Clear references immediately
        $self->theme_paths({});
        $self->theme_widgets({});
        $self->current_directory($dir_path);

        # Check cache first - this should be instant
        if (exists $self->cached_theme_lists->{$dir_path}) {
            my $themes_ref = $self->cached_theme_lists->{$dir_path};
            print "Using cached theme list for $dir_path (" . @$themes_ref . " themes)\n";
            
            # Use very short timeout to prevent blocking
            Glib::Timeout->add(10, sub {
                $self->_display_themes_immediately($themes_ref, $dir_path);
                return 0;
            });
        } else {
            # Start background scanning with very small time slices
            print "Starting background scan of $dir_path\n";
            $self->_start_background_scan($dir_path);
        }
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

    sub _set_icon_theme {
        my ($self, $child) = @_;

        my $frame = $child->get_child();
        my $theme_info = $self->theme_paths->{$frame + 0};

        return unless $theme_info;

        my $theme_name = $theme_info->{name};
        print "Setting icon theme: $theme_name\n";

        # Apply immediately in background
        Glib::Timeout->add(10, sub {
            system("gsettings set org.cinnamon.desktop.interface icon-theme '$theme_name' 2>/dev/null &");
            $self->current_theme($theme_name);
            
            # Save to config
            $self->config->{last_applied_theme} = {
                name => $theme_name,
                path => $theme_info->{path},
                timestamp => time()
            };
            $self->_save_config($self->config);
            
            print "Applied icon theme: $theme_name\n";
            return 0;
        });
    }

    sub _start_background_scan {
        my ($self, $dir_path) = @_;
        
        $self->_update_loading_progress("Scanning directory...", 0);
        
        # Get directory listing first with proper variable declaration
        my $dh;
        unless (opendir($dh, $dir_path)) {
            $self->_hide_loading_indicator();
            print "ERROR: Cannot open directory $dir_path\n";
            return;
        }
        
        my @all_subdirs = grep { -d "$dir_path/$_" && $_ !~ /^\./ } readdir($dh);
        closedir($dh);
        
        my $total_dirs = @all_subdirs;
        unless ($total_dirs > 0) {
            print "No subdirectories found in $dir_path\n";
            $self->_show_no_themes_message();
            return;
        }
        
        print "Found $total_dirs subdirectories to scan\n";
        
        # Process directories in very small batches
        my $processed = 0;
        my @found_themes = ();
        
        my $process_batch;
        $process_batch = sub {
            return 0 if $self->current_directory ne $dir_path;
            
            my $batch_size = 3; # Very small batches
            my $end_idx = ($processed + $batch_size - 1 < $total_dirs - 1) 
                         ? $processed + $batch_size - 1 
                         : $total_dirs - 1;
            
            # Process this small batch
            for my $i ($processed..$end_idx) {
                my $subdir = $all_subdirs[$i];
                my $theme_path = "$dir_path/$subdir";
                
                # Quick validation
                my $index_file = "$theme_path/index.theme";
                if (-f $index_file && $self->_quick_theme_validation($theme_path)) {
                    my $theme_info = $self->_parse_icon_theme_info($theme_path, $subdir);
                    push @found_themes, $theme_info;
                    print "Found valid theme: $subdir\n";
                }
            }
            
            $processed = $end_idx + 1;
            my $progress = int(($processed / $total_dirs) * 100);
            $self->_update_loading_progress("Scanning themes...", $progress);
            
            if ($processed < $total_dirs) {
                # Continue with next batch - very short delay
                Glib::Timeout->add(5, $process_batch);
                return 0;
            } else {
                # Scanning complete
                @found_themes = sort { lc($a->{name}) cmp lc($b->{name}) } @found_themes;
                $self->cached_theme_lists->{$dir_path} = \@found_themes;
                
                print "Scan complete: " . @found_themes . " themes found\n";
                
                if (@found_themes > 0) {
                    $self->_display_themes_immediately(\@found_themes, $dir_path);
                } else {
                    $self->_show_no_themes_message();
                }
                return 0;
            }
        };
        
        # Start processing
        Glib::Timeout->add(10, $process_batch);
    }   

    sub _start_lazy_preview_loading {
        my ($self, $themes_ref, $dir_path) = @_;
        
        print "Starting lazy preview loading for " . @$themes_ref . " themes\n";
        
        # Cancel any existing preview loading
        if ($self->{preview_loading_timeout}) {
            Glib::Source->remove($self->{preview_loading_timeout});
            $self->{preview_loading_timeout} = undef;
        }
        
        my $themes_to_process = [@$themes_ref]; # Copy array
        my $current_index = 0;
        
        my $process_next;
        $process_next = sub {
            # Stop if directory changed
            return 0 if $self->current_directory ne $dir_path;
            return 0 if $current_index >= @$themes_to_process;
            
            my $theme_info = $themes_to_process->[$current_index];
            my $theme_name = $theme_info->{name};
            $current_index++;
            
            print "Processing preview " . $current_index . "/" . @$themes_to_process . ": $theme_name\n";
            
            # Check if preview already exists
            my $cache_file = $ENV{HOME} . "/.local/share/cinnamon-icons-theme-manager/thumbnails/${theme_name}-preview-400.png";
            
            if (-f $cache_file && -s $cache_file > 1000) {
                # Load existing preview
                $self->_update_widget_with_cached_preview($theme_info, $cache_file);
                
                # Continue immediately to next theme
                if ($current_index < @$themes_to_process) {
                    $self->{preview_loading_timeout} = Glib::Timeout->add(50, $process_next);
                }
            } else {
                # Generate preview in background
                Glib::Idle->add(sub {
                    my $success = 0;
                    eval {
                        $success = $self->_generate_simple_preview($theme_info, $cache_file);
                    };
                    if ($@) {
                        print "Error generating preview for $theme_name: $@\n";
                    }
                    
                    # Only update widget if preview generation was successful
                    if ($success && -f $cache_file && -s $cache_file > 1000) {
                        $self->_update_widget_with_cached_preview($theme_info, $cache_file);
                    } else {
                    }
                    
                    # Continue to next theme
                    if ($current_index < @$themes_to_process) {
                        $self->{preview_loading_timeout} = Glib::Timeout->add(200, $process_next);
                    } else {
                        print "All preview loading completed\n";
                        $self->{preview_loading_timeout} = undef;
                    }
                    
                    return 0;
                });
            }
            
            return 0;
        };
        
        # Start processing after delay
        $self->{preview_loading_timeout} = Glib::Timeout->add(500, $process_next);
    }

    sub _start_lazy_preview_loading_at_zoom {
        my ($self, $themes_ref, $dir_path, $zoom_level) = @_;
        
        print "Starting lazy preview loading for " . @$themes_ref . " themes at ${zoom_level}px\n";
        
        # Cancel any existing preview loading
        if ($self->{preview_loading_timeout}) {
            Glib::Source->remove($self->{preview_loading_timeout});
            $self->{preview_loading_timeout} = undef;
        }
        
        my $themes_to_process = [@$themes_ref]; # Copy array
        my $current_index = 0;
        
        my $process_next;
        $process_next = sub {
            # Stop if directory changed or zoom level changed
            return 0 if ($self->current_directory ne $dir_path || $self->zoom_level != $zoom_level);
            return 0 if $current_index >= @$themes_to_process;
            
            my $theme_info = $themes_to_process->[$current_index];
            my $theme_name = $theme_info->{name};
            $current_index++;
            
            print "Processing preview " . $current_index . "/" . @$themes_to_process . ": $theme_name at ${zoom_level}px\n";
            
            # CHECK CACHE FIRST
            my $cache_file = $ENV{HOME} . "/.local/share/cinnamon-icons-theme-manager/thumbnails/${theme_name}-preview-${zoom_level}.png";
            
            if ($self->_is_valid_cached_preview($cache_file)) {
                # Use existing cached preview
                $self->_update_widget_with_cached_preview_at_zoom($theme_info, $cache_file, $zoom_level);
                
                # Continue immediately to next theme
                if ($current_index < @$themes_to_process) {
                    $self->{preview_loading_timeout} = Glib::Timeout->add(10, $process_next);
                } else {
                    print "All preview loading completed\n";
                    $self->{preview_loading_timeout} = undef;
                }
            } else {
                # Generate new preview
                Glib::Idle->add(sub {
                    return 0 if ($self->current_directory ne $dir_path || $self->zoom_level != $zoom_level);
                    
                    my $success = 0;
                    eval {
                        $success = $self->_generate_simple_preview($theme_info, $cache_file);
                    };
                    if ($@) {
                        print "Error generating preview for $theme_name: $@\n";
                    }
                    
                    if ($success && $self->_is_valid_cached_preview($cache_file)) {
                        $self->_update_widget_with_cached_preview_at_zoom($theme_info, $cache_file, $zoom_level);
                    }
                    
                    # Continue to next theme
                    if ($current_index < @$themes_to_process && $self->zoom_level == $zoom_level) {
                        $self->{preview_loading_timeout} = Glib::Timeout->add(200, $process_next);
                    } else {
                        print "All preview loading completed\n";
                        $self->{preview_loading_timeout} = undef;
                    }
                    
                    return 0;
                });
            }
            
            return 0;
        };
        
        # Start processing
        $self->{preview_loading_timeout} = Glib::Timeout->add(10, $process_next);
    }

    sub _start_non_blocking_preview_generation {
        my ($self, $themes_ref, $dir_path) = @_;

        print "Starting non-blocking preview generation for current zoom level only\n";
        
        my $themes_processed = 0;
        my $total_themes = @$themes_ref;
        my $current_zoom = $self->zoom_level; # Capture current zoom level
        
        # Process one theme at a time with idle callbacks to prevent freezing
        my $process_next_theme;
        $process_next_theme = sub {
            # Stop if directory changed or all processed
            return 0 if ($self->current_directory ne $dir_path || $themes_processed >= $total_themes);
            
            # Stop if zoom level changed while processing
            if ($self->zoom_level != $current_zoom) {
                return 0;
            }
            
            my $theme_info = $themes_ref->[$themes_processed];
            my $theme_name = $theme_info->{name};
            
            print "Generating preview for: $theme_name (" . ($themes_processed + 1) . "/$total_themes) at ${current_zoom}px\n";
            
            # Generate preview in idle callback to prevent UI blocking
            Glib::Idle->add(sub {
                # Check if we already have preview at current zoom level
                my $cache_dir = $ENV{HOME} . '/.local/share/cinnamon-icons-theme-manager/thumbnails';
                my $cache_file = "$cache_dir/${theme_name}-preview-${current_zoom}.png";
                
                # Only generate if not cached for this specific size
                if (!(-f $cache_file && -s $cache_file > 1000)) {
                    eval {
                        $self->_generate_icon_preview(
                            $theme_info,
                            $cache_file,
                            $current_zoom,
                            int($current_zoom * 0.75)
                        );
                    };
                    if ($@) {
                        print "Error generating preview for $theme_name: $@\n";
                    }
                }
                
                # Update the widget with the preview
                $self->_update_theme_widget_with_preview($theme_info);
                
                $themes_processed++;
                
                # Continue with next theme after very short delay to keep UI responsive
                if ($themes_processed < $total_themes && $self->zoom_level == $current_zoom) {
                    Glib::Timeout->add(50, $process_next_theme); # Short delay between themes
                } else {
                    print "Preview generation completed or zoom changed\n";
                }
                
                return 0;
            });
            
            return 0;
        };
        
        # Start processing after short delay
        Glib::Timeout->add(100, $process_next_theme);
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

    sub _start_zoom_preview_generation_non_blocking {
        my ($self, $children_ref, $width, $height) = @_;
        
        
        # Cancel any existing zoom preview generation
        if ($self->{zoom_preview_timeout}) {
            Glib::Source->remove($self->{zoom_preview_timeout});
            $self->{zoom_preview_timeout} = undef;
        }
        
        my $processed_count = 0;
        my $total_count = @$children_ref;
        my $current_zoom = $self->zoom_level;  # Capture current zoom level
        
        # Process one widget at a time to keep UI responsive
        my $process_next_widget;
        $process_next_widget = sub {
            # Stop if zoom level changed or all processed
            return 0 if ($self->zoom_level != $current_zoom || $processed_count >= $total_count);
            
            my $child = $children_ref->[$processed_count];
            my $frame = $child->get_child();
            my $theme_info = $self->theme_paths->{$frame + 0};
            
            if ($theme_info) {
                my $theme_name = $theme_info->{name};
                
                #  Always check cache first for zoom changes
                my $cache_dir = $ENV{HOME} . '/.local/share/cinnamon-icons-theme-manager/thumbnails';
                my $cache_file = "$cache_dir/${theme_name}-preview-${width}.png";
                
                if ($self->_is_valid_cached_preview($cache_file)) {
                    # Load existing high-quality preview immediately
                    $self->_load_cached_preview_for_widget($theme_info, $cache_file, $width, $height);
                    
                    # Continue immediately to next widget
                    $processed_count++;
                    if ($processed_count < $total_count && $self->zoom_level == $current_zoom) {
                        $self->{zoom_preview_timeout} = Glib::Timeout->add(5, $process_next_widget);  # Very fast for cached
                    }
                } else {
                    # Generate new preview in idle callback to avoid blocking
                    Glib::Idle->add(sub {
                        # Double-check zoom level hasn't changed
                        return 0 if $self->zoom_level != $current_zoom;
                        
                        my $success = 0;
                        eval {
                            $success = $self->_generate_simple_preview($theme_info, $cache_file);
                        };
                        if ($@) {
                            print "Error generating zoom preview for $theme_name: $@\n";
                        }
                        
                        # Load the new preview if generation was successful
                        if ($success && $self->_is_valid_cached_preview($cache_file)) {
                            $self->_load_cached_preview_for_widget($theme_info, $cache_file, $width, $height);
                        }
                        
                        # Continue to next widget
                        $processed_count++;
                        if ($processed_count < $total_count && $self->zoom_level == $current_zoom) {
                            $self->{zoom_preview_timeout} = Glib::Timeout->add(50, $process_next_widget);
                        } else {
                            $self->{zoom_preview_timeout} = undef;
                        }
                        
                        return 0;
                    });
                }
            } else {
                # No theme info, skip to next
                $processed_count++;
                if ($processed_count < $total_count && $self->zoom_level == $current_zoom) {
                    $self->{zoom_preview_timeout} = Glib::Timeout->add(5, $process_next_widget);
                }
            }
            
            return 0;
        };
        
        # Start processing immediately for cached previews
        $self->{zoom_preview_timeout} = Glib::Timeout->add(10, $process_next_widget);
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

    sub _create_instant_theme_widget {
        my ($self, $theme_info) = @_;
        
        # Create frame
        my $frame = Gtk3::Frame->new();
        $frame->set_shadow_type('in');
        
        # Create container
        my $box = Gtk3::Box->new('vertical', 6);
        $box->set_margin_left(6);
        $box->set_margin_right(6);
        $box->set_margin_top(6);
        $box->set_margin_bottom(6);
        
        # Create minimal placeholder - just solid color, no Cairo
        my $placeholder = Gtk3::DrawingArea->new();
        $placeholder->set_size_request(400, 300);
        
        # Simple draw callback
        $placeholder->signal_connect('draw' => sub {
            my ($widget, $cr) = @_;
            # Light gray background
            $cr->set_source_rgb(0.95, 0.95, 0.95);
            $cr->paint();
            # Simple "Loading..." text
            $cr->set_source_rgb(0.5, 0.5, 0.5);
            $cr->select_font_face("Sans", 'normal', 'normal');
            $cr->set_font_size(14);
            $cr->move_to(160, 150);
            $cr->show_text("Loading...");
            return 1;
        });
        
        $box->pack_start($placeholder, 1, 1, 0);
        
        # Create label
        my $theme_name = $theme_info->{display_name} || $theme_info->{name};
        my $label = Gtk3::Label->new($theme_name);
        $label->set_ellipsize('middle');
        $label->set_max_width_chars(20);
        
        $box->pack_start($label, 0, 0, 0);
        $frame->add($box);
        
        # Store references
        $self->theme_paths->{$frame + 0} = $theme_info;
        $self->theme_widgets->{$frame + 0} = $placeholder;
        
        return $frame;
    }

    sub _create_instant_theme_widget_at_zoom {
        my ($self, $theme_info, $zoom_level) = @_;
        
        # Create frame
        my $frame = Gtk3::Frame->new();
        $frame->set_shadow_type('in');
        
        # Create container
        my $box = Gtk3::Box->new('vertical', 6);
        $box->set_margin_left(6);
        $box->set_margin_right(6);
        $box->set_margin_top(6);
        $box->set_margin_bottom(6);
        
        #  Create placeholder at current zoom level, not hardcoded 400
        my $height = int($zoom_level * 0.75);
        my $placeholder = Gtk3::DrawingArea->new();
        $placeholder->set_size_request($zoom_level, $height);
        
        # Simple draw callback
        $placeholder->signal_connect('draw' => sub {
            my ($widget, $cr) = @_;
            # Light gray background
            $cr->set_source_rgb(0.95, 0.95, 0.95);
            $cr->paint();
            # Simple "Loading..." text
            $cr->set_source_rgb(0.5, 0.5, 0.5);
            $cr->select_font_face("Sans", 'normal', 'normal');
            $cr->set_font_size(14);
            $cr->move_to($zoom_level * 0.4, $height * 0.5);  # Center based on actual size
            $cr->show_text("Loading...");
            return 1;
        });
        
        $box->pack_start($placeholder, 1, 1, 0);
        
        # Create label
        my $theme_name = $theme_info->{display_name} || $theme_info->{name};
        my $label = Gtk3::Label->new($theme_name);
        $label->set_ellipsize('middle');
        $label->set_max_width_chars(20);
        
        $box->pack_start($label, 0, 0, 0);
        $frame->add($box);
        
        # Store references
        $self->theme_paths->{$frame + 0} = $theme_info;
        $self->theme_widgets->{$frame + 0} = $placeholder;
        
        return $frame;
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

    sub _initialize_configuration {
        my $self = shift;

        # Initialize directory structure first
        $self->_initialize_directory_structure();

        # Initialize configuration system
        $self->_init_config_system();

        # Load configuration
        my $config = $self->_load_config();
        $self->config($config);

        #  Properly initialize zoom level from config
        my $zoom_level = $config->{preview_size} || 400;
        
        # Validate zoom level - must be exactly 400, 500, or 600
        if ($zoom_level != 400 && $zoom_level != 500 && $zoom_level != 600) {
            $zoom_level = 400;
            $config->{preview_size} = 400;
            $self->_save_config($config);
        }
        
        #  Set zoom level properly in object
        $self->zoom_level($zoom_level);
        $self->last_selected_directory_path($config->{last_selected_directory});

        print "Configuration initialized\n";
        print "  Preview size: " . $self->zoom_level . "px\n";
        print "  Custom directories: " . @{$config->{custom_directories} || []} . "\n";
        print "  Last directory: " . ($self->last_selected_directory_path || 'none') . "\n";
    }

    sub _load_config {
        my $self = shift;
        my $config_file = $self->_get_config_file_path();
        my $config = {
            preview_size => 400,  # Always default to 400px
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
                    
                    #  Validate and correct preview_size
                    my $preview_size = $config->{preview_size};
                    if (!$preview_size || ($preview_size != 400 && $preview_size != 500 && $preview_size != 600)) {
                        print "Invalid preview size in config ($preview_size), using default 400px\n";
                        $config->{preview_size} = 400;
                    } else {
                        print "Loaded preview size from config: ${preview_size}px\n";
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
                    print "Config file is empty, using defaults (400px)\n";
                }
            };
            if ($@) {
                print "Error loading config: $@\n";
                print "Using default configuration (400px)\n";
            }
        } else {
            print "Config file not found, using defaults (400px)\n";
        }
        
        return $config;
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

    sub _cleanup_background_processes {
        my $self = shift;

        # Clear cached theme lists to free memory
        $self->cached_theme_lists({});

        # Clear icon cache
        $self->icon_cache({});

        print "Background processes cleaned up\n";
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

        #  Better cache validation and create preview at requested size
        my $preview_widget;
        if (-f $preview_path && -s $preview_path > 1000) {
            eval {
                my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_scale(
                    $preview_path, $width, $height, 1
                );
                $preview_widget = Gtk3::Image->new_from_pixbuf($pixbuf) if $pixbuf;
            };
            if ($@) {
                print "Error loading cached preview: $@\n";
                # If cache is corrupted, delete it and create placeholder
                unlink($preview_path);
                $preview_widget = undef;
            }
        }

        # Generate new preview if no cached version exists or cache was corrupted
        unless ($preview_widget) {
            #  Create placeholder at requested size, not hardcoded
            my $pixbuf = $self->_create_placeholder_pixbuf($width, $height);
            $preview_widget = Gtk3::Image->new_from_pixbuf($pixbuf);

            # Schedule preview generation for this specific size only
            $self->_schedule_single_size_preview_generation($theme_info, $preview_path, $width, $height);
        }

        return $preview_widget;
    }

    sub _generate_simple_preview {
        my ($self, $theme_info, $cache_file) = @_;
        
        my $theme_path = $theme_info->{path};
        my $theme_name = $theme_info->{name};
        
        # ADDITIONAL SAFETY CHECK: Never generate previews for blacklisted themes
        my @blacklisted_themes = (
            'hicolor', 'Hicolor', 'HICOLOR', 'HiColor', 'hiColor', 'Hi-Color',
            'default', 'Default', 'DEFAULT'
        );
        
        foreach my $blacklisted (@blacklisted_themes) {
            if (lc($theme_name) eq lc($blacklisted)) {
                return 0;
            }
        }
        
        if ($theme_name =~ /hicolor/i) {
            return 0;
        }
        
        #  Use robust cache checking
        if ($self->_is_valid_cached_preview($cache_file)) {
            return 1;  # Return success since cache exists
        }
        
        print "Generating HIGH-RESOLUTION preview for: $theme_name\n";
        
        #  Determine target size from cache filename and use high-resolution icons
        my $target_width = 400;  # Default
        my $target_height = 300;
        
        if ($cache_file =~ /(\d+)\.png$/) {
            $target_width = $1;
            $target_height = int($target_width * 0.75);
        }
        
        #  Use much higher resolution icons based on target preview size
        my $icon_resolution;
        if ($target_width >= 600) {
            $icon_resolution = 256;  # Very high resolution for 600px previews
        } elsif ($target_width >= 500) {
            $icon_resolution = 192;  # High resolution for 500px previews  
        } else {
            $icon_resolution = 128;  # Medium-high resolution for 400px previews
        }
        
        
        # Use the EXACT same icon types as the original code - no changes to layout
        my @required_icons = (
            # Row 1: Places icons
            {
                name => 'computer',
                alternatives => ['computer-laptop', 'computer-desktop', 'system'],
            },
            {
                name => 'folder',
                alternatives => ['user-folder', 'folder-home', 'user-folder-home'],
            },
            {
                name => 'desktop',
                alternatives => ['user-desktop', 'gnome-fs-desktop','folder-desktop'],
            },
            {
                name => 'user-trash',
                alternatives => ['user-trash-empty', 'trash-empty', 'edittrash', 'gnome-stock-trash-empty'],
            },
            # Row 2: Application/Script mimetypes
            {
                name => 'application-x-shellscript',
                alternatives => ['text-x-script', 'application-x-script', 'text-x-shellscript'],
            },
            {
                name => 'application-x-php',
                alternatives => ['text-x-php', 'application-php', 'text-php'],
            },
            {
                name => 'application-x-ruby',
                alternatives => ['text-x-ruby', 'application-ruby', 'text-ruby'],
            },
            {
                name => 'text-x-javascript',
                alternatives => ['application-x-javascript', 'application-javascript', 'text-javascript'],
            },
            # Row 3: Document mimetypes
            {
                name => 'text-plain',
                alternatives => ['text-x-generic', 'text', 'text-x-plain'],
            },
            {
                name => 'x-office-document',
                alternatives => ['application-vnd.oasis.opendocument.text', 'application-msword', 'application-document'],
            },
            {
                name => 'x-office-presentation',
                alternatives => ['application-vnd.oasis.opendocument.presentation', 'application-vnd.ms-powerpoint', 'application-presentation'],
            },
            {
                name => 'x-office-spreadsheet',
                alternatives => ['application-vnd.oasis.opendocument.spreadsheet', 'application-vnd.ms-excel', 'application-spreadsheet'],
            },
            # Row 4: Device icons
            {
                name => 'application-x-tar',
                alternatives => ['application-tar', 'gnome-mime-application-x-compressed-tar', 'gnome-mime-application-x-tar','package-tar','tar'],
            },
            {
                name => 'image',
                alternatives => ['application-image', 'application-x-image'],
            },
            {
                name => 'application-executable',
                alternatives => ['application-x-executable', 'exec', 'gnome-mime-application-x-executable'],
            },
            {
                name => 'printer',
                alternatives => ['printer-network', 'printer-local', 'device-printer'],
            }
        );
        
        my @found_pixbufs = ();
        
        # Try to find EXACTLY the 16 icons we need for the 4x4 grid using HIGH RESOLUTION
        foreach my $icon_def (@required_icons) {
            my @names_to_try = ($icon_def->{name}, @{$icon_def->{alternatives}});
            my $found_icon = 0;
            
            foreach my $icon_name (@names_to_try) {
                my $icon_path = $self->_find_icon_quickly($theme_path, $icon_name);
                if ($icon_path) {
                    eval {
                        #  Load icons at higher resolution for sharp results
                        my $pixbuf = $self->_load_high_resolution_icon($icon_path, $icon_resolution);
                        if ($pixbuf) {
                            push @found_pixbufs, $pixbuf;
                            $found_icon = 1;
                            last; # Found one for this slot, move to next
                        }
                    };
                    if ($@) {
                    }
                }
            }
            
            # If we couldn't find this icon, add a placeholder slot
            unless ($found_icon) {
                push @found_pixbufs, undef; # Placeholder for missing icon
            }
        }
        
        # Count actual icons found
        my $real_icons_count = grep { defined $_ } @found_pixbufs;
        
        # Only generate preview if we found at least 6 icons
        if ($real_icons_count >= 6) {
            my $surface = Cairo::ImageSurface->create('argb32', $target_width, $target_height);
            my $cr = Cairo::Context->create($surface);
            
            #  Use high-quality icon grid drawing method
            $self->_draw_high_quality_icon_grid($cr, \@found_pixbufs, $target_width, $target_height);
            
            $surface->write_to_png($cache_file);
            print "Generated HIGH-RESOLUTION preview with $real_icons_count real icons: $cache_file\n";
            return 1;
        } else {
            return 0;
        }
    }

    sub _load_icons_from_directory_async {
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
            return;
        }

        $self->{last_loaded_directory} = $dir_path;
        $self->{last_load_time} = $current_time;


        # Show loading indicator but don't block UI
        $self->_show_loading_indicator('Scanning for icon themes...');

        # Clear existing icons immediately to show we're loading
        my $flowbox = $self->icons_grid;
        foreach my $child ($flowbox->get_children()) {
            $flowbox->remove($child);
        }

        # Clear references
        $self->theme_paths({});
        $self->theme_widgets({});
        $self->current_directory($dir_path);

        # Check cache first - this is fast and non-blocking
        my $themes_ref;
        if (exists $self->cached_theme_lists->{$dir_path}) {
            $themes_ref = $self->cached_theme_lists->{$dir_path};
            print "Using cached theme list for $dir_path (" . @$themes_ref . " themes)\n";
            $self->_display_themes_non_blocking($themes_ref, $dir_path);
        } else {
            # Scan in background using Glib::Idle for true non-blocking
            print "Starting non-blocking directory scan...\n";
            
            Glib::Idle->add(sub {
                # This runs when UI is idle, allowing drag/resize
                print "Scanning $dir_path in background...\n";
                
                my @themes = $self->_scan_icon_themes($dir_path);
                @themes = sort { lc($a->{name}) cmp lc($b->{name}) } @themes;
                $themes_ref = \@themes;
                $self->cached_theme_lists->{$dir_path} = $themes_ref;
                
                print "Scanned $dir_path: " . @themes . " icon themes found\n";
                
                if (@themes == 0) {
                    $self->_hide_loading_indicator();
                    return 0;
                }

                # Display themes non-blocking
                $self->_display_themes_non_blocking($themes_ref, $dir_path);
                return 0; # Don't repeat
            });
        }
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
                }
            }
        }
    }

sub _scan_icon_themes {
        my ($self, $base_dir) = @_;

        my @themes = ();
        my %seen_themes = (); # Track theme names to prevent duplicates

        opendir(my $dh, $base_dir) or return @themes;
        my @subdirs = grep { -d "$base_dir/$_" && $_ !~ /^\./ } readdir($dh);
        closedir($dh);

        # EXPANDED BLACKLIST: Themes to completely skip - more comprehensive patterns
        my @blacklisted_themes = (
            'hicolor', 'Hicolor', 'HICOLOR', 'HiColor', 'hiColor', 'Hi-Color',
            'default', 'Default', 'DEFAULT'
        );

        foreach my $subdir (@subdirs) {
            my $theme_path = "$base_dir/$subdir";

            # FIRST CHECK: Skip blacklisted themes immediately with case-insensitive matching
            my $is_blacklisted = 0;
            foreach my $blacklisted (@blacklisted_themes) {
                if (lc($subdir) eq lc($blacklisted)) {
                    $is_blacklisted = 1;
                    last;
                }
            }
            next if $is_blacklisted;

            # ADDITIONAL CHECK: Skip if directory name contains 'hicolor' anywhere
            if ($subdir =~ /hicolor/i) {
                next;
            }

            # Skip if we've already processed this theme name
            if (exists $seen_themes{$subdir}) {
                next;
            }

            # Check if this directory contains an icon theme
            my $index_file = "$theme_path/index.theme";
            next unless -f $index_file;

            # ADDITIONAL CHECK: Read index.theme and check internal name
            if (open my $index_fh, '<', $index_file) {
                my $internal_name_is_hicolor = 0;
                while (my $line = <$index_fh>) {
                    chomp $line;
                    if ($line =~ /^Name\s*=\s*(.+)$/i) {
                        my $internal_name = $1;
                        $internal_name =~ s/^["']|["']$//g; # Remove quotes
                        if (lc($internal_name) =~ /hicolor|default/i) {
                            $internal_name_is_hicolor = 1;
                            last;
                        }
                    }
                }
                close $index_fh;
                next if $internal_name_is_hicolor;
            }

            # Use validation function (but Hicolor is already filtered out)
            unless ($self->_validate_theme_quality($theme_path, $subdir)) {
                next;
            }

            # Parse theme information
            my $theme_info = $self->_parse_icon_theme_info($theme_path, $subdir);

            # FINAL CHECK: Validate theme info doesn't contain hicolor references
            if ($theme_info->{name} && lc($theme_info->{name}) =~ /hicolor|default/i) {
                next;
            }
            if ($theme_info->{display_name} && lc($theme_info->{display_name}) =~ /hicolor|default/i) {
                next;
            }

            # Mark this theme name as seen
            $seen_themes{$subdir} = 1;

            push @themes, $theme_info;
        }

        return @themes;
    }
        
    sub _scan_theme_structure {
        my ($self, $theme_path) = @_;


        my @icon_directories = ();

        # Target directories we care about (updated for 4x4 grid requirements)
        my @content_dirs = ('places', 'devices', 'mimes', 'mimetypes');
        my @quality_dirs = ('scalable', '96x96', '64x64', '48x48');


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

        # Look for quality_dir/content_dir combinations
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
                            }
                        }
                    }
                }
            }
        }

        # Look for content_dir/quality_dir combinations
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

        if (@icon_directories) {
            for my $i (0..$#icon_directories) {
                my $type = $icon_directories[$i]->{priority} == 1 ? "SVG" : "PNG";
            }
        }

        return @icon_directories;
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
                return;
            }
        }

        # Also check if preview is currently being generated
        if ($self->{currently_generating_preview} &&
            $self->{currently_generating_preview} eq $current_name) {
            return;
        }

        # Add to queue
        push @{$self->{preview_generation_queue}}, {
            theme_info => $theme_info,
            cache_file => $cache_file,
            width => $width,
            height => $height
        };


        # Start processing queue if not already running
        if (!$self->{preview_generation_active}) {
            $self->_process_preview_generation_queue();
        }
    }

    sub _schedule_preview_generation_for_size {
        my ($self, $theme_info, $cache_file, $width, $height) = @_;


        # Add to generation queue if not already queued
        if (!$self->{preview_generation_queue}) {
            $self->{preview_generation_queue} = [];
        }

        # Check if already queued - handle undefined theme names and prevent duplicates
        my $current_name = $theme_info->{name} || '';
        return if $current_name eq ''; # Skip if no theme name

        # Create unique key for this size
        my $queue_key = "${current_name}-${width}x${height}";
        
        foreach my $queued (@{$self->{preview_generation_queue}}) {
            my $queued_name = $queued->{theme_info}->{name} || '';
            my $queued_key = "${queued_name}-$queued->{width}x$queued->{height}";
            if ($queued_key eq $queue_key) {
                return;
            }
        }

        # Also check if preview is currently being generated
        if ($self->{currently_generating_preview} &&
            $self->{currently_generating_preview} eq $queue_key) {
            return;
        }

        # Add to queue
        push @{$self->{preview_generation_queue}}, {
            theme_info => $theme_info,
            cache_file => $cache_file,
            width => $width,
            height => $height
        };


        # Start processing queue if not already running
        if (!$self->{preview_generation_active}) {
            $self->_process_preview_generation_queue();
        }
    }

    sub _draw_icon_grid {
        my ($self, $cr, $icon_pixbufs, $width, $height) = @_;

        #  Redirect to high-quality version for consistency
        return $self->_draw_high_quality_icon_grid($cr, $icon_pixbufs, $width, $height);
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

    sub _create_mode_buttons {
        my $self = shift;

        my $icons_mode = Gtk3::ToggleButton->new_with_label('Icon Themes');
        my $settings_mode = Gtk3::ToggleButton->new_with_label('Settings');

        $icons_mode->set_active(1); # Active by default

        return ($icons_mode, $settings_mode);
    }

    sub _create_placeholder_widget {
        my ($self, $theme_info) = @_;

        # Create frame with inset shadow
        my $frame = Gtk3::Frame->new();
        $frame->set_shadow_type('in');

        # Create vertical box container
        my $box = Gtk3::Box->new('vertical', 6);
        $box->set_margin_left(6);
        $box->set_margin_right(6);
        $box->set_margin_top(6);
        $box->set_margin_bottom(6);

        # Create simple placeholder - very fast
        my $placeholder = $self->_create_simple_placeholder($self->zoom_level, int($self->zoom_level * 0.75));
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
        my ($self, $width, $height) = @_;

        # Create solid color pixbuf - very fast, no Cairo
        my $pixbuf = Gtk3::Gdk::Pixbuf->new('rgb', 1, 8, $width, $height);
        $pixbuf->fill(0xf0f0f0ff); # Light gray background
        
        return Gtk3::Image->new_from_pixbuf($pixbuf);
    }

    sub _create_zoom_buttons {
        my $self = shift;

        my $zoom_out = Gtk3::Button->new();
        $zoom_out->set_relief('none');
        $zoom_out->set_size_request(32, 32);
        $zoom_out->set_tooltip_text('Decrease preview size (600px → 500px → 400px)');

        my $zoom_in = Gtk3::Button->new();
        $zoom_in->set_relief('none');
        $zoom_in->set_size_request(32, 32);
        $zoom_in->set_tooltip_text('Increase preview size (400px → 500px → 600px)');

        # Use system icons for zoom
        my $zoom_out_icon = Gtk3::Image->new_from_icon_name('zoom-out-symbolic', 1);
        $zoom_out->add($zoom_out_icon);

        my $zoom_in_icon = Gtk3::Image->new_from_icon_name('zoom-in-symbolic', 1);
        $zoom_in->add($zoom_in_icon);

        return ($zoom_out, $zoom_in);
    }

    sub _display_themes_immediately {
        my ($self, $themes_ref, $dir_path) = @_;
        
        my $total_themes = @$themes_ref;
        print "Displaying $total_themes themes immediately\n";
        
        if ($total_themes == 0) {
            $self->_show_no_themes_message();
            return;
        }
        
        #  Use current zoom level from object
        my $current_zoom = $self->zoom_level;
        
        # Create ALL widgets immediately with simple placeholders at current zoom level
        foreach my $theme_info (@$themes_ref) {
            my $widget = $self->_create_instant_theme_widget_at_zoom($theme_info, $current_zoom);
            $self->icons_grid->add($widget);
        }
        
        $self->icons_grid->show_all();
        $self->_hide_loading_indicator();
        
        # Start lazy preview loading in background at current zoom level
        $self->_start_lazy_preview_loading_at_zoom($themes_ref, $dir_path, $current_zoom);
    }

    sub _draw_high_quality_icon_grid {
        my ($self, $cr, $icon_pixbufs, $width, $height) = @_;

        return unless @$icon_pixbufs > 0;


        #  Set highest quality Cairo rendering settings
        $cr->set_antialias('subpixel');  # Best antialiasing for sharp text and edges
        
        # Use light background as requested
        $cr->set_source_rgb(0.98, 0.98, 0.98); # Very light gray background
        $cr->rectangle(0, 0, $width, $height);
        $cr->fill();

        # Always use 4x4 grid layout for 16 icons
        my $cols = 4;
        my $rows = 4;

        my $cell_width = $width / $cols;  # Use floating point for precision
        my $cell_height = $height / $rows;


        #  Calculate icon size based on preview size - use more space for larger previews
        my $margin_ratio;
        if ($width >= 600) {
            $margin_ratio = 0.04;  # Very small margins for 600px previews
        } elsif ($width >= 500) {
            $margin_ratio = 0.05;  # Small margins for 500px previews
        } else {
            $margin_ratio = 0.08;  # Standard margins for 400px previews
        }
        
        my $margin = ($cell_width < $cell_height ? $cell_width : $cell_height) * $margin_ratio;
        my $icon_size = ($cell_width < $cell_height ? $cell_width : $cell_height) - ($margin * 2);


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


                        # Get current pixbuf dimensions
                        my $current_width = $pixbuf->get_width();
                        my $current_height = $pixbuf->get_height();

                        #  Only scale if necessary, and use highest quality scaling
                        my $final_size = int($icon_size);
                        my $scaled_pixbuf;

                        if ($current_width != $final_size || $current_height != $final_size) {
                            $scaled_pixbuf = $pixbuf->scale_simple($final_size, $final_size, 'hyper');
                        } else {
                            $scaled_pixbuf = $pixbuf;
                        }

                        #  Draw with sub-pixel precision and highest quality filter
                        Gtk3::Gdk::cairo_set_source_pixbuf($cr, $scaled_pixbuf, $draw_x, $draw_y);
                        my $pattern = $cr->get_source();
                        $pattern->set_filter('best');  # Highest quality rendering filter
                        $cr->paint();
                    }

                    $icon_index++;
                }
            }
        }

        #  Add very subtle grid lines only for larger previews to show structure
        if ($width >= 500) {
            $cr->set_source_rgba(0, 0, 0, 0.02); # Ultra-subtle grid lines
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

    }

    sub _draw_ultra_sharp_icon_grid {
        my ($self, $cr, $icon_pixbufs, $width, $height) = @_;

        return unless @$icon_pixbufs > 0;


        # Use light background as requested
        $cr->set_source_rgb(0.98, 0.98, 0.98); # Very light gray background
        $cr->rectangle(0, 0, $width, $height);
        $cr->fill();

        # Always use 4x4 grid layout for 16 icons
        my $cols = 4;
        my $rows = 4;

        my $cell_width = $width / $cols;  # Use floating point for precision
        my $cell_height = $height / $rows;


        # Calculate icon size - use even more of the cell for larger previews
        my $margin_ratio = ($width >= 600) ? 0.03 : 0.05;  # Even smaller margins for ultra-sharp
        my $margin = ($cell_width < $cell_height ? $cell_width : $cell_height) * $margin_ratio;
        my $icon_size = ($cell_width < $cell_height ? $cell_width : $cell_height) - ($margin * 2);


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


                        # Get current pixbuf dimensions
                        my $current_width = $pixbuf->get_width();
                        my $current_height = $pixbuf->get_height();

                        # Only scale if necessary, and use highest quality
                        my $final_size = int($icon_size);
                        my $scaled_pixbuf;

                        if ($current_width != $final_size || $current_height != $final_size) {
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
            }
        }
    }

    sub _scale_existing_preview_to_size {
        my ($self, $preview_widget, $new_width, $new_height) = @_;


        # Get the current pixbuf from the preview widget
        my $current_pixbuf = $preview_widget->get_pixbuf();

        if ($current_pixbuf) {
            eval {
                # Scale the existing pixbuf to the new size for immediate feedback
                my $scaled_pixbuf = $current_pixbuf->scale_simple(
                    $new_width,
                    $new_height,
                    'bilinear'  # Fast scaling
                );

                if ($scaled_pixbuf) {
                    $preview_widget->set_from_pixbuf($scaled_pixbuf);
                }
            };
            if ($@) {
            }
        } else {
        }
    }  

    sub min {
        my ($a, $b) = @_;
        return $a < $b ? $a : $b;
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

    sub _extract_high_res_theme_icons {
        my ($self, $theme_info, $preview_size) = @_;

        my @icon_pixbufs = ();
        my $theme_path = $theme_info->{path};


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


        # First, let's verify the theme path exists
        unless (-d $theme_path) {
            return @icon_pixbufs;
        }

        # Search for each icon type directly in the theme with high resolution
        foreach my $icon_type (@{$self->icon_types}) {
            my $pixbuf = $self->_find_high_res_icons($theme_path, $icon_type, $icon_resolution);
            if ($pixbuf) {
                push @icon_pixbufs, $pixbuf;
            } else {
            }
        }

        return @icon_pixbufs;
    }

    sub _extract_theme_icons {
        my ($self, $theme_info) = @_;

        my @icon_pixbufs = ();
        my $theme_path = $theme_info->{path};


        # First, let's verify the theme path exists
        unless (-d $theme_path) {
            return @icon_pixbufs;
        }

        # Search for each icon type directly in the theme
        foreach my $icon_type (@{$self->icon_types}) {
            my $pixbuf = $self->_find_icons($theme_path, $icon_type);
            if ($pixbuf) {
                push @icon_pixbufs, $pixbuf;
            } else {
            }
        }

        return @icon_pixbufs;
    }

    sub _extract_ultra_high_res_theme_icons {
        my ($self, $theme_info, $preview_size) = @_;

        my @icon_pixbufs = ();
        my $theme_path = $theme_info->{path};


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


        # First, let's verify the theme path exists
        unless (-d $theme_path) {
            return @icon_pixbufs;
        }

        # Search for each icon type directly in the theme with ultra-high resolution
        foreach my $icon_type (@{$self->icon_types}) {
            my $pixbuf = $self->_find_ultra_high_res_icons($theme_path, $icon_type, $icon_resolution);
            if ($pixbuf) {
                push @icon_pixbufs, $pixbuf;
            } else {
            }
        }

        return @icon_pixbufs;
    }

    sub _find_icon_quickly {
        my ($self, $theme_path, $icon_name) = @_;
        
        
        # Step 1: Find all icon directories using real Linux patterns
        my @icon_directories = $self->_scan_theme_directories_optimized($theme_path);
        
        if (@icon_directories == 0) {
            return undef;
        }
        
        # Step 2: Search for the icon in priority order (SVG first, then PNG by size)
        return $self->_search_icon_in_directories($icon_name, \@icon_directories);
    }

    sub _get_height_for_width {
        my ($self, $width) = @_;
        # Maintain 4:3 aspect ratio
        return int($width * 0.75);
    }  

    sub _hide_loading_indicator {
        my $self = shift;

        $self->loading_spinner->stop();
        $self->loading_box->hide();
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










    