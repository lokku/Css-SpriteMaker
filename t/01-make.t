use strict;
use warnings;

use Test::More;

use_ok('CSS::SpriteMaker');

my $SpriteMaker = CSS::SpriteMaker->new();
ok($SpriteMaker, 'created CSS::SpriteMaker instance');

done_testing();
