package CSS::SpriteMaker;

use strict;
use warnings;

use feature qw(say);

use File::Find;
use Image::Magick;

use Module::Pluggable 
    search_path => ['CSS::SpriteMaker::Layout'],
    except => qr/CSS::SpriteMaker::Layout::Utils::.*/,
    require => 1,
    inner => 0;

use POSIX qw(ceil);


=head1 NAME

CSS::SpriteMaker - Combine several images into a single CSS sprite

=head1 VERSION

Version 0.04

=cut

our $VERSION = '0.04';


=head1 SYNOPSIS

    use CSS::SpriteMaker;

    my $SpriteMaker = CSS::SpriteMaker->new(
        verbose => 1, # optional
        rc_filename_to_classname => sub { my $filename = shift; ... } # optional
    );

    $SpriteMaker->make_sprite(
        source_images  => ['/path/to/imagedir', '/images/img1.png', '/img2.png'];
        target_file => '/tmp/test/mysprite.png',
        layout_name => 'Packed',    # optional
        remove_source_padding => 1, # optional
        format => 'png8',           # optional
    );

    $SpriteMaker->print_css();

    $SpriteMaker->print_html();

OR

    my $SpriteMaker = CSS::SpriteMaker->new();

    $SpriteMaker->make_sprite(
       source_dir => '/tmp/test/images',
       target_file => '/tmp/test/mysprite.png',
    );

    $SpriteMaker->print_css();

    $SpriteMaker->print_html();

=head1 DESCRIPTION

A CSS Sprite is an image obtained by arranging many smaller images on a 2D
canvas, according to a certain layout.

Transferring one larger image is generally faster than transferring multiple
images separately as it greatly reduces the number of HTTP requests (and
overhead) necessary to render the original images on the browser.

=head1 PUBLIC METHODS

=head2 new

Create and configure a new CSS::SpriteMaker object.

The object can be initialised as follows:
    
    my $SpriteMaker = CSS::SpriteMaker->new({
        rc_filename_to_classname => sub { my $filename = shift; ... }, # optional
        source_dir => '/tmp/test/images',       # optional
        target_file => '/tmp/test/mysprite.png' # optional
        remove_source_padding => 1, # optional
        verbose => 1,               # optional
    });
    
Default values are set to:

=over 4

=item remove_source_padding : false,

=item verbose : false,

=item format  : png

=back

The parameter rc_filename_to_classname is a code reference to a function that allow to customize the way class names are generated. This function should take one parameter as input and return a class name


    

=cut
sub new {
    my $class  = shift;
    my %opts   = @_;

    # defaults
    $opts{remove_source_padding} //= 0;
    $opts{verbose}               //= 0;
    $opts{format}                //= 'png';
    $opts{layout_name}           //= 'Packed';
    
    my $self = {
        source_images => $opts{source_images},
        source_dir => $opts{source_dir},
        target_file => $opts{target_file},
        is_verbose => $opts{verbose},
        format => $opts{format},
        remove_source_padding => $opts{remove_source_padding},
        output_css_file => $opts{output_css_file},
        output_html_file => $opts{output_html_file},

        # layout_name is used as default
        layout => {
            name => $opts{layout_name},
            # no options by default
            options => {}
        },
        rc_filename_to_classname => $opts{rc_filename_to_classname},

        # the maximum color value
        color_max => 2 ** Image::Magick->QuantumDepth - 1,
    };

    return bless $self, $class;
}

=head2 make_sprite

Creates the sprite file out of the specifed image files or directories, and
according to the given layout name.

my $is_error = $SpriteMaker->make_sprite(
    source_images => ['some/file.png', path/to/some_directory],
    target_file => 'sample_sprite.png',
    layout_name => 'Packed',

    # all imagemagick supported formats
    format => 'png8', # optional, default is png
);

returns true if an error occurred during the procedure.

Available layouts are:

=over 4

=item * Packed: try to pack together the images as much as possible to reduce the
  image size.

