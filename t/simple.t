use strict;
use warnings;
use Test::More;

use Mac::AUHAL;

my $au = Mac::AUHAL->new;
isa_ok $au, 'Mac::AUHAL';

$au->set_format(
    sample_rate => 44144,
    channels    => 1,
    bits        => 0,
);

done_testing;
