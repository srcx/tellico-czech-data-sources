#!/usr/bin/perl -w

# tellico_dvt.pl
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
                      'title' => "DVT Search Results",
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
            my $cover_id =  Digest::MD5::md5_hex($cover). '.gif';
            $writer->dataElement('cover', $cover_id);
            $images{$cover_id} = $cover;
          } else {
            my $value = $entry->{$field};
            if (ref($value) eq 'ARRAY') {
              $writer->startTag($field.'s');
              foreach $v (@$value) {
                $writer->dataElement($field, $v);
              }
              $writer->endTag;
            } else {
              $writer->dataElement($field, $value);
            }
          }
        }
        $writer->endTag;        # entry
    }

    # image
    $writer->startTag('images');

    foreach my $image_id (keys %images) {
        $writer->startTag('image',
                          'format' => "GIF",
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
$ua->agent("Tellico Source Script for sckn.cz/dvt (private use)/0.1");

$search = $ARGV[0];

$res = $ua->get('http://www.sckn.cz/ceskeknihy/html/vyhledavani.php?odeslano=1&isbn='.$search);

%fields_map = (
  'Vydal:' => 'publisher',
  'Autor:' => 'author',
  'Název:' => 'title',
  'Podtitul:' => 'subtitle',
  'ISBN:' => 'isbn',
  'Vazba:' => 'binding',
  'Rok vydání:' => 'pub_year',
  'Poèet stran:' => 'pages',
  'Jazyk knihy:' => 'language',
);

if ($res->is_success) {
  # no support for multiple search results
  my $converter = Text::Iconv->new("windows-1250", "utf-8");
  my %fields = ();
  my $content = $converter->convert($res->content);
  $content = Encode::decode_utf8($content);
  my $html = HTML::TreeBuilder->new_from_content($content);
  my @elems = $html->find("div");
  my $field_cs_name;
  foreach $elem (@elems) {
    if ($elem->attr('class') eq 'vypisPadR') {
      $field_cs_name = $elem->as_trimmed_text();
    } elsif ($elem->attr('class') eq 'vypisPadL') {
      my $field_value = $elem->as_trimmed_text();
      my $field_name = $fields_map{$field_cs_name};
      next if (!defined ($field_name));
      if ($field_name eq 'binding') {
        $field_value = ($field_value =~ /^B/) ? 'Paperback' : 'Hardback';
      } elsif ($field_name eq 'language') {
        $field_value = ($field_value =~ /èeskı/) ? 'cs' : $field_value;
      }
      $fields{$field_name} = $field_value;
    }
  }
  my @entries = ( \%fields );
  binmode STDOUT, ":utf8";
  print into_xml (@entries);
} else {
  print STDERR $res->status_line, "\n";
  exit 1;
}

1;