=item * DirectoryBased: put images under the same directory on the same horizontal
  row. Order alphabetically within each row.

=item * FixedDimension: arrange a maximum of B<n> images on the same row (or
  column).

=back

=cut

sub make_sprite {
    my $self    = shift;
    my %options = @_;

    my $rh_sources_info = $self->_ensure_sources_info(%options);
    my $Layout          = $self->_ensure_layout(%options, 
        rh_sources_info => $rh_sources_info
    );

    my $target_file     = $options{target_file} // $self->{target_file};
    my $output_format   = $options{format} // $self->{format};

    if (!$target_file) {
        die "the ``target_file'' parameter is required for this subroutine or you must instantiate Css::SpriteMaker with the target_file parameter";
    }

    $self->_verbose(" * writing sprite image");

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
    my $err = $Target->Write("$output_format:".$target_file);
    if ($err) {
        warn "unable to obtain $target_file for writing it as $output_format. Perhaps you have specified an invalid format. Check http://www.imagemagick.org/script/formats.php for a list of supported formats. Error: $err";

        $self->_verbose("Wrote $target_file");

        return 1;
    }

    # cache the layout and the rh_info structure so that it hasn't to be passed
    # as a parameter next times.
    $self->{_cache_layout} = $Layout;

    # cache the target image file, as making the stylesheet can't be done
    # without this information.
    $self->{_cache_target_image_file} = $target_file;

    return 0;
}

=head2 print_css

Creates and prints the css stylesheet for the sprite that was previously
produced.

    $SpriteMaker->print_css(
       filehandle => $fh, 
    );

OR

    $SpriteMaker->print_css(
       filename => 'relative/path/to/style.css',
    );

NOTE: make_sprite() must be called before this method is called.

=cut

sub print_css {
    my $self            = shift;
    my %options         = @_;
    
    my $rh_sources_info = $self->_ensure_sources_info(%options);
    my $Layout          = $self->_ensure_layout(%options,
        rh_sources_info => $rh_sources_info    
    );

    my $fh = $self->_ensure_filehandle_write(%options);

    $self->_verbose("  * writing css file");

    my $stylesheet = $self->_get_stylesheet_string();

    print $fh $stylesheet;
    close $fh;

    return 0;
}

=head2 print_html

Creates and prints an html sample page containing informations about each sprite produced.

    $SpriteMaker->print_html(
       filehandle => $fh, 
    );

OR

    $SpriteMaker->print_html(
       filename => 'relative/path/to/index.html',
    );

NOTE: make_sprite() must be called before this method is called.

