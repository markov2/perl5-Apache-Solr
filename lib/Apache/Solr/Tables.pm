# This code is part of distribution Apache-Solr.  Meta-POD processed with
# OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package Apache::Solr::Tables;
use base 'Exporter';

our @EXPORT = qw/%boolparams %introduced %deprecated/;

# Boolean parameters update to Solr 9.8 syntax.
# %introduced and %deprecated tables probally incomplete.

our %boolparams = map +($_ => 1), qw/
allTermsRequired
boost
buildOnCommit
buildOnOptimize
buildOnStartup
canCancel
captureAttr
clustering
clustering.collection
clustering.includeOtherTopics
clustering.results
collectElevatedDocsWhenCollapsing
commit
debug
debug.explain.structured
docValues
echoHandler
elevateOnlyDocsMatchingQuery
enableElevation
exactMatchFirst
exclusive
expand
expand.nullGroup
exactMatchFirst
extractOnly
facet
facet.contains.ignoreCase
facet.date.hardend
facet.exists
facet.missing
facet.range.hardend
facet.zeros
forceElevation
group
group.facet
group.main
group.ngroups
group.truncate
hardend
highlight
hl
hl.defaultSummary
hl.fragsizeIsMinimum
hl.highlightAlternate
hl.highlightMultiTerm
hl.mergeContiguous
hl.payloads
hl.preserveMulti
hl.requireFieldMatch
hl.useFastVectorHighlighter
hl.usePhraseHighlighter
hl.weightMatches
ignoreStopwords
indent
literalsOverride
lowernames
markExcludes
matchText
mlt
mlt.boost
mlt.match.include
multiThreaded
omitHeader
overwrite
partialResults
preserveSep
preservePositionIncrements
segmentTerminateEarly
skipAltTokens
solr.alwaysOnTraceId
solr.disableRequestId
spellcheck
spellcheck.build
spellcheck.collate
spellcheck.collateExtendedResults
spellcheck.extendResults
spellcheck.onlyMorePopular
spellcheck.reload
stats
suggest
suggest.build
suggest.buildAll
suggest.reload
suggest.reloadAll
terms
terms.lower.incl
terms.raw
terms.stats
terms.ttf
terms.upper.incl
transpositions
tv
tv.all
tv.df
tv.offsets
tv.payloads
tv.positions
tv.tf
tv.tf_idf
unicodeAware
useConfiguredElevatedOrder
xmlOffsetAdjust
 /;

our %introduced = qw/
carrot.fragSize		3.1
carrot.lang		3.6
carrot.lexicalResourcesDir 3.2
carrot.produceSummary	3.6
carrot.resourcesDir	4.5
carrot.summarySnippets	3.6
debug			4.0
debug.explain.structured	3.2
exclusive		3.0
facet.date		1.3
facet.date.include	3.1
facet.enum.cache.minDf	1.2
facet.method		1.4
facet.mincount		1.2
facet.offset		1.2
facet.pivot		4.0
facet.prefix		1.2
facet.range		3.1
facet.range.end		3.1
facet.range.gap		3.6
facet.range.hardend	3.1
facet.range.include	3.1
facet.range.other	3.1
facet.range.start	3.1
facet.threads           4.5
hl.alternateField	1.3
hl.boundaryScanner	3.5
hl.bs.chars		3.5
hl.bs.country		3.5
hl.bs.language		3.5
hl.bs.type		3.5
hl.fragListBuilder	3.1
hl.fragmenter		1.3
hl.fragmentsBuilder	3.1
hl.highlightMultiTerm	1.4
hl.maxAlternateFieldLength	1.3
hl.maxAnalyzedChars	1.3
hl.maxMultiValuedToExamine	4.3
hl.maxMultiValuedToMatch	4.3
hl.mergeContiguous	1.3
hl.preserveMulti	4.1.0
hl.q			3.5
hl.useFastVectorHighlighter	3.1
hl.usePhraseHighlighter	1.3
literalsOverride	4.0
mlt.fl			1.3
pageDoc			4.0
pageScore		4.0
passwordsFile		4.0
qs			1.3
resourse.password	4.0
shards			3.1
shards.qt		3.1
spellcheck.accuracy	3.1
spellcheck.collate	3.1
spellcheck.maxCollations	3.1
spellcheck.maxCollationTries	3.1
spellcheck.maxResultsForSuggest	4.0
stats.facet		1.4
stats.field		1.4
terms.regex		3.2
timeAllowed		1.3
tv.all			1.4
tv.fl			3.1
tv.tf			1.4
/;

our %deprecated = qw/
facet.date		3.1
facet.zeros		1.2
carrot.lexicalResourcesDir 4.5
/;

