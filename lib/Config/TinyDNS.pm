package Config::TinyDNS;

use 5.010;
use warnings;
use strict;
use Scalar::Util qw/reftype/;
use Carp;

use Exporter::NoWork;

our $VERSION = 1;

my %Filters;

sub split_tdns_data {
    map { s/(.)//; [$1, split /:/] } split /\n/, $_[0];
}

sub join_tdns_data {
    no warnings "uninitialized";
    join "", map "$_\n", map { $_->[0] . join ":", @$_[1..$#$_] } @_;
}

sub _decode_filt;
sub _decode_filt {
    my ($f) = @_;
    given (reftype $f) {
        when ("CODE")   { return $f }
        when (undef)    { 
            return _decode_filt(
                $Filters{$f} or croak "no such filter: $f"
            );
        }
        when ("REF")    { return ($$f)->() }
        when ("ARRAY")  { 
            my $g = _decode_filt shift @$f;
            return $g->(@$f);
        }
        default         { die "bad filter: $f" }
    }
}

sub process_config {
    my @lines = split_tdns_data shift;
    for my $f (@_) {
        my $c = _decode_filt $f;
        @lines = 
            map {
                my ($f, @r) = @$_;
                local $_ = $f;
                $c->(@r);
            } 
            grep defined $_->[0],
            @lines;
    }
    return join_tdns_data @lines;
}

sub register_filters {
    my %new = @_;
    %Filters = (%new, %Filters);
}

%Filters = (
    null => sub { [$_, @_] },
    vars => \sub {
        my %vars;
        sub {
            s/\$(\w+)/$vars{$1}/ge for @_;
            /\$/ or return [$_, @_];
            $vars{$_[0]} = $_[1]; 
            return;
        }
    },
    include => sub {
        /I/ or return [$_, @_];
        require File::Slurp;
        return split_tdns_data scalar File::Slurp::read_file($_[0]);
    },
    lresolv => \sub {
        my %hosts;
        my $repl = sub {
            for ((defined $_[1] ? "$_[0]:$_[1]" : ()), $_[0]) {
                if (
                    $_[0] =~ /[^0-9.]/ and 
                    defined $hosts{$_}
                ) {
                   $_[0] = $hosts{$_};
                   last;
                }
            }
        };
        my $qual = sub { $_[0] =~ /\./ ? "$_[0].$_[1].$_[2]" : $_[0] };
        my $lo   = sub { $_[0] . (defined $_[1] ? ":$_[1]" : "") };
        sub { 
            given ($_) {
                when ([".", "&"]) { 
                    $repl->(@_[1, 5]);
                    $hosts{$lo->($qual->($_[2], "ns", $_[0]), $_[5])} = $_[1];
                }
                when (["=", "+"]) {
                    $repl->(@_[1, 4]);
                    $hosts{$lo->($_[0], $_[4])} = $_[1];
                }
                when (["@"]) {
                    $repl->(@_[1, 6]);
                    $hosts{$lo->($qual->($_[2], "mx", $_[0]), $_[6])} = $_[1];
                }
            }
            [$_, @_];
        };
    },
    rresolv => \sub {
        require Socket;
        my $repl = sub { 
            if ($_[0] =~ /[^0-9.]/) {
                $_[0] = Socket::inet_ntoa(
                    gethostbyname($_[0]) // 
                        Socket::inet_aton("0.0.0.0")
                );
            }
        };
        sub { /[.&+=\@]/ and $repl->($_[1]); [$_, @_]; };
    },
    site => sub {
        my %sites = map +($_, 1), @_;
        sub {
            /%/             or return [$_, @_];
            @_ > 2          or return [$_, @_];
            my $site = pop;
            $sites{$site}   or return;
            return [$_, @_];
        };
    },
);

1;
