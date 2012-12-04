package Apache::Solr::Document;

use warnings;
use strict;

use Log::Report    qw(solr);

=chapter NAME
Apache::Solr::Document - Apache Solr (Lucene) Document container

=chapter SYNOPSIS

  # create and upload a new document
  my $doc = Apache::Solr::Document->new(...);
  $solr->addDocument($doc, commit => 1, overwrite => 1)

  # take first result
  my $results = $solr->select
    ( q  => 'text:gold'             # search text-fields for 'gold'
    , hl => { field => 'content' }  # highlight 'gold' in content'
    );

  my $doc = $results->selected(3);  # fourth answer
  print $doc->rank;         # 3
  print $doc->field('subject')->{content};
  print $doc->content('subject');   # same
  print $doc->_subject;             # same, via autoload (mind the '_'!)

  my $hl  = $results->highlighted($doc);  # another ::Doc object
  print $hl->_content;              # highlighted content

=chapter DESCRIPTION
This object wraps-up an document: a set of fields.
Either, this is a document which has to be added to the Solr database
using M<Apache::Solr::addDocument()>,
or the subset of information as returned by M<Apache::Solr::select()>.

=chapter METHODS
=section Constructors

=c_method new OPTIONS

=option  fields HASH|ARRAY
=default fields {}
Passed to M<addFields()>.

=option  boost FLOAT
=default boost C<1.0>
Boost the preference for hits in this document.
=cut

sub new(@) { my $c = shift; (bless {}, $c)->init({@_}) }
sub init($)
{   my ($self, $args) = @_;

    $self->{ASD_boost}    = $args->{boost} // 1.0;

    $self->{ASD_fields}   = [];   # ordered
    $self->{ASD_fields_h} = {};   # grouped by name
    $self->addFields($args->{fields});
    $self;
}

=c_method fromResult HASH, RANK
Create a document object from data received as result of a select
search.
=cut

sub fromResult($$)
{   my ($class, $data, $rank) = @_;
    my (@f, %fh);
    
    while(my($k, $v) = each %$data)
    {   my @v = map +{name => $k, content => $_}
             , ref $v eq 'ARRAY' ? @$v : $v;
        push @f, @v;
        $fh{$k} = \@v;
    }

    my $self = $class->new;
    $self->{ASD_rank}     = $rank;
    $self->{ASD_fields}   = \@f;
    $self->{ASD_fields_h} = \%fh;
    $self;
}

#---------------
=section Accessors
=method boost
Boost value for all fields in the document.

=method fieldNames
All used unique names.
=cut

sub boost() {shift->{ASD_boost}}
sub fieldNames() { my %c; $c{$_->{name}}++ for shift->fields; sort keys %c }

=method uniqueId
Returns the value of the unique key associated with the document C<id>.  Only
the server knowns which field is the unique one.  If it differs from the
usual C<id>, you have to set it via global value C<$Apache::Solr::uniqueKey>
=cut

sub uniqueId() {
warn "#1 ", $Apache::Solr::uniqueKey, "<<";
shift->content($Apache::Solr::uniqueKey)}

=method rank
Only defined when the document contains results of a search: the ranking.
A value of '0' means "best".
=cut

sub rank() {shift->{ASD_rank}}

=method fields [NAME]
Returns a list of HASHs, each containing at least a C<name> and a
C<content>.  Each HASH will also contain a C<boost> value.  When a NAME
is provided, only those fields are returned.
=cut

sub fields(;$)
{   my $self = shift;
    my $f    = $self->{ASD_fields};
    @_ or return @$f;
    my $name = shift;
    my $fh   = $self->{ASD_fields_h}{$name};   # grouped by name
    $fh ? @$fh : ();
}

=method field NAME
Returns the first field with NAME (or undef).  This is a HASH.
=cut

sub field($)
{   my $fh = $_[0]->{ASD_fields_h}{$_[1]};
    $fh ? $fh->[0] : undef;
}

=method content NAME
Returns the content of the first field with NAME.
=cut

sub content($) { my $f = $_[0]->field($_[1]); $f ? $f->{content} : undef }

our $AUTOLOAD;
sub AUTOLOAD
{   (my $fn = $AUTOLOAD) =~ s/.*\:\:_//;
    shift->content($fn);
}

=method addField NAME, CONTENT, OPTIONS
CONTENT can be specified as SCALAR (reference) for performance. In
that case, a reference to the original will be kept.  When C<undef>,
the field gets ignored.

=option  boost FLOAT
=default boost C<1.0>
=cut

sub addField($$%)
{   my $self  = shift;
    my $name  = shift;
    my $field =     # important to minimalize copying of content
      { name    => $name
      , content => ( !ref $_[0]            ? shift
                   : ref $_[0] eq 'SCALAR' ? ${shift()}
                   :                         shift
                   )
      };
    my %args  = @_;
    $field->{boost} = $args{boost} || 1.0;

    push @{$self->{ASD_fields}}, $field;
    push @{$self->{ASD_fields_h}{$name}}, $field;
    $field;
}

=method addFields HASH|ARRAY, OPTIONS
The HASH or ARRAY containing NAME/CONTENT pairs.
The OPTIONS are passed M<addField()> as OPTIONS.
=cut

sub addFields($%)
{   my ($self, $h, @args) = @_;
    # pass content by ref to avoid a copy of potentially huge field.
    if(ref $h eq 'ARRAY')
    {   for(my $i=0; $i < @$h; $i+=2)
        {   $self->addField($h->[$i] => \$h->[$i+1], @args);
        }
    }
    else
    {   $self->addField($_ => \$h->{$_}, @args) for sort keys %$h;
    }
}

#--------------------------
=section Helpers
=cut

1;
