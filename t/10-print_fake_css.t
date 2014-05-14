use strict;
use warnings;

use Test::More;
  
use_ok('CSS::SpriteMaker');

##
## source_dir
##
{
    my $SpriteMaker = CSS::SpriteMaker->new();

    my $out_only_css;
    open my($fh_css_only), '>', \$out_only_css
        or die 'Cannot open file for writing $!';

    $SpriteMaker->print_fake_css(
        filehandle => $fh_css_only,
        source_dir => 'sample_icons'
    );

    close $fh_css_only;

    _fail_on_unexpected_output($out_only_css, 'source_dir');
}

##
## source_images
##
{
    my $SpriteMaker = CSS::SpriteMaker->new();

    my $out_only_css;
    open my($fh_css_only), '>', \$out_only_css
        or die 'Cannot open file for writing $!';

    $SpriteMaker->print_fake_css(
        filehandle => $fh_css_only,
        source_images => ['sample_icons/apple.png', 'sample_icons/banknote.png']
    );

    close $fh_css_only;

    _fail_on_unexpected_output($out_only_css, 'source_images');
}

##
## source_images + include_in_css
##
{
    my $SpriteMaker = CSS::SpriteMaker->new();

    my $out_only_css;
    open my($fh_css_only), '>', \$out_only_css
        or die 'Cannot open file for writing $!';

    $SpriteMaker->print_fake_css(
        filehandle => $fh_css_only,
        source_images => ['sample_icons/apple.png', 'sample_icons/banknote.png'],
        include_in_css => 0
    );

    close $fh_css_only;

    is($out_only_css, undef, "No output given with include_css option turned off");
}

sub _fail_on_unexpected_output {
    my $out = shift;
    my $test = shift;
    my $fail = 0;
    my $class_count = 0;

    for my $css_line (split "\n", $out) {
        if ($css_line =~ m/^([.].+[}])/) {
            my $css_class_definition = $1;
            if ($css_class_definition !~ m/url[(]'.*'[)]/) {
                $fail = 1;
            }
        }
        $class_count++;
    }

    ok($class_count > 0, "Generated at least one class name for '$test' test (found $class_count classes)");

    if ($fail) {
        fail("Unexpected output was found for '$test' test");
        diag("... and output was $out");
    }
    else {
        pass("Expected output found for '$test' test");
    }

}

done_testing();
