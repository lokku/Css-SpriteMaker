use strict;
use warnings;

use Test::More;

use_ok('CSS::SpriteMaker');

{
    my $SpriteMaker = CSS::SpriteMaker->new();

    ok($SpriteMaker, "Got a Css::SpriteMaker object back");

    # we need to run make or make_sprite otherwise we can't get the coordinate
    # of each item!
    $SpriteMaker->make_sprite(
        source_images => ['sample_icons/bubble.png'],
        target_file => 'sample_sprite.png',
    ) || unlink 'sample_sprite.png';

    my $rh_structure = $SpriteMaker->get_css_info_structure();
    is_deeply($rh_structure, [{
        'css_class' => 'bubble',
        'width' => 32,
        'y' => 0,
        'x' => 0,
        'full_path' => 'sample_icons/bubble.png',
        'height' => 28
    }], 'have obtained the desided css information structure');
}

done_testing();
