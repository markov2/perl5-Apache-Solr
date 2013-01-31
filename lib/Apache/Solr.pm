package Apache::Solr;

use warnings;
use strict;

use Apache::Solr::Tables;
use Log::Report    qw(solr);

use Scalar::Util   qw/blessed/;
use Encode         qw/encode/;
use Scalar::Util   qw/weaken/;

use URI            ();
use LWP::UserAgent ();
use MIME::Types    ();

use constant LATEST_SOLR_VERSION => '4.0';  # newest support by this module

# overrule this when your host has a different unique field
our $uniqueKey  = 'id';
my  $mimetypes  = MIME::Types->new;
my  $http_agent;

sub _to_bool($) {$_[0] && $_[0] ne 'false' && $_[0] ne 'off' ? 'true' : 'false'}

=chapter NAME
Apache::Solr - Apache Solr (Lucene) extension

=chapter SYNOPSIS

  my $solr    = Apache::Solr->new(server => $url);

  my $doc     = Apache::Solr::Document->new(...);
  my $results = $solr->addDocument($doc);
  $results or die $results->solrError;

  my $results = $solr->select(q => 'author:mark');
  my $doc     = $results->selected(3);
  print $doc->_author;

  # based on Log::Report, hence (for communication errors and such)
  use Log::Report;
  dispatcher SYSLOG => 'default';  # now all warnings/error to syslog
  try { $solr->select(...) }; print $@->wasFatal;

=chapter DESCRIPTION
Solr is a stand-alone full-text search-engine, with loads of features.
The main component is Lucene.  This module tries to provide a high
level interface to the Solr server.

B<BE WARNED>: this code is very new!  Please help me improve this code
by sending bugs and suggesting improvements.

=chapter METHODS

=section Constructors

=c_method new OPTIONS
Create a client to connect to one "core" (collection) of the Solr
server.

=requires server URL
The locations of the Solr server depends on the way the java environment
is set-up.   The URL is either an M<URI> object or a string which can be
instantiated as such.

=option  server_version VERSION
=default server_version <latest>
By default the latest version of the server software, currently 4.0.
Try to get this setting right, because it will help you a lot in correct
parameter use and support for the right features.

=option  core NAME
=default core C<undef>
Set the core name to be addressed by this client. When there is no core
name specified, the core is selected by the server or already part of
the URL.

You probably want to set-up a core dedicated for testing and one for
the live environment.

=option  agent M<LWP::UserAgent> object
=default agent <created internally>
Agent which implements the communication between this client and the
Solr server.

When you have multiple C<Apache::Solr> objects in your program, you may
want to share this agent, to share the connection. Since [0.94], this
will happen automagically: the parameter defaults to the agent created
for the previous object.

Do not forget to install M<LWP::Protocol::https> if you need to connect
via https.

=option  autocommit BOOLEAN
=default autocommit C<true>
Commit all changes immediately unless specified differently.

=option  format  'XML'|'JSON'
=default format  'XML'
Communication format between client and server.  You may also instantiate
M<Apache::Solr::XML> or M<Apache::Solr::JSON> directly.

=cut

sub new(@)
{   my ($class, %args) = @_;
    if($class eq __PACKAGE__)
    {   my $format = delete $args{format} || 'XML';
        $format eq 'XML' || $format eq 'JSON'
            or panic "unknown communication format '$format' for solr";
        $class .= '::' . $format;
        eval "require $class"; panic $@ if $@;
    }
    (bless {}, $class)->init(\%args)
}

sub init($)
{   my ($self, $args) = @_;
    $self->server($args->{server});
    $self->{AS_core}     = $args->{core};
    $self->{AS_commit}   = exists $args->{autocommit} ? $args->{autocommit} : 1;
    $self->{AS_sversion} = $args->{server_version} || LATEST_SOLR_VERSION;

    $http_agent = $self->{AS_agent} = $args->{agent} ||
       $http_agent || LWP::UserAgent->new(keep_alive=>1);
    weaken $http_agent;

    $self;
}

