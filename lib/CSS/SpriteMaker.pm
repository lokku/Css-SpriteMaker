package CSS::SpriteMaker;

use strict;
use warnings;

use feature qw(say);

use File::Find;
use Image::Magick;

use CSS::SpriteMaker::Layout::DirectoryBased;
use CSS::SpriteMaker::Layout::Packed;

use POSIX qw(ceil);


=head1 NAME

CSS::SpriteMaker - Combine several images into a single CSS sprite

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

    use CSS::SpriteMaker;

    my $SpriteMaker = CSS::SpriteMaker->new(
        source_dir => '/tmp/test/images',
        target_file => '/tmp/test/mysprite.png',
        format => 'png8',           # optional
        remove_source_padding => 1, # optional
        verbose => 1,               # optional
        output_css_file => /path/to/file.css,   # optional
        output_html_file => /path/to/file.html  # optional
    );

    $SpriteMaker->make();

Once make() is called, the specified target_file is created.

=head1 METHODS

=head2 new

Create and configure a new CSS::SpriteMaker object.

The object must be initialised as follows:
    
    my $SpriteMaker = CSS::SpriteMaker->new({
        source_dir => '/tmp/test/images',
        target_file => '/tmp/test/mysprite.png'
        format => 'png',
        remove_source_padding => 1,
        same_size => 0,
        verbose => 1,
        output_css_file => /path/to/file.css,
        output_html_file => /path/to/file.html,
    });

=cut
sub new {
    my $class  = shift;
    my %opts   = @_;

    # defaults
    $opts{remove_source_padding} //= 1;
    $opts{verbose}               //= 0;
    $opts{format}                //= 'png';
    $opts{same_size}             //= 0;
    
    my $self = {
        source_dir => $opts{source_dir},
        target_file => $opts{target_file},
        is_verbose => $opts{verbose},
        format => $opts{format},
        remove_source_padding => $opts{remove_source_padding},
        output_css_file => $opts{output_css_file},
        output_html_file => $opts{output_html_file},

        # the maximum color value
        color_max => 2 ** Image::Magick->QuantumDepth - 1,
    };

    return bless $self, $class;
}

=head2 make

Creates the CSS sprite according to the current configuration.

Returns true if the image was successfully created and false otherwise.

=cut

sub make {
    my $self = shift;

    $self->_verbose("Target file: " . $self->{target_file});
    $self->_verbose("Checking " . $self->{source_dir});

    # collect information about each source image
    # - width: width of image in pixels
    # - height: height of image in pixels
    # - name: the file name
    my %source_info;

    my $source_total = 0;

    # the filenames of the images
    $self->_verbose(" * gathering files and directories of source images");
    my $id = 0;
    find(sub {
        my $filename = $_;
        my $fullpath = $File::Find::name;
        my $parentdir = $File::Find::dir;
    
        return if $filename eq '.';

        if (-f $filename) {
            $source_info{$id}{name} = $filename;
            $source_info{$id}{pathname} = $fullpath;
            $source_info{$id}{parentdir} = $parentdir;
            $id++;
        }

    }, $self->{source_dir});

    $self->_verbose(" * analysing source images");

    # collect properties of each input image
    IMAGE:
    for my $id (keys %source_info) {
        my %properties = %{$self->_get_image_properties(
            $source_info{$id}{pathname}
        )};

        # skip invalid images
        next IMAGE if !%properties;

        for my $property (keys %properties) {
            $source_info{$id}{$property} = $properties{$property};
        };
    }

    # devise the best layout
    $self->_verbose(" * creating layout");
    my $Layout = CSS::SpriteMaker::Layout::DirectoryBased->new(\%source_info);
    $Layout = CSS::SpriteMaker::Layout::Packed->new(\%source_info);

    # my $rh_layout = $self->layout_items(\%source_info);

    # save image
    $self->_verbose(" * writing sprite image");
    my $err = $self->_write_sprite($Layout, \%source_info);

    # save stylesheet
    if (defined $self->{output_css_file}) {
        $err += $self->_write_stylesheet($Layout, \%source_info);
    }
    if (defined $self->{output_html_file}) {
        $err += $self->_write_html($Layout, \%source_info);
    }

    return !$err;
}

