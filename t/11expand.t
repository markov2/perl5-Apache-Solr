#!/usr/bin/perl
# Test various kinds of parameter expansion

use warnings;
use strict;

use lib 'lib';
use Apache::Solr;

use Test::More tests => 3;

# the server will not be called in this script.
my $server = 'http://localhost:8080/solr';
my $core   = 'my-core';

my $solr = Apache::Solr->new(server => $server, core => $core);
ok(defined $solr, 'instantiated client');
isa_ok($solr, 'Apache::Solr');

### Expansion of facets tested in t/12facet.t

### Terms

my @t = $solr->expandTerms(fl => 'subject', limit => 100
  , mincount => 5, 'terms.maxcount' => 10, raw => 1, raw => 0
  , lower_incl => 1, terms_upper_incl => 0
  , prefix => 'at', regex => 'a.*b');

is(join("\n",@t,''), <<_EXPECT, 'test term expansion');
terms.fl
subject
terms.limit
100
terms.mincount
5
terms.maxcount
10
terms.raw
true
terms.raw
false
terms.lower.incl
true
terms.upper.incl
false
terms.prefix
at
terms.regex
a.*b
_EXPECT
