package CSS::SpriteMaker;

use strict;
use warnings;

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
        remove_source_padding => 1,
        verbose => 1,
    });

=cut
sub new {
    my $class  = shift;
    my %opts   = @_;

    # defaults
    $opts{remove_source_padding} //= 1;
    $opts{verbose}               //= 1;
    
    my $self = {
        source_dir => $opts{source_dir},
        target_file => $opts{target_file},
        is_verbose => $opts{verbose},
        remove_source_padding => $opts{remove_source_padding},

        # the maximum color value
        color_max => (2^Image::Magick->QuantumDepth) - 1,
    };

    return bless $self, $class;
}

=head2 make

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

        return if $filename eq '.';

        $source_info{$id}{name} = $filename;
        $source_info{$id}{pathname} = $fullpath;
        $id++;

    }, $self->{source_dir});

    # collect properties of each input image
    IMAGE:
    for my $id (keys %source_info) {
        my %properties = %{$self->_identify_image(
            $source_info{$id}{pathname}
        )};

        # skip invalid images
        next IMAGE if !%properties;

        for my $property (keys %properties) {
            $source_info{$id}{$property} = $properties{$property};
        };
    }

    # devise the best layout
    my $rh_layout = $self->layout_items(\%source_info);

    # make our image
    $self->_verbose(sprintf("Target image size: %s, %s",
        $rh_layout->{width},
        $rh_layout->{height})
    );
    my $Target = Image::Magick->new();
    $Target->Set(size => sprintf("%sx%s",
        $rh_layout->{width},
        $rh_layout->{height}
    ));
    $Target->ReadImage('canvas:transparent');
    $Target->Set(type => 'TruecolorMatte');

    # place each image according to the layout
    ITEM_ID:
    for my $source_id (keys %{$rh_layout->{items}}) {
        my $rh_source_layout = $rh_layout->{items}{$source_id};
        my $rh_source_info = $source_info{$source_id};

        my $I = Image::Magick->new(); 
        $self->_verbose("Placing " . $rh_source_info->{pathname});

        # read input image again
        my $err = $I->Read($rh_source_info->{pathname});
        if ($err) {
            warn $err;
            next ITEM_ID;
        }

        # place soure image in the target image
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
    my $n = $Target->Write(filename => "$self->{target_file}");
    $self->_verbose("Wrote $n");

    return;
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
            $rh_items_info->{$b}{height}
                <=>
            $rh_items_info->{$a}{height}
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

        if ($rh_block->{fit}) {
            
            # convert to more clean output - i.e., take from the packed boxes
            # the only two information that we're interested in and augment our
            # layout
            $rh_layout->{items}{$block_id} = {
                x => $rh_block->{fit}{x},
                y => $rh_block->{fit}{y},
            };
            
            # compute the overall width/height
            $max_w = $rh_block->{fit}{w} if $max_w < $rh_block->{fit}{w};
            $max_h = $rh_block->{fit}{h} if $max_h < $rh_block->{fit}{h};
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

=head2 _identify_image

Return an hashref of information about the image at the given pathname.

=cut

sub _identify_image {
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
    $rh_info->{format} = $Image->Get('format');
    $rh_info->{comment} = $Image->Get('comment');
    $rh_info->{colors}{total} = $Image->Get('colors');

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
