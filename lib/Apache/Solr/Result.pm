# This code is part of distribution Apache-Solr.  Meta-POD processed with
# OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package Apache::Solr::Result;

use warnings;
no warnings 'recursion';  # linked list of pages can get deep

use strict;

use Log::Report    qw(solr);
use Time::HiRes    qw(time);
use Scalar::Util   qw(weaken);

use Apache::Solr::Document ();

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Quotekeys = 0;

=chapter NAME
Apache::Solr::Result - Apache Solr (Lucene) result container

=chapter SYNOPSIS

  # All operations return a ::Result object
  my $result = $solr->select(...);

  $result or die $result->solrError; # error reported by Solr
  $result or die $result->errors;    # any error caught by this object

  # Lots of trace information included
  $result->showTimings;

  # ::Document containing the requested fields from a select() search
  my $doc1   = $result->selected(0);

  # ::Document containing the highlight info from a selected document
  my $hl1    = $result->highlighted($doc1);

  # Some operations have helper methods
  my $result = $solr->queryTerm(...);
  print Dumper $result->terms;

=chapter DESCRIPTION

=chapter OVERLOADING
=overload stringification 
=cut

use overload
    '""' => 'endpoint'
  , bool => 'success';

#----------------------
=chapter METHODS
=section Constructors

=c_method new %options

=option  request M<HTTP::Request> object
=default request C<undef>

=option  response M<HTTP::Response> object
=default response C<undef>

=requires params   ARRAY
=requires endpoint URI

=option  core M<Apache::Solr> object
=default core C<undef>

=option  sequential BOOLEAN
=default sequential C<false>
[1.06] By setting this, you indicate that you will process the documents
in (numeric) sequential order; that you have no intention to go back to
a lower number.  This implies that those cached results can be cleaned-up
in the client early, reducing memory consumption.

However: you are allowed to go back to lower numbers, with the penalty
of a repeat of a message exchange between this client and the database.

=cut

sub new(@) { my $c = shift; (bless {}, $c)->init({@_}) }
sub init($)
{   my ($self, $args) = @_;
    my $p = $self->{ASR_params} = $args->{params} or panic;
    $self->{ASR_endpoint} = $args->{endpoint}     or panic;

    my %params            = @$p;

    $self->{ASR_start}    = time;
    $self->request($args->{request});
    $self->response($args->{response});

    $self->{ASR_pages}    = [ $self ];   # first has non-weak page-table
    weaken $self->{ASR_pages}[0];        # no reference loop!

    if($self->{ASR_core} = $args->{core}) { weaken $self->{ASR_core} }
    $self->{ASR_next}    = $params{start} || 0;
	$self->{ASR_seq}     = $args->{sequential} || 0;
    $self->{ASR_fpz}     = $args->{_fpz};

    $self;
}

# replace the pageset with a shared set.
sub _pageset($)
{   $_[0]->{ASR_pages} = $_[1];
    weaken $_[0]->{ASR_pages};           # otherwise memory leak
}

#---------------
=section Accessors

=method start 
The timestamp of the moment the call has started, including the creation of
the message to be sent.

=method params 
List of (expanded) parameters used to call the solr server.

=method endpoint 
=method request [$request]
=method response [$response]
=method decoded [HASH]
=method endpoint 
The URI where the request is sent to.
=method elapse 
Number of seconds used to receive a decoded answer.
=method core 
[0.95] May return the M<Apache::Solr> object which created this result.
=method sequential
[1.06] Shows whether the results are only read in numeric order.
=cut

sub start()    {shift->{ASR_start}}
sub endpoint() {shift->{ASR_endpoint}}
sub params()   {@{shift->{ASR_params}}}
sub core()     {shift->{ASR_core}}
sub sequential() {shift->{ASR_seq}}

sub request(;$) 
{   my $self = shift;
    @_ && $_[0] or return $self->{ASR_request};
    $self->{ASR_req_out} = time;
    $self->{ASR_request} = shift;
}

sub response(;$) 
{   my $self = shift;
    @_ && $_[0] or return $self->{ASR_response};
    $self->{ASR_resp_in}  = time;
    $self->{ASR_response} = shift;
}

sub decoded(;$) 
{   my $self = shift;
    @_ or return $self->{ASR_decoded};
    $self->{ASR_dec_done} = time;
    $self->{ASR_decoded}  = shift;
}

sub elapse()
{   my $self = shift;
    my $done = $self->{ASR_dec_done} or return;
    $done = $self->{ASR_start};
}

=method success 
Returns true if the command has successfully completed.  
=examples
   my $result = $sorl->commit;
   $result->success or die;
   $result or die;          # same, via overloading
   $solr->commit or die;    # same, also overloading
=cut

sub success() { my $s = shift; $s->{ASR_success} ||= $s->solrStatus==0 }

=method solrStatus 
=method solrQTime 
Elapse (as reported by the server) to handle the request.  In seconds!
=method solrError 
=method serverError 
=method httpError 
=cut

