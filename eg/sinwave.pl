use strict;
use warnings;

use Cocoa::EventLoop;
use Mac::AUHAL;

my $M_PI = atan2(1, 1) * 4;

my $au = Mac::AUHAL->new;
$au->set_format(
    sample_rate => 8000.,
    channels    => 1,
    bits        => 32,
    float       => 1,
);

my $pos  = 0.;
my $freq = 440.;
$au->set_render_cb(sub {
    my ($frames, $data_ref) = @_;

    for (1 .. $frames) {
        $$data_ref .= pack 'f', sin($pos);
        $pos += (2. * $M_PI * $freq) / 8000.;
    }
});
$au->start;

Cocoa::EventLoop->run;
