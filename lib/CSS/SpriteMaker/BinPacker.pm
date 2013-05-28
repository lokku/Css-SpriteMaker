package CSS::SpriteMaker::BinPacker;

use strict;
use warnings;


=head DESCRIPTION

This is a very simple binary tree based bin packing algorithm that is initialized
with a fixed width and height and will fit each block into the first node where
it fits and then split that node into 2 parts (down and right) to track the
remaining whitespace.

Best results occur when the input blocks are sorted by height, or even better
when sorted by max(width,height).

Inputs:
------

  w:       width of target rectangle
  h:      height of target rectangle
  blocks: array of any objects that have .w and .h attributes

Outputs:
-------

  marks each block that fits with a .fit attribute pointing to a
  node with .x and .y coordinates

Example:
-------

  var blocks = [
    { w: 100, h: 100 },
    { w: 100, h: 100 },
    { w:  80, h:  80 },
    { w:  80, h:  80 },
    etc
    etc
  ];

  var packer = new Packer(500, 500);
  packer.fit(blocks);

  for(var n = 0 ; n < blocks.length ; n++) {
    var block = blocks[n];
    if (block.fit) {
      Draw(block.fit.x, block.fit.y, block.w, block.h);
    }
  }


=cut

sub new {
    my $class = shift;
    my %params = @_;

    my $self = bless {}, $class;

    $self->_init($params{w}, $params{h});

    return $self;
}

sub _init {
    my $self = shift;
    my ($w, $h) = @_; 

    $self->{root} = { 
        x => 0, 
        y => 0, 
        w => $w, 
        h => $h
    };
}

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
