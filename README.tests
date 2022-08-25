
# Setting up a test server

Some of the tests require contact to a real Solr server.  Its name
must be set as environment variable SOLR_TEST_SERVER.

The server should support Fields 'id', 'subject', 'content_type',
and 'content'.  In my 3.6 server, the 'content' fields was missing
from the default server configuration.  I had to add

  <field name="content" type="text_generic" indexed="true" stored="true" />

to the schema.xml file.  Probably you also need to add the

  <copyField source="content" dest="text" />

Also, enable apache-solr-cell in /etc/solr/conf/solrconfig.xml with

  <lib dir="/usr/local/share/java/dist/" regex="apache-solr-cell-\d.*\.jar" />
  <lib dir="/usr/local/share/java/contrib/extraction/lib" regex=".*\.jar" />

The exact paths may differ on your system.

And then restart jetty9