sub solrStatus()
{   my $dec  = shift->decoded or return 500;
    $dec->{responseHeader}{status};
}

sub solrQTime()
{   my $dec   = shift->decoded or return;
    my $qtime = $dec->{responseHeader}{QTime};
    defined $qtime ? $qtime/1000 : undef;
}

sub solrError()
{   my $dec  = shift->decoded or return;
    my $err  = $dec->{error} || {};
    my $msg  = $err->{msg}   || '';
    $msg =~ s/\s*$//s;
    length $msg ? $msg : ();
}

sub httpError()
{   my $resp = shift->response or return;
    $resp->status_line;
}

sub serverError()
{   my $resp = shift->response or return;
    $resp->code != 200 or return;
    my $ct   = $resp->content_type;
    $ct eq 'text/html' or return;
    my $body = $resp->decoded_content || $resp->content;
    $body =~ s!.*<body>!!;
    $body =~ s!</body>.*!!;
    $body =~ s!</h[0-6]>|</p>!\n!g;  # cheap reformatter
    $body =~ s!</b>\s*!: !g;
    $body =~ s!<[^>]*>!!gs;
    $body;
}

=method errors 
All errors collected by this object into one string.
=cut

sub errors()
{   my $self = shift;
    my @errors;
    if(my $h = $self->httpError)   { push @errors, "HTTP error:",   "   $h" }
    if(my $a = $self->serverError) 
    {   $a =~ s/^/   /gm;
        push @errors, "Server error:", $a;
    }
    if(my $s = $self->solrError)   { push @errors, "Solr error:",   "   $s" }
    join "\n", @errors, '';
}

#--------------------------
=section Response information

=subsection in response to a select()

=method nrSelected 
Returns the number of selected documents, as result of a
M<Apache::Solr::select()> call.  Probably many of those documents are
not loaded (yet).

=examples
  print $result->nrSelected, " results\n";

  for(my $docnr = 0; $docnr < $result->nrSelected; $docnr++)
  {   my $doc = $result->selected($docnr);
      ...
  }
  # easier:
  while(my $doc = $result->nextSelected) ...
=cut

sub _responseData()
{   my $dec  = shift->decoded;
    $dec->{result} // $dec->{response};
}

sub nrSelected()
{   my $results = shift->_responseData
        or panic "there are no results (yet)";

    $results->{numFound};
}

=method selected $rank, %options
Returns information about the query by M<Apache::Solr::select()> on
position $rank (count starts at 0!)  Returned is an M<Apache::Solr::Document>
object.

The first request will take a certain number of "rows".  This routine
will automatically collect more of the selected answers, when you address
results outside the first "page" of "rows".  The results of these other
requests are cached as well.

This method has no C<%options> at the moment.

=example
   my $r = $solr->select(rows => 10, ...);
   $r or die $r->errors;

   if(my $last = $r->selected(9)) {...}
   my $doc = $r->selected(11);         # auto-request more
=cut

sub _docs($)
{   my ($self, $data) = @_;
    my $docs = $data->{doc} // $data->{docs} // [];

    # Decoding XML without schema may give unexpect results
    $docs    = [ $docs ] if ref $docs eq 'HASH'; # when only one result
    $docs;
}

sub selected($%)
{   my ($self, $rank, %options) = @_;
    my $data   = $self->_responseData
        or panic __x"there are no results in the answer";

	# start for next
    $self->{ASR_next} = $rank +1;

    # in this page?
    my $startnr  = $data->{start};
    if($rank >= $startnr)
    {   my $docs = $self->_docs($data);
        if($rank - $startnr < @$docs)
        {   my $doc = $docs->[$rank - $startnr];
            return Apache::Solr::Document->fromResult($doc, $rank);
        }
    }

    $rank < $data->{numFound}       # outside answer range
        or return ();
 
    my $pagenr  = $self->selectedPageNr($rank);
    my $page    = $self->selectedPage($pagenr)
               || $self->selectedPageLoad($pagenr, $self->core);

    $page->selected($rank);
}

=method nextSelected %options
[0.95] Produces the next document, or C<undef> when there are none
left.  [1.06] Use M<selected()> or M<new(start)> to give a starting
point.  [1.06]  The C<%options> are passed to M<selected()>.

=example
  my $result = $solr->select(q => ...);
  while(my $doc = $result->nextSelected)
  {   my $hl = $result->highlighted($doc);
  }
=cut

sub nextSelected(%)
{   my $self = shift;
    $self->selected($self->{ASR_next}, @_);
}

=method highlighted $document
Return information which relates to the selected $document.
=cut

sub highlighted($)
{   my ($self, $doc) = @_;
    my $rank   = $doc->rank;
    my $pagenr = $self->selectedPageNr($rank);
    my $hl     = $self->selectedPage($pagenr)->decoded->{highlighting}
        or error __x"there is no highlighting information in the result";
    Apache::Solr::Document->fromResult($hl->{$doc->uniqueId}, $rank);
}

#--------------------------
=subsection in response to a queryTerms()

