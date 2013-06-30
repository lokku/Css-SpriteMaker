use strict;
use warnings;

use Test::More;
  
use_ok('CSS::SpriteMaker');

{
    my $SpriteMaker = CSS::SpriteMaker->new();

    isa_ok($SpriteMaker, 'CSS::SpriteMaker', 'created CSS::SpriteMaker instance');

    my $err = $SpriteMaker->make_sprite(
        source_dir => 'sample_icons',
        target_file => 'sample_sprite.png',
    );
    is ($err, 0, 'sprite was successfully created');

    my $out_css;
    open my($fh), '>', \$out_css
        or die 'Cannot open file for writing $!';

    $SpriteMaker->print_css(filehandle => $fh);
    close $fh;

    like ($out_css, qr/'sample_sprite[.]png'/, 'found sample sprite url');

}

done_testing();
