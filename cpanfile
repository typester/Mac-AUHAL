requires 'perl' => '5.010';
requires 'Cocoa::EventLoop';
requires 'Data::Validator';

on test => sub {
    requires 'Test::More' => 0.98;
};

on configure => sub {
    requires 'Module::Build' => 0.40;
    requires 'Module::CPANfile';
};

on 'develop' => sub {
};

