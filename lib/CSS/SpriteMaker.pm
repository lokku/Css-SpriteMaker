package CSS::SpriteMaker;

use strict;
use warnings;

use feature qw(say);

use File::Find;

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

    # go through each file in the source dir
    find(sub {
        say "found --> " . $File::Find::name;
    }, $self->source_dir);

    return;
}

=head1 LICENSE AND COPYRIGHT

Copyright 2012 Savio Dimatteo.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of File::CleanupTask