#---------------
=section Accessors

=method core [CORE]
Returns the CORE, when not defined the default core as set by M<new(core)>.
May return C<undef>.

=method autocommit [BOOLEAN]

=method agent
Returns the M<LWP::UserAgent> object which maintains the connection to
the server.

=method serverVersion
Returns the specified version of the Solr server software (by default the
latest).  Treat this version as string, to avoid rounding errors.
=cut

sub core(;$) { my $s = shift; @_ ? $s->{AS_core}   = shift : $s->{AS_core} }
sub autocommit(;$)
             { my $s = shift; @_ ? $s->{AS_commit} = shift : $s->{AS_commit} }
sub agent()  {shift->{AS_agent}}
sub serverVersion() {shift->{AS_sversion}}

=method server [URI|STRING]
Returns the M<URI> object which refers to the server base address.  You need
to clone() it before modifying.  You may set a new value as STRING or C<URI>
object.
=cut

sub server(;$)
{   my ($self, $uri) = @_;
    $uri or return $self->{AS_server};
    $uri = URI->new($uri)
         unless blessed $uri && $uri->isa('URI');
    $self->{AS_server} = $uri;
}

#--------------------------
=section Commands

=subsection Search

=method select PARAMETERS
Find information in the document collection.

This method has a HUGE number of parameters.  These values are passed in
the uri of the http query to the solr server.  See M<expandSelect()> for
all the simplifications offered here.  Sets of there parameters
may need configuration help in the server as well.

=cut

sub select(@)
{   my $self = shift;
    $self->_select(scalar $self->expandSelect(@_));
}
sub _select(@) {panic "not extended"}

=method queryTerms TERMS
Search for often used terms. See F<http://wiki.apache.org/solr/TermsComponent>

TERMS are passed to M<expandTerms()> before being used.

B<Be warned:> The result is not sorted when XML communication is used,
even when you explicitly request it.

=examples
  my $r = $self->queryTerms(fl => 'subject', limit => 100);
  if($r->success)
  {   foreach my $hit ($r->terms('subject'))
      {   my ($term, $count) = @$hit;
          print "term=$term, count=$count\n";
      }
  }

  if(my $r = $self->queryTerms(fl => 'subject', limit => 100))
     ...
=cut

sub queryTerms(@)
{   my $self  = shift;
    $self->_terms(scalar $self->expandTerms(@_));
}
sub _terms(@) {panic "not implemented"}

#-------------------------------------
=subsection Updates
See F<http://wiki.apache.org/solr/UpdateXmlMessages>.  Missing are the
atomic updates.

=method addDocument DOC|ARRAY, OPTIONS
Add one or more documents (M<Apache::Solr::Document> objects) to the Solr
database on the server.

=option  commit BOOLEAN
=default commit <autocommit>

=option  commitWithin SECONDS
=default commitWithin C<undef>
[Since Solr 3.4] Automatically translated into 'commit' for older
servers.  Currently, the resolution is milli-seconds.

=option  overwrite BOOLEAN
=default overwrite <true>

=option  allowDups BOOLEAN
=default allowDups <false>
[deprecated since Solr 1.1??]  Use option C<overwrite>.

=option  overwritePending BOOLEAN
=default overwritePending <not allowDups>
[deprecated since Solr 1.1??]

=option  overwriteCommitted BOOLEAN
=default overwriteCommitted <not allowDups>
[deprecated since Solr 1.1??]

=cut

sub addDocument($%)
{   my ($self, $docs, %args) = @_;
    $docs  = [ $docs ] if ref $docs ne 'ARRAY';

    my $sv = $self->serverVersion;

    my (%attrs, %params);
    $params{commit}
      = _to_bool(exists $args{commit} ? $args{commit} : $self->autocommit);

    if(my $cw = $args{commitWithin})
    {   if($sv lt '3.4') { $attrs{commit} = 'true' }
        else { $attrs{commitWithin} = int($cw * 1000) }
    }

    $attrs{overwrite} = _to_bool delete $args{overwrite}
        if exists $args{overwrite};

    foreach my $depr (qw/allowDups overwritePending overwriteCommitted/)
    {   if(exists $args{$depr})
        {   if($sv ge '1.0') { $self->deprecated("add($depr)") }
            else { $attrs{$depr} = _to_bool delete $args{$depr} }
        }
    }

    $self->_add($docs, \%attrs, \%params);
}

