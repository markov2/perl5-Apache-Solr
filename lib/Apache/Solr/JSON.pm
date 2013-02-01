package Apache::Solr::JSON;
use base 'Apache::Solr';

use warnings;
use strict;

use Log::Report          qw(solr);

use Apache::Solr::Result ();
use HTTP::Request        ();
use JSON                 ();
use Scalar::Util         qw(blessed);

=chapter NAME
Apache::Solr::JSON - Apache Solr (Lucene) client via JSON

=chapter SYNOPSIS

  my $solr = Apache::Solr::JSON->new(...);
  my $solr = Apache::Solr->new(format => 'JSON', ...);

=chapter DESCRIPTION
Implement the Solr client, where the communication is in JSON.

Both the requests and the responses are using JSON syntax, produced by
the M<JSON> distribution (which defaults to M<JSON::XS> when installed)

B<Warning 1:>
Apparently, Perl's JSON implementation does not support the repetition
of keys in one list, but Solr is using that.  Care is taken to avoid
these cases.

B<Warning 2:>
In some cases, XML and JSON differ in structure and names in the structure.
In those cases, the XML plan is made leading: the JSON data is transformed
to match the XML.

=chapter METHODS
=section Constructors

=c_method new OPTIONS
=default format 'JSON'

=option  json M<JSON> object
=default json <created internally>
By default, an JSON object is created for you, in utf8 mode.
=cut

sub init($)
{   my ($self, $args) = @_;
    $args->{format}   ||= 'JSON';
    $self->SUPER::init($args);

    $self->{ASJ_json} = $args->{json} || JSON->new->utf8;
    $self;
}

#---------------
=section Accessors
=method json
=cut

sub json() {shift->{ASJ_json}}

#--------------------------
=section Commands
See F<http://wiki.apache.org/solr/UpdateJSON>
=cut

sub _select($)
{   my ($self, $params) = @_;

    # select may be called more than once, but do not add wt each time
    # again.
    my @params   = @$params;
    my %params   = @params;
    unshift @params, wt => 'json';

    my $endpoint = $self->endpoint('select', params => \@params);
    my $result   = Apache::Solr::Result->new(params => \@params
      , endpoint => $endpoint, core => $self);
    $self->request($endpoint, $result);

    if(my $dec = $result->decoded)
    {   # JSON uses different names!
        my $r = $dec->{result} = delete $dec->{response};
        $r->{doc} = delete $r->{docs};
    }
    $result;
}

sub _extract($$$)
{   my ($self, $params, $data, $ct) = @_;
    my @params   = (wt => 'json', @$params);
    my $endpoint = $self->endpoint('update/extract', params => \@params);
    my $result   = Apache::Solr::Result->new(params => \@params
      , endpoint => $endpoint, core => $self);
    $self->request($endpoint, $result, $data, $ct);
    $result;
}

sub _add($$$)
{   my ($self, $docs, $attrs, $params) = @_;
    $attrs   ||= {};
    $params  ||= {};

    my $sv = $self->serverVersion;
    $sv ge '3.1' or error __x"solr version too old for updates in JSON syntax";

    my @params   = (wt => 'json', %$params);
    my $endpoint = $self->endpoint
      ( ($sv lt '4.0' ? 'update/json' : 'update')
      , params => \@params
      );
    my $result   = Apache::Solr::Result->new(params => \@params
      , endpoint => $endpoint, core => $self);

    # We cannot create HASHes with twice the same key in Perl, so cannot
    # produce the syntax for adding multiple documents.  Try to save it.
    delete $attrs->{boost}
        if $attrs->{boost} && $attrs->{boost}==1.0;

    exists $attrs->{$_} && ($params->{$_} = delete $attrs->{$_})
        for qw/commit commitWithin overwrite boost/;

    my $add;
    if(@$docs==1)
    {   $add = {add => {%$attrs, doc => $self->_doc2json($docs->[0])}} }
    elsif(keys %$attrs)
    {   # in combination with attributes only
        error __x"unable to add more than one doc with JSON interface";
    }
    else
    {   $add = [ map $self->_doc2json($_), @$docs ] }

    $self->request($endpoint, $result, $add);
    $result;
}

