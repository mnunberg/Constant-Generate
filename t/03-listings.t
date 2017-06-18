#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use Constant::Generate [qw(
    FOO BAR BAZ
)], -allvalues => 'MYVALS', -allsyms => 'MYSYMS';

is_deeply [ MYVALS ] => [ 0, 1, 2 ],        'allvalues';
is_deeply [ MYSYMS ] => [qw/ FOO BAR BAZ/], 'allsyms';

done_testing();