=head2 _get_stylesheet_string

Returns the stylesheet in a string.

=cut

sub _get_stylesheet_string {
    my $self            = shift;
    my $rh_layout       = shift;
    my $rh_sources_info = shift;

    my @stylesheet;
    
    # a list of classes
    my @classes =
        map { $self->_generate_css_class_name($_) }
        map { my $name = $_; $name =~ s/@//g; $name }
        map { $rh_sources_info->{$_}{name} }
        keys %$rh_sources_info;

    # write header
    # header associates the sprite image to each class
    push @stylesheet, sprintf("%s { background-image: url('%s'); background-repeat: no-repeat; }",
        join(",", @classes),
        $self->{target_file}
    );

    # now take care of individual sections
    for my $id (keys %$rh_sources_info) {

        if (defined $rh_layout->{items}{$id}) {
            my $rh_source_info = $rh_sources_info->{$id};
            my $css_class = $self->_generate_css_class_name($rh_source_info->{name});

            push @stylesheet, sprintf("%s { background-position: %spx %spx; width: %spx; height: %spx; }",
                $css_class,
                -1 * $rh_layout->{items}{$id}{x},
                -1 * $rh_layout->{items}{$id}{y},
                $rh_source_info->{width},
                $rh_source_info->{height},
            );
        }
    }

    return join "\n", @stylesheet;
}

=head2 _write_stylesheet

Creates the stylesheet for the sprite that was just produced. Follows the
format specified on creation.

=cut

sub _write_stylesheet {
    my $self            = shift;
    my $rh_layout       = shift;
    my $rh_sources_info = shift;

    $self->_verbose("  * writing " . $self->{output_css_file});

    open my ($fh), '>', $self->{output_css_file};

    my $stylesheet = $self->_get_stylesheet_string($rh_layout, $rh_sources_info);

    print $fh $stylesheet;

    close $fh;

    return 0;
}

=head2 _write_html

Creates a sample html webpage for the sprite produced.

=cut
sub _write_html {
    my $self = shift;
    my $rh_layout = shift;
    my $rh_sources_info = shift;
    
    $self->_verbose("  * writing " . $self->{output_html_file});

    my $stylesheet = $self->_get_stylesheet_string($rh_layout, $rh_sources_info);

    open my ($fh), '>', $self->{output_html_file};

    print $fh '<html><head><style type="text/css">';
    print $fh $stylesheet;
    print $fh <<EOCSS;
    .color {
        width: 10px;
        height: 10px;
        margin: 1px;
        float: left;
        border: 1px solid black;
    }
    .item-container {
        clear: both;
        background-color: #BCE;
        width: 340px;
        margin: 10px;
        -webkit-border-radius: 10px;
        -moz-border-radius: 10px;
        -o-border-radius: 10px;
        border-radius: 10px;
    }
EOCSS
    print $fh '</style></head><body>';

    # html
    for my $id (keys %$rh_sources_info) {
        my $rh_source_info = $rh_sources_info->{$id};
        my $css_class = $self->_generate_css_class_name($rh_source_info->{name});

        $css_class =~ s/[.]//;

        print $fh '<div class="item-container">';
        print $fh "  <div class=\"item $css_class\"></div>";
        print $fh "  <div class=\"item_description\">";
        for my $key (keys %$rh_source_info) {
            next if $key eq "colors";
            print $fh "<b>" . $key . "</b>: " . ($rh_source_info->{$key} // 'none') . "<br />";
        }
        print $fh '<h3>Colors</h3>';
            print $fh "<b>total</b>: " . $rh_source_info->{colors}{total} . '<br />';
            for my $colors (keys %{$rh_source_info->{colors}{map}}) {
                my ($r, $g, $b, $a) = split /,/, $colors;
                my $rrgb = $r * 255 / $self->{color_max};
                my $grgb = $g * 255 / $self->{color_max};
                my $brgb = $b * 255 / $self->{color_max};
                my $argb = 255 - ($a * 255 / $self->{color_max});
                print $fh '<div class="color" style="background-color: ' . "rgba($rrgb, $grgb, $brgb, $argb);\"></div>";
            }
        print $fh "  </div>";
        print $fh '</div>';
    }

    print $fh "</body></html>";

    return 0;
}

=head2 _generate_css_class_name

This method generates the name of the CSS class for a certain image file. Takes
the image filename as input and produces a css class name (including the .)

=cut

sub _generate_css_class_name {
    my $self = shift;
    my $filename = shift;

    # prepare
    my $css_class = $filename;

    # remove the extension if any
    $css_class =~ s/[.].*\Z//i;

    return ".$css_class";
}

=head2 _write_sprite

Actually creates the sprite file according to the given layout.

=cut

sub _write_sprite {
    my $self = shift;
    my $Layout = shift;
    my $rh_sources_info = shift;

    $self->_verbose(sprintf("Target image size: %s, %s",
        $Layout->width(),
        $Layout->height())
    );

    my $Target = Image::Magick->new();

    $Target->Set(size => sprintf("%sx%s",
        $Layout->width(),
        $Layout->height()
    ));

    # prepare the target image
    if (my $err = $Target->ReadImage('xc:white')) {
        warn $err;
    }
    $Target->Set(type => 'TruecolorMatte');
    
    # make it transparent
    $self->_verbose(" - clearing canvas");
    $Target->Draw(
        fill => 'transparent', 
        primitive => 'rectangle', 
        points => sprintf("0,0 %s,%s", $Layout->width(), $Layout->height())
    );
    $Target->Transparent('color' => 'white');

    # place each image according to the layout
    ITEM_ID:
    for my $source_id ($Layout->get_item_ids) {
        my $rh_source_info = $rh_sources_info->{$source_id};
        my ($layout_x, $layout_y) = $Layout->get_item_coord($source_id);

        $self->_verbose(sprintf(" - placing %s (format: %s  size: %sx%s  position: [%s,%s])",
            $rh_source_info->{pathname},
            $rh_source_info->{format},
            $rh_source_info->{width},
            $rh_source_info->{height},
            $layout_y,
            $layout_x
        ));
        my $I = Image::Magick->new(); 
        my $err = $I->Read($rh_source_info->{pathname});
        if ($err) {
            warn $err;
            next ITEM_ID;
        }

        # place soure image in the target image according to the layout
        my $destx = $layout_x;
        my $startx = $rh_source_info->{first_pixel_x};
        my $starty = $rh_source_info->{first_pixel_y};
        for my $x ($startx .. $startx + $rh_source_info->{width} - 1) {
            my $desty = $layout_y;
            for my $y ($starty .. $starty + $rh_source_info->{height} - 1) {
                my $p = $I->Get(
                    sprintf('pixel[%s,%s]', $x, $y),
                );
                $Target->Set(
                    sprintf('pixel[%s,%s]', $destx, $desty), $p); 
                $desty++;
            }
            $destx++;
        }
    }

    # write target image
    my $err = $Target->Write("$self->{format}:".$self->{target_file});
    if ($err) {
        warn "unable to obtain $self->{target_file} for writing it as $self->{format}. Perhaps you have specified an invalid format. Check http://www.imagemagick.org/script/formats.php for a list of supported formats. Error: $err";

        $self->_verbose("Wrote $self->{target_file}");

        return 1;
    }

    return 0;
}

=head2 _get_image_properties

Return an hashref of information about the image at the given pathname.

=cut

sub _get_image_properties {
    my $self       = shift;
    my $image_path = shift;

    my $Image = Image::Magick->new();

    my $err = $Image->Read($image_path);
    if ($err) {
        warn $err;
        return {};
    }

    my $rh_info = {};
    $rh_info->{first_pixel_x} = 0,
    $rh_info->{first_pixel_y} = 0,
    $rh_info->{width} = $Image->Get('columns');
    $rh_info->{height} = $Image->Get('rows');
    $rh_info->{comment} = $Image->Get('comment');
    $rh_info->{colors}{total} = $Image->Get('colors');
    $rh_info->{format} = $Image->Get('magick');

    if ($self->{remove_source_padding}) {
        #
        # Find borders for this image.
        #
        # (RE-)SET:
        # - first_pixel(x/y) as the true point the image starts
        # - width/height as the true dimensions of the image
        #
        my $w = $rh_info->{width};
        my $h = $rh_info->{height};

        # seek for left/right borders
        my $first_left = 0;
        my $first_right = $w-1;
        my $left_found = 0;
        my $right_found = 0;

        BORDER_HORIZONTAL:
        for my $x (0 .. ceil(($w-1)/2)) {
            my $xr = $w-$x-1;
            for my $y (0..$h-1) {
                my $al = $Image->Get(sprintf('pixel[%s,%s]', $x, $y));
                my $ar = $Image->Get(sprintf('pixel[%s,%s]', $xr, $y));
                
                # remove rgb info and only get alpha value
                $al =~ s/^.+,//;
                $ar =~ s/^.+,//;

                if ($al != $self->{color_max} && !$left_found) {
                    $first_left = $x;
                    $left_found = 1;
                }
                if ($ar != $self->{color_max} && !$right_found) {
                    $first_right = $xr;
                    $right_found = 1;
                }
                last BORDER_HORIZONTAL if $left_found && $right_found;
            }
        }
        $rh_info->{first_pixel_x} = $first_left;
        $rh_info->{width} = $first_right - $first_left + 1;

        # seek for top/bottom borders
        my $first_top = 0;
        my $first_bottom = $h-1;
        my $top_found = 0;
        my $bottom_found = 0;

        BORDER_VERTICAL:
        for my $y (0 .. ceil(($h-1)/2)) {
            my $yb = $h-$y-1;
            for my $x (0 .. $w-1) {
                my $at = $Image->Get(sprintf('pixel[%s,%s]', $x, $y));
                my $ab = $Image->Get(sprintf('pixel[%s,%s]', $x, $yb));
                
                # remove rgb info and only get alpha value
                $at =~ s/^.+,//;
                $ab =~ s/^.+,//;

                if ($at != $self->{color_max} && !$top_found) {
                    $first_top = $y;
                    $top_found = 1;
                }
                if ($ab != $self->{color_max} && !$bottom_found) {
                    $first_bottom = $yb;
                    $bottom_found = 1;
                }
                last BORDER_VERTICAL if $top_found && $bottom_found;
            }
        }
        $rh_info->{first_pixel_y} = $first_top;
        $rh_info->{height} = $first_bottom - $first_top + 1;
    }

    # Store information about the color of each pixel
    $rh_info->{colors}{map} = {};
    for my $x ($rh_info->{first_pixel_x} .. $rh_info->{width}) {
        for my $y ($rh_info->{first_pixel_y} .. $rh_info->{height}) {
            my $color = $Image->Get(
                sprintf('pixel[%s,%s]', $x, $y),
            );
            push @{$rh_info->{colors}{map}{$color}}, {
                x => $x,
                y => $y,
            };
        }
    }

    return $rh_info; 
}

=head2 _generate_color_histogram

Generate color histogram out of the information structure of all the images.

=cut

sub _generate_color_histogram {
    my $self           = shift;
    my $rh_source_info = shift;

    my %histogram;
    for my $id (keys %$rh_source_info) {
        for my $color (keys %{ $rh_source_info->{$id}{colors}{map} }) {
            my $rah_colors_info = $rh_source_info->{$id}{colors}{map}{$color};

            $histogram{$color} = scalar @$rah_colors_info;
        }
    }

    return \%histogram;
}

=head2 _verbose

Print verbose output only if the verbose option was passed as input.

=cut

sub _verbose {
    my $self = shift;
    my $msg  = shift;

    if ($self->{is_verbose}) {
        print "${msg}\n";
    }
}

=head1 LICENSE AND COPYRIGHT

Copyright 2012 Savio Dimatteo.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of CSS::SpriteMaker