=cut
sub print_html {
    my $self    = shift;
    my %options = @_;
    
    my $rh_sources_info = $self->_ensure_sources_info(%options);
    my $Layout          = $self->_ensure_layout(%options,
        rh_sources_info => $rh_sources_info
    );
    my $fh              = $self->_ensure_filehandle_write(%options);
    
    $self->_verbose("  * writing html sample page");

    my $stylesheet = $self->_get_stylesheet_string($Layout, $rh_sources_info);

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

=head2 get_css_info_structure

Returns an arrayref of hashrefs like:

    [
        {
            full_path => 'relative/path/to/file.png',
            css_class => 'file',
            width     => 16,  # pixels
            height    => 16,
            x         => 173, # offset within the layout
            y         => 234,
        },
        ...more
    ]

This structure can be used to build your own html or css stylesheet for
example.

NOTE: the x y offsets within the layout, will be always positive numbers.

=cut

sub get_css_info_structure {
    my $self            = shift;
    my %options         = @_;

    my $rh_sources_info = $self->_ensure_sources_info(%options);
    my $Layout          = $self->_ensure_layout(%options,
        rh_sources_info => $rh_sources_info
    );

    my $rh_id_to_class  = $self->_generate_css_class_names($rh_sources_info);

    my @css_info;

    for my $id (keys %$rh_sources_info) {
        my $rh_source_info = $rh_sources_info->{$id};
        my $css_class = $rh_id_to_class->{$id};

        my ($x, $y) = $Layout->get_item_coord($id);

        push @css_info, {
            full_path => $rh_source_info->{pathname},
            x => $x,
            y => $y,
            css_class => $css_class,
            width => $rh_source_info->{width},
            height => $rh_source_info->{height},
        };
    }

    return \@css_info;
}

=head1 PRIVATE METHODS

=head2 _generate_css_class_names

Returns a mapping id -> class_name out of the current information structure.

It guarantees unique class_name for each id.

=cut

sub _generate_css_class_names {
    my $self = shift;
    my $rh_source_info = shift;;

    my %existing_classnames_lookup;
    my %id_to_class_mapping;

    for my $id (keys %$rh_source_info) {

        my $css_class = $self->_generate_css_class_name(
            $rh_source_info->{$id}{name}
        );
        
        # keep modifying the css_class name until it doesn't exist in the hash
        my $i = 0;
        while (exists $existing_classnames_lookup{$css_class}) {
            # ... we want to add an incremental suffix like "-2"
            if (!$i) {
                # the first time, we want to add the prefix only, but leave the class name intact
                if ($css_class =~ m/-\Z/) {
                    # class already ends with a dash
                    $css_class .= '1';
                }
                else {
                    $css_class .= '-1';
                }
            }
            elsif ($css_class =~ m/-(\d+)\Z/) { # that's our dash added before!
                my $current_number = $1;
                $current_number++;
                $css_class =~ s/-\d+\Z/-$current_number/;
            }
            $i++;
        }

        $existing_classnames_lookup{$css_class} = 1;
        $id_to_class_mapping{$id} = $css_class;
    }

    return \%id_to_class_mapping;
}


=head2 _image_locations_to_source_info

Identify informations from the location of each input image, and assign
numerical ids to each input image.

=cut

sub _image_locations_to_source_info {
    my $self         = shift;
    my $ra_locations = shift;

    my %source_info;
    
    # collect properties of each input image
    IMAGE:
    my $id = 0;
    for my $rh_location (@$ra_locations) {

        my %properties = %{$self->_get_image_properties(
            $rh_location->{pathname}
        )};

        # skip invalid images
        next IMAGE if !%properties;

        for my $key (keys %$rh_location) {
            $source_info{$id}{$key} = $rh_location->{$key};
        }
        for my $key (keys %properties) {
            $source_info{$id}{$key} = $properties{$key};
        }

        $id++;
    }

    return \%source_info;
}

=head2 _locate_image_files

Finds the location of image files within the given directory. Returns an
arrayref of hashrefs containing information about the names and pathnames of
each image file.

The returned arrayref looks like:

[   # pathnames of the first image to follow
    {
        name => 'image.png',
        pathname => '/complete/path/to/image.png',
        parentdir => '/complete/path/to',
    },
    ...
]

Dies if the given directory is empty or doesn't exist.

=cut

sub _locate_image_files {
    my $self             = shift;
    my $source_directory = shift;

    if (!defined $source_directory) {
        die "you have called _locate_image_files but \$source_directory was undefined";
    }

    $self->_verbose(" * gathering files and directories of source images");

    my @locations;
    find(sub {
        my $filename = $_;
        my $fullpath = $File::Find::name;
        my $parentdir = $File::Find::dir;
    
        return if $filename eq '.';

        if (-f $filename) {
            push @locations, {
                # only the name of the file 
                name     => $filename,

                # the full relative pathname
                pathname => $fullpath,

                # the full relative path to the parent directory
                parentdir => $parentdir
            };
        }

    }, $source_directory);

    return \@locations;
}

=head2 _get_stylesheet_string

Returns the stylesheet in a string.

=cut

sub _get_stylesheet_string {
    my $self = shift;
    my $target_image_filename = shift // $self->{_cache_target_image_file};

    my $rah_cssinfo = $self->get_css_info_structure(); 

    my @classes = map { "." . $_->{css_class} } @$rah_cssinfo;

    my @stylesheet;

    # write header
    # header associates the sprite image to each class
    push @stylesheet, sprintf(
        "%s { background-image: url('%s'); background-repeat: no-repeat; }",
        join(",", @classes),
        $target_image_filename
    );

    for my $rh_info (@$rah_cssinfo) {
        push @stylesheet, sprintf(
            ".%s { background-position: %spx %spx; width: %spx; height: %spx; }",
            $rh_info->{css_class}, 
            -1 * $rh_info->{x},
            -1 * $rh_info->{y},
            $rh_info->{width},
            $rh_info->{height},
        );
    }

    return join "\n", @stylesheet;
}


=head2 _generate_css_class_name

This method generates the name of the CSS class for a certain image file. Takes
the image filename as input and produces a css class name (excluding the
prepended ".").

=cut

sub _generate_css_class_name {
    my $self     = shift;
    my $filename = shift;

    my $rc_filename_to_classname = $self->{rc_filename_to_classname};

    if (defined $rc_filename_to_classname) {
        my $classname = $rc_filename_to_classname->($filename);
        if (!$classname) {
            warn "custom sub to generate class names out of file names returned empty class for file name $filename";
        }
        if ($classname =~ m/^[.]/) {
            warn sprintf('your custom sub should not include \'.\' at the beginning of the class name. (%s was generated from %s)',
                $classname,
                $filename
            );
        }
        return $classname;
    }

    # prepare (lowercase)
    my $css_class = lc($filename);

    # remove image extensions if any
    $css_class =~ s/[.](tif|tiff|gif|jpeg|jpg|jif|jfif|jp2|jpx|j2k|j2c|fpx|pcd|png|pdf)\Z//;

    # remove @ []
    $css_class =~ s/[@\]\[]//g;

    # turn certain characters into dashes
    $css_class =~ s/[\s_.]/-/g;

    # remove dashes if they appear at the end
    $css_class =~ s/-\Z//g;

    # remove initial dashes if any
    $css_class =~ s/\A-+//g;

    return $css_class;
}


=head2 _ensure_filehandle_write

Inspects the input %options hash and returns a filehandle according to the
parameters passed in there.

The filehandle is where something (css stylesheet for example) is going to be
printed.

=cut

sub _ensure_filehandle_write {
    my $self = shift;
    my %options = @_;

    return $options{filehandle} if defined $options{filehandle};

    if (defined $options{filename}) {
        open my ($fh), '>', $options{filename};
        return $fh;
    }

    return \*STDOUT;
}

=head2 _ensure_sources_info

Makes sure the user of this module has provided a valid input parameter for
sources_info and return the sources_info structure accordingly. Dies in case
something goes wrong with the user input.

Parameters that allow us to obtain a $rh_sources_info structure are: 

- source_images: an arrayref of files or directories, directories will be
  visited recursively and any image file in it becomes the input.

If none of the above parameters have been found in input options, the cache is
checked before giving up - i.e., the user has previously provided the layout
parameter, and was able to generate a sprite. 

=cut

sub _ensure_sources_info {
    my $self = shift;
    my %options = @_;

    my $rh_source_info;

    return $options{source_info} if exists $options{source_info};

    my @source_images;

    if (exists $options{source_dir} && defined $options{source_dir}) {
        push @source_images, $options{source_dir};
    }

    if (exists $options{source_images} && defined $options{source_images}) {
        die 'source_images parameter must be an ARRAY REF' if ref $options{source_images} ne 'ARRAY';
        push @source_images, @{$options{source_images}};
    }

    if (@source_images) {
        # locate each file within each directory and then identify all...
        my @locations;
        for my $file_or_dir (@source_images) {
            my $ra_locations = $self->_locate_image_files($file_or_dir);
            push @locations, @$ra_locations;
        }

        $rh_source_info = $self->_image_locations_to_source_info(
            \@locations
        );
    }
    
    if (!$rh_source_info) {
        if (exists $self->{_cache_rh_source_info}
            && defined $self->{_cache_rh_source_info}) {

            $rh_source_info = $self->{_cache_rh_source_info};
        }
        else {
            die "Unable to create the source_info_structure!";
        }
    }
    else {
        # cache sources info
        $self->{_cache_rh_source_info} = $rh_source_info;
    }

    return $rh_source_info;
}



=head2 _ensure_layout

Makes sure the user of this module has provided valid layout options and
returns a $Layout object accordingly. Dies in case something goes wrong with
the user input. A Layout actually runs over the specified items on instantiation.

Parameters in %options (see code) that allow us to obtain a $Layout object are:

- layout: a CSS::SpriteMaker::Layout object already;
- layout: can also be a hashref like 
    {
        name => 'LayoutName',
        options => {
            'Layout-Specific option' => 'value',
            ...
        }
    }
- layout_name: the name of a CSS::SpriteMaker::Layout object.

If none of the above parameters have been found in input options, the cache is
checked before giving up - i.e., the user has previously provided the layout
parameter... 

=cut 

sub _ensure_layout {
    my $self = shift;
    my %options = @_;

    die 'rh_sources_info parameter is required' if !exists $options{rh_sources_info};

    # Try to understand what layout is asked
    my $Layout;
    if (exists $options{layout} && ref $options{layout} ne 'HASH') {
        if (exists $options{layout}{_layout_ran}) {
            $Layout = $options{layout};
        }
        else {
            warn 'a Layout object was specified but strangely was not executed on the specified items. NOTE: if a layout is instantiated it\'s always ran over the items!';
        }
    }

    if (defined $Layout) {
        if (exists $options{layout_name} && defined $options{layout_name}) {
            warn 'the parameter layout_name was ignored as the layout parameter was specified. These two parameters are mutually exclusive.';
        }
    }
    else {
        #
        # Load layout from plugins, and layout items
        #
        $self->_verbose(" * creating layout");

        # default source of layout name
        my $layout_name = $options{layout_name} // $self->{layout}{name};
        my $rh_layout_options = $self->{layout}{options};

        # override this if an hashref was passed among the options
        # the user has passed something like:
        # { ... 'layout' => { 'name' => 'SomeLayout' , 'options' => { ... } } }
        if (exists $options{layout} && ref $options{layout} eq 'HASH') {
            my $rh_specified_layout = $options{layout};
            if (exists $rh_specified_layout->{name} 
                && defined $rh_specified_layout->{name}) {

                $layout_name = $rh_specified_layout->{name};

                if (exists $options{layout}{options}) {
                    $rh_layout_options = $options{layout}{options};
                }
            }
            else {
                warn 'ignoring the specified layout options. If you want to specify a layout through a hashref, you need to provide it in the following format { name => "some layout name", options => { ... } }';
            }
        }

        LOAD_LAYOUT_PLUGIN:
        for my $plugin ($self->plugins()) {
            my ($plugin_name) = reverse split "::", $plugin;
            if ($plugin eq $layout_name || $plugin_name eq $layout_name) {
                $self->_verbose(" * using layout $plugin");
                $Layout = $plugin->new($options{rh_sources_info}, $rh_layout_options);
                last LOAD_LAYOUT_PLUGIN;
            }
        }

        if (!defined $Layout) {
            die sprintf(
                "The layout you've specified (%s) couldn't be found. Valid layouts are:\n%s",
                $layout_name,
                join "\n", $self->plugins()
            );
        }
    }

    if (!defined $Layout) {
        # try checking in the cache before giving up...
        if (exists $self->{_cache_layout} 
            && defined $self->{_cache_layout}) {
 
            $Layout = $self->{_cache_layout};
        }
        else {
            die "Unable to find a layout, did you forget to pass the ``layout'' or ``layout_name'' parameter?";
        }
    }

    return $Layout;
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

Copyright 2013 Savio Dimatteo.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of CSS::SpriteMaker
