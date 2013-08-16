use strict;
use warnings;

use Test::More;

my $layout_to_test = 'FixedDimension';

use_ok('CSS::SpriteMaker');

my $SpriteMaker = CSS::SpriteMaker->new();

my $rh_source_info = $SpriteMaker->_ensure_sources_info(
    source_images => ['sample_icons/']
);

my $Layout = $SpriteMaker->_ensure_layout(
    layout => {
        name => 'FixedDimension',
        options => {
            'n' => 3
        }
    },
    rh_sources_info => $rh_source_info
);

isa_ok($Layout, 'CSS::SpriteMaker::Layout::FixedDimension', 'obtained the layout class');

# build expected result
my $rh_expected = {
  'id32:32:0' => 1,
  'id5:0:602' => 1,
  'id29:0:410' => 1,
  'id30:0:96' => 1,
  'id40:0:160' => 1,
  'id18:64:64' => 1,
  'id3:32:442' => 1,
  'id16:22:96' => 1,
  'id38:32:506' => 1,
  'id19:64:570' => 1,
  'id31:60:192' => 1,
  'id13:128:282' => 1,
  'id46:64:256' => 1,
  'id28:64:128' => 1,
  'id7:0:32' => 1,
  'id41:0:474' => 1,
  'id43:32:570' => 1,
  'id26:22:32' => 1,
  'id11:33:224' => 1,
  'id2:0:64' => 1,
  'id45:64:538' => 1,
  'id42:0:256' => 1,
  'id47:60:474' => 1,
  'id23:160:282' => 1,
  'id20:32:160' => 1,
  'id21:64:0' => 1,
  'id33:0:0' => 1,
  'id36:0:442' => 1,
  'id4:0:538' => 1,
  'id12:28:474' => 1,
  'id1:32:64' => 1,
  'id27:0:128' => 1,
  'id0:0:282' => 1,
  'id9:54:442' => 1,
  'id34:32:538' => 1,
  'id10:32:192' => 1,
  'id48:65:224' => 1,
  'id17:54:32' => 1,
  'id8:64:506' => 1,
  'id15:0:506' => 1,
  'id14:56:160' => 1,
  'id37:0:570' => 1,
  'id39:64:410' => 1,
  'id25:32:128' => 1,
  'id22:32:256' => 1,
  'id44:54:96' => 1,
  'id24:0:192' => 1,
  'id6:32:410' => 1,
  'id35:0:224' => 1
};

# re-format expected result
my $rh_obtained = {};
for my $id (keys %$rh_source_info) {
    $rh_obtained->{sprintf("id%s:%s:%s", $id, $Layout->get_item_coord($id)) } = 1;
}

is_deeply($rh_obtained, $rh_expected, "FixedDimension layout behaves as expected");

done_testing();
