package CSS::SpriteMaker;

use strict;
use warnings;

use feature qw(say);

use File::Find;
use Image::Magick;

use CSS::SpriteMaker::BinPacking;

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
    );

    $SpriteMaker->make();

Once make() is called, the specified target_file is created.


=head2 CONFIGURATION FORMAT

=head1 METHODS

=head2 new

Create and configure a new CSS::SpriteMaker object.

The object must be initialised as follows:
    
    my $cleanup = File::Cleanup->new({
        source_dir => '/tmp/test/images',
        target_file => '/tmp/test/mysprite.png'
        format => 'png',
        remove_source_padding => 1,
        verbose => 1,
    });

=cut
sub new {
    my $class  = shift;
    my %opts   = @_;

    # defaults
    $opts{remove_source_padding} //= 1;
    $opts{verbose}               //= 0;
    $opts{format}                //= 'png';
    
    my $self = {
        source_dir => $opts{source_dir},
        target_file => $opts{target_file},
        is_verbose => $opts{verbose},
        format => $opts{format},
        remove_source_padding => $opts{remove_source_padding},

        # the maximum color value
        color_max => (2^Image::Magick->QuantumDepth) - 1,
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
    my $rh_layout = $self->layout_items_bydir(\%source_info);

    # save image
    my $err = $self->_write_sprite($rh_layout, \%source_info);

    # save stylesheet
    $err += $self->_write_stylesheet($rh_layout, \%source_info);

    return !$err;
}

=head2 _write_stylesheet

Creates the stylesheet for the sprite that was just produced. Follows the
format specified on creation.

=cut
sub _write_stylesheet {
    my $self = shift;
    my $rh_layout = shift;
    my $rh_sources_info = shift;

    # a list of classes
    my @classes =
        map { $self->_generate_css_class_name($_) }
        map { my $name = $_; $name =~ s/@//g; $name }
        map { $rh_sources_info->{$_}{name} }
        keys %$rh_sources_info;

    say '<html><head><style type="text/css">';

    # write header
    # header associates the sprite image to each class
    say sprintf("%s { background-image: url('%s'); background-repeat: no-repeat; }",
        join(",", @classes),
        'sample_icons.png'
    );

    # now take care of individual sections
    for my $id (keys %$rh_sources_info) {

        if (defined $rh_layout->{items}{$id}) {
            my $rh_source_info = $rh_sources_info->{$id};
            my $css_class = $self->_generate_css_class_name($rh_source_info->{name});

            say sprintf("%s { background-position: %spx %spx; width: %spx; height: %spx; }",
                $css_class,
                -1 * $rh_layout->{items}{$id}{x},
                -1 * $rh_layout->{items}{$id}{y},
                $rh_source_info->{width},
                $rh_source_info->{height},
            );
        }
    }
    
    say '</style></head><body>';

    # html
    for my $id (keys %$rh_sources_info) {
        my $rh_source_info = $rh_sources_info->{$id};
        my $css_class = $self->_generate_css_class_name($rh_source_info->{name});

        $css_class =~ s/[.]//;

        say "<div class=\"$css_class\"></div>";
    }

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
    my $rh_layout = shift;
    my $rh_sources_info = shift;


    $self->_verbose(sprintf("Target image size: %s, %s",
        $rh_layout->{width},
        $rh_layout->{height})
    );

    my $Target = Image::Magick->new();

    $Target->Set(size => sprintf("%sx%s",
        $rh_layout->{width},
        $rh_layout->{height}
    ));

    # prepare the target image
    $Target->ReadImage('canvas:transparent');
    $Target->Set(type => 'TruecolorMatte');

    # place each image according to the layout
    ITEM_ID:
    for my $source_id (keys %{$rh_layout->{items}}) {
        my $rh_source_layout = $rh_layout->{items}{$source_id};
        my $rh_source_info = $rh_sources_info->{$source_id};

        $self->_verbose(sprintf("Placing %s (%s)",
            $rh_source_info->{pathname},
            $rh_source_info->{format})
        );

        # read input image (again - we will be reading individual pixels soon)
        my $I = Image::Magick->new(); 
        my $err = $I->Read($rh_source_info->{pathname});
        if ($err) {
            warn $err;
            next ITEM_ID;
        }

        # place soure image in the target image according to the layout
        my $destx = $rh_source_layout->{x};
        my $startx = $rh_source_info->{first_pixel_x};
        my $starty = $rh_source_info->{first_pixel_y};
        for my $x ($startx .. $startx + $rh_source_info->{width} - 1) {
            my $desty = $rh_source_layout->{y};
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
        warn "unable to opten $self->{target_file} for writing it as $self->{format}. Perhaps you have specified an invalid format. Check http://www.imagemagick.org/script/formats.php for a list of supported formats";

        $self->_verbose("Wrote $self->{target_file}");

        return 1;
    }

    return 0;
}

=head2 layout_items

Lay out items on a 2D space. Information about width and height of each item
must be known a priori.

The input information structure is expected to be a hashref of the form:

$rh_items_info = {
    'item_id_1' => {
        width => 300,
        height => 250,
    },
    'item_id_2' => {
        width => 100,
        height => 100,
    },
    # ... more items
}

The output layout structure contains information about the dimension of the 2D
space and tells where each item will be placed. For each item, this resulting
structure indicates the starting (x, y) coordinate in the 2D space, with 
(0, 0) being the top left pixel.

This structure looks like:

$rh_layout = {
    width => 400,   # layout is 300px wide
    height => 250,  # layout is 250px high
    items {
        'item_id_1' => {
            'x' => 0,
            'y' => 0,
        },
        'item_id_2' => {
            'x' => 300,
            'y' => 0,
        },
    }
}

=cut

sub layout_items {
    my $self          = shift;
    my $rh_items_info = shift;

    # our result layout structure
    my $rh_layout = {
        width  => 0,
        height => 0,
        items  => {},
    };

    # sort items by height
    my @items_sorted =
        sort {
            $rh_items_info->{$b}{width}
                <=>
            $rh_items_info->{$a}{width}
        }
        keys %$rh_items_info;
   
    # pack the items
    my $Packer = CSS::SpriteMaker::BinPacking->new();

    # copy the items into blocks (input for the packer)
    my @blocks = map {
        { w => $rh_items_info->{$_}{width},
          h => $rh_items_info->{$_}{height}, 
          id => $_,
        }
    } @items_sorted;

    # fit each block
    $Packer->fit(\@blocks);

    my $max_w = 0;
    my $max_h = 0;
    for my $rh_block (@blocks) {

        my $block_id = $rh_block->{id};

        if (my $rh_fit = $rh_block->{fit}) {
            # convert to more clean structure - i.e., take from the packed boxes
            # the only two information that we're interested in and augment our
            # layout
            $rh_layout->{items}{$block_id} = {
                x => $rh_fit->{x},
                y => $rh_fit->{y},
            };
            
            # compute the overall width/height
            $max_w = $rh_fit->{w} + $rh_fit->{x} if $max_w < $rh_fit->{w} + $rh_fit->{x};
            $max_h = $rh_fit->{h} + $rh_fit->{y} if $max_h < $rh_fit->{h} + $rh_fit->{y};
        }
        else {
            warn "Wasn't able to fit block $block_id";
        }
    }

    # write dimensions in the resulting layout
    $rh_layout->{width} = $max_w;
    $rh_layout->{height} = $max_h;

    return $rh_layout;
}

=head2 layout_items_bydir

Lay out items according to their parent directory name. Items that are found in
the same directory will be grouped in the same row. A group of items in one row
is sorted by file name.

See layout_items for more information as the format of the returned hash is the
same.

=cut

sub layout_items_bydir {
    my $self          = shift;
    my $rh_items_info = shift;

    # our result layout structure
    my $rh_layout = {
        width  => 0,  # the width of the overall layout
        height => 0,  # the height of the overall layout
        items  => {},  # the position of items { id => {x => ... , y => ... } }
    };

    # 1. sort items by directory, then filename
    my @items_id_sorted = 
    sort {
        $rh_items_info->{$a}{pathname}
            cmp
        $rh_items_info->{$b}{pathname}
    }
    keys %$rh_items_info;

    
    # 2. put items from the same directory in the same row
    my $x = 0;
    my $y = 0;
    my $total_height = 0;
    my $total_width = 0;
    my $row_height = 0;

    my $parentdir_prev;
    for my $id (@items_id_sorted) {
        my $w = $rh_items_info->{$id}{width};
        my $h = $rh_items_info->{$id}{height};
        my $parentdir = $rh_items_info->{$id}{parentdir};

        if (defined $parentdir_prev && $parentdir ne $parentdir_prev) {
            # next row!
            $y += $row_height;
            $x = 0;
            $row_height = 0;
        }

        # chain on this row...
        $rh_layout->{items}{$id} = {
            x => $x,
            y => $y
        };
        $x += $w;
        $row_height = $h if $h > $row_height;
        $total_width = $x if $x > $total_width;
        $total_height = $y + $row_height if $y + $row_height > $total_height;

        $parentdir_prev = $parentdir;
    }

    $rh_layout->{width} = $total_width;
    $rh_layout->{height} = $total_height;

    return $rh_layout;
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
