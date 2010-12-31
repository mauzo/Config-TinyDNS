package t::Utils;

use warnings;
use strict;

use Test::More;
use Test::Warn;
use Config::TinyDNS;

use Exporter::NoWork;

our ($Filter, $Data, $Want);

# END blocks don't work with done_testing
require Test::NoWarnings;
{
    no warnings "redefine";
    sub done_testing {
        Test::NoWarnings::had_no_warnings();
        Test::More::done_testing(@_);
    }
}

sub IMPORT {
    shift;
    my $caller = caller 2;
    no strict "refs";
    for (qw/Filter Data Want/) {
        *{"$caller\::$_"} = \$$_;
    }
    return @_;
}

sub filt {
    my ($data, $want, $name) = @_;
    $#_ < 2 and ($want, $name) = ($data, $want);
    for ($Data, $Want, $data, $want) {
        ref and $_ = join "\n", @$_;
    }
    my $B = Test::More->builder;
    my $got = Config::TinyDNS::filter_tdns_data($Data . $data, $Filter);
    $B->is_eq($got, $Want . $want, $name);
}

1;

