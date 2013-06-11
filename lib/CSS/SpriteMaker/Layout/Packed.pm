package CSS::SpriteMaker::Layout::Packed;

use strict;
use warnings;

use base 'CSS::SpriteMaker::Layout';

use CSS::SpriteMaker::Layout::Utils::BinPacking;

=head1 NAME

CSS::SpriteMaker::Layout::Packed - Layout items trying to minimize the size of the resulting file.

    my $DirectoryBasedLayout = CSS::SpriteMaker::Layout::Packed->new(
        {
            "1" => {
                width => 128,
                height => 128,
                pathname => '/full/path/to/file1.png',
                parentdir => '/full/path/to',
            },
            ...
        }
    );


All items will be packed throughcontained in the same sub directory are cascaded on the same row of 
the layout.

Input hashref items must contain the following keys
for this layout to produce a result:

- pathname : the full pathname of the file;

- width : the width in pixels of the image;

- height : the height in pixels of the image;

- parentdir: the full pathname of the parent directory the image is contained
  in.


=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head2 new

Instantiates the layout:

    my $DirectoryBasedLayout = CSS::SpriteMaker::Layout::DirectoryBased->new(
        $rh_item_info
    );

=cut

sub new {
    my $class = shift;
    my $rh_items_info = shift;

    my $self = bless {}, $class;

    if (!$rh_items_info) {
        die 'no items info hashref was passed in construction to this layout';
    }

    $self->_layout_items($rh_items_info);
    $self->finalize();

    return $self;
}

=head2 _layout_items

see POD of super class CSS::SpriteMaker::Layout::_layout_items for more
information.

=cut

sub _layout_items {
    my $self          = shift;
    my $rh_items_info = shift;

    # sort items by height
    my @items_sorted =
        sort {
            $rh_items_info->{$b}{height}
                <=>
            $rh_items_info->{$a}{height}
        }
        keys %$rh_items_info;
   
    # pack the items
    my $Packer = CSS::SpriteMaker::Layout::Utils::BinPacking->new();

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
            $self->set_item_coord($block_id, $rh_fit->{x}, $rh_fit->{y});
            
            # compute the overall width/height
            $max_w = $rh_fit->{w} + $rh_fit->{x} if $max_w < $rh_fit->{w} + $rh_fit->{x};
            $max_h = $rh_fit->{h} + $rh_fit->{y} if $max_h < $rh_fit->{h} + $rh_fit->{y};
        }
        else {
            warn "Wasn't able to fit block $block_id";
        }
    }

    # write dimensions in the resulting layout
    $self->{width} = $max_w;
    $self->{height} = $max_h;

    return;
}

1;
