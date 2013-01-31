#!/usr/bin/perl
# Test various kinds of parameter expansion

use warnings;
use strict;

use lib 'lib';
use Apache::Solr;

use Test::More tests => 4;

# the server will not be called in this script.
my $server = 'http://localhost:8080/solr';
my $core   = 'my-core';

my $solr = Apache::Solr->new(server => $server, core => $core);
ok(defined $solr, 'instantiated client');
isa_ok($solr, 'Apache::Solr');

### Expansion of facets tested in t/12facet.t

### expandTerms

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

###### expandExtract

my @t2 = $solr->expandExtract(a => 1, extractOnly => 1
  , 'literal.id' => 5, literal => { b => 'tic' }, literals => { c => 'tac' }
  , literal_xyz => 42
  , fmap => { id => 'doc_id' }, fmap_subject => 'mysubject'
  , boost => { abc => 3.5 }, boost_xyz => 2.0
);
is(join("\n",@t2,''), <<_EXPECT, 'test extract expansion');
a
1
extractOnly
true
literal.id
5
literal.b
tic
literal.c
tac
literal.xyz
42
fmap.id
doc_id
fmap.subject
mysubject
boost.abc
3.5
boost.xyz
2
_EXPECT
