package CSS::SpriteMaker::Layout::Utils::BinPacking;

use strict;
use warnings;

our $VERSION = 0.01

=head1 NAME

CSS::SpriteMaker::Layout::Utils::BinPacking - Attempt to optimally pack multiple boxes into a rectangular bin.

Basically, a Perl port of packer.growing.js (https://npmjs.org/package/binpacking)

=head1 VERSION

Version 0.01

=cut

=head1 SYNOPSIS

    use CSS::SpriteMaker::BinPacking;

    # initialize the packer
    my $Packer = CSS::SpriteMaker::BinPacking->new();

    # create some blocks
    my @blocks = (
        { w => 120 , h => 150 },
        { w => 64 , h => 64 },
        { w => 80 , h => 40 },
        { w => 100 , h => 200 },
        { w => 56 , h => 50 },
    );

    # fit the blocks into a rectangular bin
    $Packer->fit(\@blocks);

=cut

=head1 METHODS

=cut

=head2 new

=cut

sub new {
    my $class = shift;
    return bless {}, $class;
}

=head2 fit

=cut

sub fit {
    my $self      = shift;
    my $ra_blocks = shift;

    $self->{root} = {
        x => 0,
        y => 0,
        w => $ra_blocks->[0]{w},
        h => $ra_blocks->[0]{h},
    };

    for my $rh_block (@$ra_blocks) {
        if (my $node = $self->find_node($self->{root}, $rh_block->{w}, $rh_block->{h})) {
            $rh_block->{fit} = $self->split_node($node, $rh_block->{w}, $rh_block->{h});
        }
        else {
            $rh_block->{fit} = $self->grow_node($rh_block->{w}, $rh_block->{h});
        }

    }
}

=head2 find_node

=cut

sub find_node {
    my $self = shift;
    my ($root, $w, $h) = @_;

    if ($root->{used}) {
      return $self->find_node($root->{right}, $w, $h) 
        || $self->find_node($root->{down}, $w, $h);
    }
    elsif (($w <= $root->{w}) && ($h <= $root->{h})) {
      return $root;
    }
    else {
      return 0;
    }
}

=head2 split_node

=cut

sub split_node {
    my $self = shift;
    my ($node, $w, $h) = @_;

    $node->{used} = 1;
    $node->{down} = { 
        x => $node->{x},
        y => $node->{y} + $h,
        w => $node->{w},
        h => $node->{h} - $h 
    };

    $node->{right} = { 
        x => $node->{x} + $w, 
        y => $node->{y},
        w => $node->{w} - $w,
        h => $node->{h}
    };

    return $node;
}

=head2 grow_node

=cut

sub grow_node {
    my ($self, $w, $h) = @_;

    my $can_grow_down = ($w <= $self->{root}{w});
    my $can_grow_right = ($h <= $self->{root}{h});

    my $should_grow_right = $can_grow_right
        && ($self->{root}{h} >= ($self->{root}{w} + $w));

    my $should_grow_down = $can_grow_down
        && ($self->{root}{w} >= ($self->{root}{h} + $h));

    if ($should_grow_right) {
        return $self->grow_right($w, $h);
    }
    elsif ($should_grow_down) {
        return $self->grow_down($w, $h);
    }
    elsif ($can_grow_right) {
        return $self->grow_right($w, $h);
    }
    elsif ($can_grow_down) {
        return $self->grow_down($w, $h);
    }
    else {
        return 0;
    }
}

=head2 grow_right

=cut

sub grow_right {
    my ($self, $w, $h) = @_;
    $self->{root} = {
        used => 1,
        x => 0,
        y => 0,
        w => $self->{root}{w} + $w,
        h => $self->{root}{h},
        down => $self->{root},
        right => { 
            x => $self->{root}{w}, 
            y => 0, 
            w => $w, 
            h => $self->{root}{h}
        },
    };

    if (my $node = $self->find_node($self->{root}, $w, $h)) {
      return $self->split_node($node, $w, $h);
    }
    else {
      return 0;
    }
}

=head2 grow_down

=cut

sub grow_down {
    my ($self, $w, $h) = @_;

    $self->{root} = {
      used => 1,
      x => 0,
      y => 0,
      w => $self->{root}{w},
      h => $self->{root}{h} + $h,
      down => { 
        x => 0, 
        y => $self->{root}{h}, 
        w => $self->{root}{w}, 
        h => $h 
      },
      right => $self->{root},
    };

    if (my $node = $self->find_node($self->{root}, $w, $h)) {
        return $self->split_node($node, $w, $h);
    } 
    else {
        return 0;
    }
}

1;
