package Config::TinyDNS;

use 5.010;
use warnings;
use strict;
use Scalar::Util    qw/reftype/;
use List::MoreUtils qw/natatime/;
use Carp;

use Exporter::NoWork;

our $VERSION = 1;

my %Filters;

sub split_tdns_data {
    map { 
        s/(.)// 
            ? [$1, ($1 eq "#" ? $_ : split /:/)] 
            : () 
    } split /\n/, $_[0];
}

sub join_tdns_data {
    no warnings "uninitialized";
    join "", map "$_\n", map { $_->[0] . join ":", @$_[1..$#$_] } @_;
}

sub _lookup_filt {
    my ($k, @args) = @_;
    my $f = $Filters{$k} or croak "bad filter: $k";
    given (reftype $f) {
        when ("CODE")   { return $f }
        when ("REF")    { return ($$f)->(@args) }
        default         { die "bad \%Filters entry: $k => $f" }
    }
}
    
sub _decode_filt {
    my ($f) = @_;
    defined $f or return;
    given (reftype $f) {
        when ("CODE")   { return $f }
        when (undef)    { return _lookup_filt $f }
        when ("ARRAY")  { return _lookup_filt @$f }
        default         { croak "bad filter: $f" }
    }
}

sub _call_filt {
    my $c = shift;
    my $r = @_ ? shift : $_;
    my ($f, @r) = @$r;
    local $_ = $f;
    $c->(@r);
}

sub filter_tdns_data {
    my @lines = split_tdns_data shift;
    for my $f (@_) {
        my $c = _decode_filt $f;
        @lines = 
            map _call_filt($c),
            @lines;
    }
    return join_tdns_data @lines;
}

sub register_tdns_filters {
    my $i = natatime 2, @_;
    while (my ($k, $c) = $i->()) {
        $Filters{$k}    and croak "filter '$k' is already registered";
        ref $c and (
            reftype $c eq "CODE" or (
                reftype $c eq "REF" and reftype $$c eq "CODE"
            )
        )               or  croak "filter must be a coderef(ref)";
        $Filters{$k} = $c;
    }
}

# just for the tests
sub _filter_hash { \%Filters }

register_tdns_filters
    null => sub { [$_, @_] },
    vars => \sub {
        my %vars = ('$' => '$');
        sub {
            no warnings "uninitialized";
            s/\$(\$|\w+)/$vars{$1}/ge for @_;
            /\$/            or return [$_, @_];
            $_[0] eq '$'    and return;
            $vars{$_[0]} = $_[1]; 
            return;
        }
    },
    include => \sub {
        my $include;
        $include = sub {
            /I/ or return [$_, @_];
            require File::Slurp;
            return map _call_filt($include),
                split_tdns_data scalar File::Slurp::read_file($_[0]);
        };
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
    site => \sub {
        my %sites = map +($_, 1), @_;
        sub {
            /%/             or return [$_, @_];
            @_ > 2          or return [$_, @_];
            my $site = pop;
            $sites{$site}   or return;
            return [$_, @_];
        };
    },
    ;

1;