=method commit OPTIONS

=option  waitFlush BOOLEAN
=default waitFlush <true>
[before Solr 1.4]

=option  waitSearcher BOOLEAN
=default waitSearcher <true>

=option  softCommit BOOLEAN
=default softCommit <false>
[since Solr 4.0]

=option  expungeDeletes BOOLEAN
=default expungeDeletes <false>
[since Solr 1.4]
=cut

sub commit(%)
{   my ($self, %args) = @_;
    my $sv = $self->serverVersion;

    my %attrs;
    if(exists $args{waitFlush})
    {   if($sv ge '1.4') { $self->deprecated("commit(waitFlush)") }
        else { $attrs{waitFlush} = _to_bool delete $args{waitFlush} }
    }

    $attrs{waitSearcher} = _to_bool delete $args{waitSearcher}
        if exists $args{waitSearcher};

    if(exists $args{softCommit})
    {   if($sv lt '4.0') { $self->ignored("commit(softCommit)") }
        else { $attrs{softCommit} = _to_bool delete $args{softCommit} }
    }

    if(exists $args{expungeDeletes})
    {   if($sv lt '1.4') { $self->ignored("commit(expungeDeletes)") }
        else { $attrs{expungeDeletes} = _to_bool delete $args{expungeDeletes} }
    }

    $self->_commit(\%attrs);
}
sub _commit($) {panic "not implemented"}

=method optimize OPTIONS

=option  waitFlush BOOLEAN
=default waitFlush <true>
[before Solr 1.4]

=option  waitSearcher BOOLEAN
=default waitSearcher <true>

=option  softCommit BOOLEAN
=default softCommit <false>
[since Solr 4.0]

=option  maxSegments INTEGER
=default maxSegments 1
[since Solr 1.3]
=cut

sub optimize(%)
{   my ($self, %args) = @_;
    my $sv = $self->serverVersion;

    my %attrs;
    if(exists $args{waitFlush})
    {   if($sv ge '1.4') { $self->deprecated("optimize(waitFlush)") }
        else { $attrs{waitFlush} = _to_bool delete $args{waitFlush} }
    }

    $attrs{waitSearcher} = _to_bool delete $args{waitSearcher}
        if exists $args{waitSearcher};

    if(exists $args{softCommit})
    {   if($sv lt '4.0') { $self->ignored("optimize(softCommit)") }
        else { $attrs{softCommit} = _to_bool delete $args{softCommit} }
    }

    if(exists $args{maxSegments})
    {   if($sv lt '1.3') { $self->ignored("optimize(maxSegments)") }
        else { $attrs{maxSegments} = delete $args{maxSegments} }
    }

    $self->_optimize(\%attrs);
}
sub _optimize($) {panic "not implemented"}

=method delete OPTIONS
Remove one or more documents, based on id or query.

=option  commit BOOLEAN
=default commit <autocommit>
When specified, it indicates whether to commit (update the indexes) after
the last delete.  By default the value of M<new(autocommit)>.

=option  id ID|ARRAY-of-IDs
=default id C<undef>
The expected content of the uniqueKey fields (usually named C<id>) for
the documents to be removed.

=option  query QUERY|ARRAY-of-QUERYs
=default query C<undef>

=option  fromPending BOOLEAN
=default fromPending C<true>
[deprecated since ?]

=option  fromCommitted BOOLEAN
=default fromCommitted C<true>
[deprecated since ?]
=cut