sub _doc2json($)
{   my ($self, $this) = @_;
    my %doc;
    foreach my $fieldname ($this->fieldNames)
    {   my @f;
        foreach my $field ($this->fields($fieldname))
        {   # put boosted fields in a HASH
            push @f, $field->{boost} && $field->{boost}!=1.0
                   ? +{boost => $field->{boost}, value => $field->{content}}
                   : $field->{content};
        }
        # we have to combine multi-fields into ARRAYS
        $doc{$fieldname} = @f > 1 ? \@f : $f[0];
    }

    \%doc;
}

sub _commit($)   { my ($s, $attr) = @_; $s->simpleUpdate(commit   => $attr) }
sub _optimize($) { my ($s, $attr) = @_; $s->simpleUpdate(optimize => $attr) }
sub _delete($$)  { my $self = shift; $self->simpleUpdate(delete   => @_) }
sub _rollback()  { shift->simpleUpdate('rollback') }

sub _terms($)
{   my ($self, $terms) = @_;

    my @params   = (wt => 'json', @$terms);
    my $endpoint = $self->endpoint('terms', params => \@params);
    my $result   = Apache::Solr::Result->new(params => \@params
      , endpoint => $endpoint, core => $self);

    $self->request($endpoint, $result);

    my $table = $result->decoded->{terms} || {};
    $table    = {@$table} if ref $table eq 'ARRAY';  # bug in Solr 1.4

    while(my ($field, $terms) = each %$table)
    {   # repack array-of-pairs into array-of-arrays-of-pair
        my @pairs = @$terms;
        my @terms; 
        push @terms, [shift @pairs, shift @pairs] while @pairs;
        $result->terms($field => \@terms);
    }

    $result;
}

#--------------------------
=section Helpers
=cut

sub request($$;$$)
{   my ($self, $url, $result, $body, $body_ct) = @_;

    if(ref $body && ref $body ne 'SCALAR')
    {   $body_ct ||= 'application/json; charset=utf-8';
        $body      = \$self->json->encode($body);
    }

    my $resp = $self->SUPER::request($url, $result, $body, $body_ct);
    my $ct   = $resp->content_type;

    # At least Solr 4.0 response ct=text/plain while producing JSON
    # my $ct = $resp->content_type;
    # $ct =~ m/json/i
    #     or error __x"answer from solr server is not json but {type}"
    #          , type => $ct;

    my $dec = $self->json->decode($resp->decoded_content || $resp->content);

#use Data::Dumper;
#warn Dumper $dec;
    $result->decoded($dec);
    $result;
}

=method simpleUpdate  COMMAND, ATTRIBUTES, [CONTENT]
=cut

sub simpleUpdate($$;$)
{   my ($self, $command, $attrs, $content) = @_;

    my $sv       = $self->serverVersion;
    $sv ge '3.1' or error __x"solr version too old for updates in JSON syntax";

    $attrs     ||= {};
    my @params   = (wt => 'json', commit => delete $attrs->{commit});
    my $endpoint = $self->endpoint
      ( ($sv lt '4.0' ? 'update/json' : 'update')
      , params => \@params
      );
    my $result   = Apache::Solr::Result->new(params => \@params
      , endpoint => $endpoint, core => $self);

    my %params   = (%$attrs
      , (!$content ? () : ref $content eq 'HASH' ? %$content : @$content));
    my $doc      = $self->simpleDocument($command, \%params);
    $self->request($endpoint, $result, $doc);
    $result;
}

=method simpleDocument COMMAND, [ATTRIBUTES, [CONTENT]]
Construct a simple XML structure.
=cut

sub simpleDocument($;$$)
{   my ($self, $command, $attrs, $content) = @_;
    $attrs   ||= {};
    $content ||= {};
    +{ $command => { %$attrs, %$content } }
}

1;
