use strict;
use warnings;
use Test::More;

use Mac::AUHAL;

my $au = Mac::AUHAL->new;
isa_ok $au, 'Mac::AUHAL';

done_testing;