sub delete(%)
{   my ($self, %args) = @_;

    my %attrs;
    $attrs{commit}
      = _to_bool(exists $args{commit} ? $args{commit} : $self->autocommit);

    if(exists $args{fromPending})
    {   $self->deprecated("delete(fromPending)");
        $attrs{fromPending}   = _to_bool delete $args{fromPending};
    }
    if(exists $args{fromCommitted})
    {   $self->deprecated("delete(fromCommitted)");
        $attrs{fromCommitted} = _to_bool delete $args{fromCommitted};
    }

    my @which;
    if(my $id = $args{id})
    {    push @which, map +(id => $_), ref $id eq 'ARRAY' ? @$id : $id;
    }
    if(my $q  = $args{query})
    {    push @which, map +(query => $_), ref $q  eq 'ARRAY' ? @$q  : $q;
    }
    @which or return;

    # JSON calls do not accept multiple ids at once (it seems in 4.0)
    my $result;
    if($self->serverVersion ge '1.4' && !$self->isa('Apache::Solr::JSON'))
    {   $result = $self->_delete(\%attrs, \@which);
    }
    else
    {   # old servers accept only one id or query per delete
        $result = $self->_delete(\%attrs, [splice @which, 0, 2]) while @which;
    }
    $result;
}
sub _delete(@) {panic "not implemented"}

=method rollback
[solr 1.4]
=cut

sub rollback()
{   my $self = shift;
    $self->serverVersion ge '1.4'
        or error __x"rollback not supported by solr server";

    $self->_rollback;
}

=method extractDocument OPTIONS
Call the Solr Tika built-in to have the server translate various
kinds of structured documents into Solr searchable documents.  This
component is also called "Solr Cell".

The OPTIONS are mostly passed on as attributes to the server call,
but there are a few more.  You need to pass either a C<file> or
C<string> with data.

See F<http://wiki.apache.org/solr/ExtractingRequestHandler>

=option  commit BOOLEAN
=default commit M<new(autocommit)>
[0.94] commit the document to the database.

=option  file FILENAME|FILEHANDLE
=default file C<undef>
Either C<file> or C<string> must be used.

=option  string STRING|SCALAR
=default string C<undef>
The document provided as normal text or a reference to raw text.  You may
also specify the C<file> option with a filename.

=option  content_type MIME
=default content_type <from> filename

=example
   my $r = $solr->extractDocument(file => 'design.pdf'
     , literal_id => 'host');
=cut

sub extractDocument(@)
{   my $self  = shift;

    $self->serverVersion ge '1.4'
        or error __x"extractDocument() requires Solr v1.4 or higher";
        
    my %p     = $self->expandExtract(@_);
    my $data;

    my $ct    = delete $p{content_type};
    my $fn    = delete $p{file};
    $p{'resource.name'} ||= $fn if $fn && !ref $fn;

    $p{commit}  = _to_bool $self->autocommit
        unless exists $p{commit};

    if(defined $p{string})
    {   # try to avoid copying the data, which can be huge
        $data = ref $p{string} eq 'SCALAR'
              ? encode(utf8 => ${$p{string}})
              : encode(utf8 => $p{string});
        delete $p{string};
    }
    elsif($fn)
    {   local $/;
        if(ref $fn eq 'GLOB') { $data = <$fn> }
        else
        {   local *IN;
            open IN, '<:raw', $fn
                or fault __x"cannot read document from {fn}", fn => $fn;
            $data = <IN>;
            close IN
                or fault __x"read error for document {fn}", fn => $fn;
            $ct ||= $mimetypes->mimeTypeOf($fn);
        }
    }
    else
    {   error __x"extract requires document as file or string";
    }

    $self->_extract([%p], \$data, $ct);
}
sub _extract($){panic "not implemented"}

#-------------------------
=subsection Core management
See F<http://lucidworks.lucidimagination.com/display/solr/Configuring+solr.xml>
The CREATE, SWAP, ALIAS, and RENAME actions are not yet supported, because
they are not very useful, it seems.
=cut

