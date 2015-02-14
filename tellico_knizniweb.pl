#!/usr/bin/perl -w

# tellico_knizniweb.pl
# (c)2005-2008 Stepan Roh <src@post.cz>
# FREE TO USE, FREE TO MODIFY
# NO WARRANTY

use LWP::UserAgent;
use IO::String;
use XML::Writer;
use HTML::TreeBuilder;
use Text::Iconv;
use MIME::Base64;
use Digest::MD5;
use Encode;

sub into_xml(\@) {
    my ($arrayref) = @_;

    my $xmlstring;
    my $output = new IO::String($xmlstring);

    my $writer = new XML::Writer( OUTPUT => $output, DATA_MODE => 1, DATA_INDENT => 1 );
    $writer->xmlDecl("UTF-8");
    $writer->doctype("tellico",
                     "-//Robby Stephenson/DTD Tellico V8.0//EN",
                     "http://periapsis.org/bookcase/dtd/v8/bookcase.dtd");

    $writer->startTag('tellico',
                      'xmlns'=> 'http://periapsis.org/tellico/',
                      'syntaxVersion' => "8"
                     );

    $writer->startTag('collection',
                      'entryTitle' => 'Books',
                      'title' => "Knizniweb Search Results",
                      'type'=> "2"
                     );

    # non-standard fields
    $writer->startTag('fields');
    $writer->emptyTag('field',
                      'name' => "_default"  # include default fields
                     );
    $writer->endTag;

    my %images = ();

    foreach $entry (@$arrayref) {
        $writer->startTag('entry');
        foreach $field (keys %$entry) {
          if ($field eq 'cover') {
            my $cover = MIME::Base64::encode_base64($entry->{$field});
            my $cover_id =  Digest::MD5::md5_hex($cover). '.jpeg';
            $writer->dataElement('cover', $cover_id);
            $images{$cover_id} = $cover;
          } else {
            $writer->dataElement($field, $entry->{$field});
          }
        }
        $writer->endTag;        # entry
    }

    # image
    $writer->startTag('images');

    foreach my $image_id (keys %images) {
        $writer->startTag('image',
                          'format' => "JPEG",
                          'id' => $image_id,
                         );
        $writer->characters($images{$image_id});
        $writer->endTag;
    }
    $writer->endTag;  # images

    $writer->endTag;
    $writer->endTag;

    return $xmlstring. "\n";
}

$ua = LWP::UserAgent->new();
$ua->agent("Tellico Source Script for knizniweb.cz (private use)/0.1");

$search = $ARGV[0];

$res = $ua->get('http://www.knizniweb.cz/jnp/cz/ctenari/search/advance/index$136474.html?perpage=50&titleUniversalId='.$search);

%fields_map = (
  'Název:' => 'title',
  'Autor:' => 'author',
  'Nakladatel:' => 'publisher',
  'ISBN:' => 'isbn',
  'Poèet stran:' => 'pages',
  'Vazba:' => 'binding',
  'Rok vydání:' => 'pub_year',
);

if ($res->is_success) {
  my @hrefs = ($res->content =~ m,"([^"]*katalog/data[^"]*)",g);
  foreach $href (@hrefs) {
    $hrefs{$href} = 1;
  }
  @hrefs = sort keys %hrefs;
  my @entries = ();
  my $converter = Text::Iconv->new("windows-1250", "utf-8");
  foreach $href (@hrefs) {
    my $res = $ua->get('http://www.knizniweb.cz'.$href);
    if ($res->is_success) {
      my %fields = ();
      my $html = HTML::TreeBuilder->new_from_content($res->content);
      my $details = $html->look_down("_tag", "table", "class", "bookDetails");
      my @trs = $details->find("tr");
      foreach $tr (@trs) {
        my $field_cs_name = $tr->find("th")->as_trimmed_text();
        my $field_name = $fields_map{$field_cs_name};
        next if (!defined ($field_name));
        my $field_value = $tr->find("td")->as_trimmed_text();
        if ($field_name eq "binding") {
          if ($field_value eq "Vázaný") {
            $field_value = "Hardback";
          } elsif ($field_value eq "Brožovaný") { # this is in windows-1250
            $field_value = "Paperback";
          }
        }
        $field_value = $converter->convert($field_value);
        $field_value = Encode::decode_utf8($field_value);
        $fields{$field_name} = $field_value;
      }
      my $cover = $details->parent()->parent()->find("img");
      my $cover_res = $ua->get('http://www.knizniweb.cz'.$cover->attr("src"));
      if ($cover_res->is_success) {
        $fields{'cover'} = $cover_res->content;
      }
      $fields{'language'} = 'cs';
      push (@entries, \%fields);
    }
  }
  binmode STDOUT, ":utf8";
  print into_xml (@entries);
} else {
  print STDERR $res->status_line, "\n";
  exit 1;
}

1;
