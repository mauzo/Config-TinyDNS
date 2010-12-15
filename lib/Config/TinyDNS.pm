package Config::TinyDNS;

use 5.010;
use warnings;
use strict;
use Scalar::Util qw/reftype/;

my %Filters;

sub process_config {
    my @lines = map { s/(.)//; [$1, split /:/] } split /\n/, shift;
    for my $f (@_) {
        my $c = ref $f ? $f : $Filters{$f};
        if (reftype $c eq "REF") {
            $c = ($$c)->();
        }
        @lines = map {
            my ($f, @r) = @$_;
            local $_ = $f;
            [ $c->(@r) ];
        } @lines;
    }
    return join "\n", map { $_->[0] . join ":", @$_[1..$#$_] } @lines;
}

sub register_filters {
    my %new = @_;
    %Filters = (%new, %Filters);
}

%Filters = (
    null => sub { $_, @_ },
    vars => \sub {
        my %vars;
        sub {
            s/\$(\w+)/$vars{$1}/ge for @_;
            /\$/ or return $_, @_;
            $vars{$_[0]} = $_[1]; 
            return;
        }
    },
);

1;