sub _core_admin($@)
{   my ($self, $action, $params) = @_;
    $params->{core} ||= $self->core;
    
    my $endpoint = $self->endpoint('cores', core => 'admin'
      , params => $params);

    my @params   = %$params;
    my $result   = Apache::Solr::Result->new(params => [ %$params ]
      , endpoint => $endpoint);

    $self->request($endpoint, $result);
    $result;
}

=method coreStatus
[0.94] Returns a HASH with information about this core.  There is no
description about the exact structure and interpretation of this data.

=option  core NAME
=default core <this core>

=example
  my $result = $solr->coreStatus;
  $result or die $result->errors;

  use Data::Dumper;
  print Dumper $result->decoded->{status};
=cut

sub coreStatus(%)
{   my ($self, %args) = @_;
    $self->_core_admin('STATUS', \%args);
}

=method coreReload [CORE]
[0.94] Load a new core (on the server) from the configuration of this
core. While the new core is initializing, the existing one will continue
to handle requests. When the new Solr core is ready, it takes over and
the old core is unloaded.

=option  core NAME
=default core <this core>

=example
  my $result = $solr->coreReload;
  $result or die $result->errors;
=cut

sub coreReload(%)
{   my ($self, %args) = @_;
    $self->_core_admin('RELOAD', \%args);
}

=method coreUnload [OPTIONS]
Removes a core from Solr. Active requests will continue to be processed, but no new requests will be sent to the named core. If a core is registered under more than one name, only the given name is removed.

=option  core NAME
=default core <this core>
=cut

sub coreUnload($%)
{   my ($self, %args) = @_;
    $self->_core_admin('UNLOAD', \%args);
}

#--------------------------
=section Helpers

=subsection Parameter pre-processing

Many parameters are passed to the server.  The syntax of the communication
protocol is not optimal for the end-user: it is too verbose and depends on
the Solr server version.

General rules:
=over 4
=item * you can group them on prefix
=item * use underscore as alternative to dots: less quoting needed
=item * boolean values in Perl will get translated into 'true' and 'false'
=item * when an ARRAY (or LIST), the order of the parameters get preserved
=back
=cut

sub _calling_sub()
{   for(my $i=0;$i <10; $i++)
    {   my $sub = (caller $i)[3];
        return $sub if !$sub || index($sub, 'Apache::Solr::') < 0;
    }
}

sub _simpleExpand($$$)
{   my ($self, $p, $prefix) = @_;
    my @p  = ref $p eq 'HASH' ? %$p : @$p;
    my $sv = $self->serverVersion;

    my @t;
    while(@p)
    {   my ($k, $v) = (shift @p, shift @p);
        $k =~ s/_/./g;
        $k = $prefix.$k if defined $prefix && index($k, $prefix)!=0;
        my $param   = $k =~ m/^f\.[^\.]+\.(.*)/ ? $1 : $k;

        my ($dv, $iv);
        if(($dv = $deprecated{$param}) && $sv ge $dv)
        {   my $command = _calling_sub;
            $self->deprecated("$command($param) since $dv");
        }
        elsif(($iv = $introduced{$param}) && $iv gt $sv)
        {   my $command = _calling_sub;
            $self->ignored("$command($param) introduced in $iv");
            next;
        }

        push @t, $k => $boolparams{$param} ? _to_bool($_) : $_
            for ref $v eq 'ARRAY' ? @$v : $v;
    }
    @t;
}

=method expandTerms PAIRS|ARRAY
Used by M<queryTerms()> only.
=examples
  my @t = $solr->expandTerms('terms.lower.incl' => 'true');
  my @t = $solr->expandTerms([lower_incl => 1]);   # same

  my $r = $self->queryTerms(fl => 'subject', limit => 100);
=cut

sub expandTerms(@)
{   my $self = shift;
    my $p    = @_==1 ? shift : [@_];
    my @t    = $self->_simpleExpand($p, 'terms.');
    wantarray ? @t : \@t;
}

=method expandExtract PAIRS|ARRAY
Used by M<extractDocument()>.

