#!/usr/bin/perl -w

# tellico_dumknihy.pl
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
                      'title' => "Dum Knihy Search Results",
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
$ua->agent("Tellico Source Script for dumknihy.cz (private use)/0.1");
$ua->cookie_jar( {} );

$search = $ARGV[0];

$search =~ tr/-//d;

$res = $ua->get('http://www.dumknihy.cz/hledanizpracuj.asp?akce=OK&isbn='.$search);

if ($res->is_success) {
  my @hrefs = ($res->content =~ m,"\s*([^"]*?titul\.asp[^"]*?)\s*",g);
  foreach $href (@hrefs) {
    $hrefs{$href} = 1;
  }
  @hrefs = sort keys %hrefs;
  my @entries = ();
  my $converter = Text::Iconv->new("windows-1250", "utf-8");
  foreach $href (@hrefs) {
    my $res = $ua->get('http://www.dumknihy.cz/'.$href);
    if ($res->is_success) {
      my %fields = ();
      my $content = $converter->convert($res->content);
      $content = Encode::decode_utf8($content);
      my $html = HTML::TreeBuilder->new_from_content($content);
      $fields{'title'} = $html->look_down("_tag", "span", "class", "nadpis")->as_trimmed_text();
      my $subtitle_elem = $html->look_down("_tag", "span", "class", "produkt_podnazev");
      if (defined $subtitle_elem) {
        $fields{'subtitle'} = $subtitle_elem->as_trimmed_text();
      }
      my $descr_html = $html->find("strong")->parent()->as_HTML();
      my @descr_parts = split(/<br ?\/?>/, $descr_html, 6);
      my @descr_texts = ();
      foreach $part (@descr_parts) {
        my $part_html = HTML::TreeBuilder->new_from_content($part);
        my $text = $part_html->as_trimmed_text();
        push (@descr_texts, $text);
      }
      my ($author, $info, $info2, $ean, $isbn) = @descr_texts;
      # info2 is missing
      if ($info2 =~ /EAN/) {
        $isbn = $ean;
      }
      $fields{'author'} = $author;
      ($fields{'isbn'}) = ($isbn =~ /ISBN\s+(.*)$/);
      my ($publisher, $year, $binding, $pages) = ($info =~ /^(.*?)\s*,\s*(\d*).*?-\s*(\S+).*?(\d+)/);
      $fields{'publisher'} = $publisher;
      $fields{'pub_year'} = $year;
      $fields{'binding'} = ($binding =~ /váz/) ? 'Hardback' : 'Paperback';
      $fields{'pages'} = $pages;
      my $cover = $html->find("img");
      my $cover_res = $ua->get('http://www.dumknihy.cz/'.$cover->attr("src"));
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
