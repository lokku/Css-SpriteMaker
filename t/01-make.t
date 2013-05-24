use strict;
use warnings;

use Test::More;

use_ok('CSS::SpriteMaker');

my $SpriteMaker = CSS::SpriteMaker->new(
    source_dir => 'sample_icons',
    target_file => 'sample_sprite.png',
);
ok($SpriteMaker, 'created CSS::SpriteMaker instance');

$SpriteMaker->make();

done_testing();