[0.93] If the key is C<literal> or C<literals>, then the keys in the
value HASH (or ARRAY of PAIRS) get 'literal.' prepended.  "Literals"
are fields you add yourself to the SolrCEL output.  Unless C<extractOnly>,
you need to specify the 'id' literal.

[0.94] You can also use C<fmap>, C<boost>, and C<resource> with an
HASH (or ARRAY-of-PAIRS).

=example
  my $result = $solr->extractDocument(string => $document
     , resource_name => $fn, extractOnly => 1
     , literals => { id => 5, b => 'tic' }, literal_xyz => 42
     , fmap => { id => 'doc_id' }, fmap_subject => 'mysubject'
     , boost => { abc => 3.5 }, boost_xyz => 2.0);
);

=cut

sub _expand_flatten($$)
{   my ($self, $v, $prefix) = @_;
    my @l = ref $v eq 'HASH' ? %$v : @$v;
    my @s;
    push @s, $prefix.(shift @l) => (shift @l) while @l;
    @s;
}

sub expandExtract(@)
{   my $self = shift;
    my @p = @_==1 ? @{(shift)} : @_;
    my @s;
    while(@p)
    {   my ($k, $v) = (shift @p, shift @p);
        if(!ref $v)
             { push @s, $k => $v }
        elsif($k eq 'literal' || $k eq 'literals')
             { push @s, $self->_expand_flatten($v, 'literal.') }
        elsif($k eq 'fmap' || $k eq 'boost' || $k eq 'resource')
             { push @s, $self->_expand_flatten($v, "$k.") }
        else { panic "unknown set '$k'" }
    }

    my @t = @s ? $self->_simpleExpand(\@s) : ();
    wantarray ? @t : \@t;
}

=method expandSelect PAIRS
The M<select()> method accepts many, many parameters.  These are passed
to modules in the server, which need configuration before being usable.

Besides the common parameters, like 'q' (query) and 'rows', there
are parameters for various (pluggable) backends, usually prefixed
by the backend abbreviation.
=over 4
=item * facet -> F<http://wiki.apache.org/solr/SimpleFacetParameters>
=item * hl (highlight) -> F<http://wiki.apache.org/solr/HighlightingParameters>
=item * mtl -> F<http://wiki.apache.org/solr/MoreLikeThis>
=item * stats -> F<http://wiki.apache.org/solr/StatsComponent>
=item * group -> F<http://wiki.apache.org/solr/FieldCollapsing>
=back

You may use M<WebService::Solr::Query> to construct the query ('q').

=examples
  my @r = $solr->expandSelect
    ( q => 'inStock:true', rows => 10
    , facet => {limit => -1, field => [qw/cat inStock/], mincount => 1}
    , f_cat_facet => {missing => 1}
    , hl    => {}
    , mlt   => { fl => 'manu,cat', mindf => 1, mintf => 1 }
    , stats => { field => [ 'price', 'popularity' ] }
    , group => { query => 'price:[0 TO 99.99]', limit => 3 }
     );

  # becomes (one line)
  ...?rows=10&q=inStock:true
    &facet=true&facet.limit=-1&facet.field=cat
       &f.cat.facet.missing=true&facet.mincount=1&facet.field=inStock
    &mlt=true&mlt.fl=manu,cat&mlt.mindf=1&mlt.mintf=1
    &stats=true&stats.field=price&stats.field=popularity
    &group=true&group.query=price:[0+TO+99.99]&group.limit=3

=cut

my %sets =   #also-per-field?  (probably more config later)
  ( facet => [1]
  , hl    => [1]
  , mlt   => [0]
  , stats => [0]
  , group => [0]
  );
 