=method terms $field, [$terms]
Returns the results of a 'terms' query (see M<Apache::Solr::queryTerms()>),
which is a HASH.  When $terms are specified, a new table is set.

In Solr XML (at least upto v4.0) the results are presented as lst, not arr
So: their sort order is lost.

=cut

sub terms($;$)
{   my ($self, $field) = (shift, shift);
    return $self->{ASR_terms}{$field} = shift if @_;

    my $r = $self->{ASR_terms}{$field}
        or error __x"no search for terms on field {field} requested"
            , field => $field;

    $r;
}

#--------------------------
=section Helpers

=method showTimings [$fh]
Print timing informat to the $fh, by default the selected
file-handle (probably STDOUT).
=cut

sub _to_msec($) { sprintf "%.1f", $_[0] * 1000 }

sub showTimings(;$)
{   my ($self, $fh) = @_;
    $fh ||= select;
    my $req     = $self->request;
    my $to      = $req ? $req->uri : '(not set yet)';
    my $start   = localtime $self->{ASR_start};

    $fh->print("endpoint: $to\nstart:    $start\n");

    if($req)
    {   my $reqsize = length($req->as_string);
        my $reqcons = _to_msec($self->{ASR_req_out} - $self->{ASR_start});
        $fh->print("request:  constructed $reqsize bytes in $reqcons ms\n");
    }

    if(my $resp = $self->response)
    {   my $respsize = length($resp->as_string);
        my $respcons = _to_msec($self->{ASR_resp_in} - $self->{ASR_req_out});
        $fh->print("response: received $respsize bytes after $respcons ms\n");
        my $ct       = $resp->content_type;
        my $status   = $resp->status_line;
        $fh->print("          $ct, $status\n");
    }

    if(my $dec = $self->decoded)
    {   my $decoder = _to_msec($self->{ASR_dec_done} - $self->{ASR_resp_in});
        $fh->print("decoding: completed in $decoder ms\n");
        if(defined(my $qt = $self->solrQTime))
        {   $fh->print("          solr processing took "._to_msec($qt)." ms\n");
        }
        if(my $error = $self->solrError)
        {   $fh->print("          solr reported error: '$error'\n");
        }
        my $total   = _to_msec($self->{ASR_dec_done} - $self->{ASR_start});
        $fh->print("elapse:   $total ms total\n");
    }
}

=method selectedPageNr $rank
=method selectedPages 
=method selectedPage $pagenr
=cut

sub selectedPageNr($) { my $pz = shift->fullPageSize; $pz ? int(shift() / $pz) : 0 }
sub selectPages()     { @{shift->{ASR_pages}} }
sub selectedPage($)   { my $pages = shift->{ASR_pages}; $pages->[shift()] }

=method selectedPageSize 
[1.07] DEPRECATED.  Use M<fullPageSize()>.
=cut

# The reloads page 0, which may have been purged by sequential reading.  Besided,
# the name does not cover its content: it's not the size of the select page but
# the first page.
sub selectedPageSize()
{   my $result = shift->selectedPage(0)->_responseData || {};
    my $docs   = $result->{doc} // $result->{docs};
    ref $docs eq 'HASH'  ? 1 : ref $docs eq 'ARRAY' ? scalar @$docs : 50;
}

=method fullPageSize
[1.07] Returns the page size of all of the full returned pages.  The last page
is probably smaller.
=cut

sub fullPageSize() { my $self = shift; $self->{ASR_fpz} ||= $self->_calc_page_size }

sub _calc_page_size()
{   my $self = shift;
    my $docs = $self->_docs($self->selectedPage(0)->_responseData);
#warn Dumper $self->selectedPage(0)->_responseData;
#warn "CALC PZ=", scalar @$docs;
    scalar @$docs;
}

=method selectedPageLoad $rank, $client
Query the database for the next page of results.
=cut

sub selectedPageLoad($;$)
{   my ($self, $pagenr, $client) = @_;
    $client
        or error __x"cannot autoload page {nr}, no client provided"
             , nr => $pagenr;

    my $fpz    = $self->fullPageSize;
    my @params = $self->replaceParams
      ( {start => $pagenr * $fpz, rows => $fpz}, $self->params);

    my $seq    = $self->sequential;
    my $page   = $client->select({sequential => $seq, _fpz => $fpz}, @params);
    my $pages  = $self->{ASR_pages};

    # put new page in shared table of pages
    $pages->[$pagenr] = $page;
    $page->_pageset($pages);

	# purge cached previous pages when in sequential mode
	if($seq && $pagenr != 0)
    {   $pages->[$_] = undef for 0..$pagenr-1;
    }

	$page;
}

=method replaceParams HASH, $oldparams
=cut

sub replaceParams($@)
{   my ($self, $new) = (shift, shift);
    my @out;
    while(@_)
    {    my ($k, $v) = (shift, shift);
         $v = delete $new->{$k} if $new->{$k};
         push @out, $k => $v;
    }
    (@out, %$new);
}

1;
