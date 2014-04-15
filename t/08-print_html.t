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
    is ($err, 0, 'sprite was successfully created') 
        && unlink 'sample_sprite.png';

    my $out_css;
    open my($fh), '>', \$out_css
        or die 'Cannot open file for writing $!';

    $SpriteMaker->print_html(filehandle => $fh);
    close $fh;

    is(length $out_css > 100, 1, 'more than 100 characters returned for html sample page');
}

done_testing();