sub expandSelect(@)
{   my $self = shift;
    my @s;
    my (@flat, %seen_set);
    while(@_)
    {   my ($k, $v) = (shift, shift);
        $k =~ s/_/./g;
        my @p = split /\./, $k;

        # fields are $set.$more or f.$field.$set.$more
        my $per_field    = $p[0] eq 'f' && @p > 2;
        my ($set, $more) = $per_field ? @p[2,3] : @p[0,1];

        if(my $def = $sets{$set})
        {   $seen_set{$set} = 1;
            $def->[0]
               or error __x"set {set} cannot be used per field, in {field}"
                    , set => $set, field => $k;
            if(ref $v eq 'HASH')
            {   !$more
                    or error __x"field {field} is not simple for a set", field => $k;
                push @s, $self->_simpleExpand($v, "$k.");
            }
            elsif($more)    # skip $set=true for now
            {   push @flat, $k => $v;
            }
        }
        elsif(ref $v eq 'HASH')
        {   error __x"unknown set {set}", set => $set;
        }
        else
        {   push @flat, $k => $v;
        }
    }
    push @flat, %seen_set;
    unshift @s, $self->_simpleExpand(\@flat);
    wantarray ? @s : \@s;
}

=method deprecated MESSAGE
Produce a warning MESSAGE about deprecated parameters with the
indicated server version.
=cut

sub deprecated($)
{   my ($self, $msg) = @_;
    return if $self->{AS_depr_msg}{$msg}++;  # report only once
    warning __x"deprecated solr {message}", message => $msg;
}

=method ignored MESSAGE
Produce a warning MESSAGE about parameters which will get ignored
because they were not yet supported by the indicated server version.
=cut

sub ignored($)
{   my ($self, $msg) = @_;
    return if $self->{AS_ign_msg}{$msg}++;  # report only once
    warning __x"ignored solr {message}", message => $msg;
}

#------------------------
=subsection Other helpers

=method endpoint ACTION, OPTIONS
Compute the address to be called (for HTTP)

=option  core NAME
=default core M<new(core)>
If no core is specified, the default of the server is addressed.

=option  params HASH|ARRAY-of-pairs
=default params []
The order of the parameters will be preserved when an ARRAY or parameters
is passed; you never know for a HASH.
=cut

sub endpoint($@)
{   my ($self, $action, %args) = @_;
    my $core = $args{core} || $self->core;
    my $take = $self->server->clone;
    $take->path ($take->path . (defined $core ? "/$core" : '') . "/$action");

    # make parameters ordered
    my $params = $args{params} || [];
    $params    = [ %$params ] if ref $params eq 'HASH';
    @$params or return $take;

    # remove paramers with undefined value
    my @p = @$params;
    my @params;
    while(@p)
    {   push @params, $p[0] => $p[1] if defined $p[1];
        shift @p, shift @p;
    }

    $take->query_form(@params) if @params;
    $take;
}
 
sub request($$;$$)
{   my ($self, $url, $result, $body, $body_ct) = @_;

    my $req;
    if(!$body)
    {   # request without payload
        $req = HTTP::Request->new(GET => $url);
    }
    else
    {   # request with 'form' payload
        $req       = HTTP::Request->new
          ( POST => $url
          , [ Content_Type        => $body_ct
            , Contend_Disposition => 'form-data; name="content"'
            ]
          , (ref $body eq 'SCALAR' ? $$body : $body)
          );
    }

#warn $req->as_string;
    $result->request($req);

    my $resp = $self->agent->request($req);
    $result->response($resp);
    $resp;
}

#----------------------------------
=chapter DETAILS

=section Comparison with other implementations

=subsection Compared to WebService::Solr

M<WebService::Solr> is a good module, with a lot of miles.  The main
differences is that C<Apache::Solr> has much more abstraction.

=over 4
=item * simplified parameter syntax, improving readibility
=item * real Perl-level boolean parameters, not 'true' and 'false'
=item * warnings for deprecated and ignored parameters
=item * smart result object with built-in trace and timing
=item * hidden paging of results
=item * flexible logging framework (Log::Report)
=item * both-way XML or both-way JSON, not requests in XML and answers in JSON
=item * access to plugings like terms and tika
=item * no Moose
=back

=cut

1;
