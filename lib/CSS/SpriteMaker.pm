package CSS::SpriteMaker;

use strict;
use warnings;

use feature qw(say);

use File::Find;
use Image::Magick;

# use Cwd            qw/realpath getcwd chdir/;
# use File::Path     qw/mkpath rmtree/;
# use File::Basename qw/fileparse/;
# use File::Spec     qw/catpath splitpath/;
# use Config::Simple;
# use File::Which    qw/which/;
# use Getopt::Long;
# use File::Copy;
# use IPC::Run3      qw/run3/;
# use Sort::Key      qw/nkeysort/;


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
        target_file => '/tmp/test/mysprite.png'
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
    });

=cut
sub new {
    my $class  = shift;
    my %opts   = @_;
    
    my $self = {
        source_dir => $opts{source_dir},
        target_file => $opts{target_file}
    };

    return bless $self, $class;
}

=head2 make

=cut
sub make {
    my $self = shift;

    say "Target file: " . $self->{target_file};
    say "Checking " . $self->{source_dir};

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

    # collect info about individual images
    IMAGE:
    for my $id (keys %source_info) {
        my $Image = Image::Magick->new();

        my $err = $Image->Read($source_info{$id}{pathname});
        if ($err) {
            warn $err;
            next IMAGE;
        }

        $source_info{$id}{width} = $Image->Get('columns');
        $source_info{$id}{height} = $Image->Get('rows');
        $source_info{$id}{format} = $Image->Get('format');
        $source_info{$id}{colors} = $Image->Get('colors');
        $source_info{$id}{comment} = $Image->Get('comment');
        $source_total++;
    }

    # devise the best layout
    my $rh_layout = $self->layout_images(\%source_info);

    # make our image
    my $Target = Image::Magick->new();
    $Target->Set(size => sprintf("%sx%s",
        $rh_layout->{width},
        $rh_layout->{height}
    ));
    $Target->ReadImage('canvas:white');

    # place each image according to the layout
    ID:
    for my $id (keys %{$rh_layout->{items}}) {
        my $item = $rh_layout->{items}{$id};

        my $I = Image::Magick->new(); 
        say "Placing " . $source_info{$id}{pathname};
        my $err = $I->Read($source_info{$id}{pathname});

        if ($err) {
            warn $err;
            next ID;
        }

        my $destx = $item->{x};
        for my $x (0..$source_info{$id}{width}) {
            my $desty = $item->{y};
            for my $y (0..$source_info{$id}{height}) {
                my $p = $I->Get(
                    sprintf('pixel[%s,%s]', $destx, $desty),
                );
                my ($r, $g, $b, $a) = split /,/, $p;
                $r *= 255/65535;
                $g *= 255/65535;
                $b *= 255/65535;
                $a *= 255/65535;

                say "$x $y : $r $g $b $a";
                $Target->Set(
                    sprintf('pixel[%s,%s]', $destx, $desty),
                        => "rgba($r,$r,$r,1)"
                ); 
                $desty++;
            }
            $destx++;
        }
    }

    # write target image
    my $n = $Target->Write($self->{target_file});
    say "Wrote $n\n";

    return;
}

=head2 layout_images

=cut

sub layout_images {
    my $self = shift;
    my $rh_source_info = shift;

    my $rh_layout = {
        width => 0,
        height => 0,
        items => {},
    };
    my $x = 0;
    my $y = 0;
    my $maxheight = 0;
    for my $id (keys %$rh_source_info) {
        my $info = $rh_source_info->{$id};
        $rh_layout->{items}{$id} = { x => $x, y => $y };
        $x += $info->{width};

        $maxheight = $info->{height} if $maxheight < $info->{height};
    }
    $rh_layout->{width} = $x;
    $rh_layout->{height} = $maxheight;

    return $rh_layout;
}

=head1 LICENSE AND COPYRIGHT

Copyright 2012 Savio Dimatteo.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of CSS::SpriteMaker
