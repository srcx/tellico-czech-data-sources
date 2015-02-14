#!/usr/bin/perl -w

# tellico_kosmas.pl
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
                      'title' => "Kosmas Search Results",
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
$ua->agent("Tellico Source Script for kosmas.cz (private use)/0.1");

$search = $ARGV[0] || $ARGV[1];

$res = $ua->get('http://www.kosmas.cz/hledani_vysledek.asp?isbn='.$search);

%fields_map = (
  'Nakladatel:' => 'publisher',
  'ISBN:' => 'isbn',
  'Rok vydání:' => 'pub_year',
  'Formát:' => '_spec',
);

if ($res->is_success) {
  # no support for multiple search results
  my $converter = Text::Iconv->new("windows-1250", "utf-8");
  my %fields = ();
  my $content = $converter->convert($res->content);
  $content = Encode::decode_utf8($content);
  my $html = HTML::TreeBuilder->new_from_content($content);
  if (!defined $html->find("h1")) {
    my @empty = ();
    print into_xml(@empty);
    exit 0;
  }
  my $header_td = $html->find("h1")->parent();
  $fields{'title'} = $header_td->find("h1")->as_trimmed_text();
  my $subtitle_elem = $header_td->find("strong");
  if (defined $subtitle_elem) {
    $fields{'subtitle'} = $subtitle_elem->as_trimmed_text();
  }
  my @authors = $header_td->find("a");
  foreach $author (@authors) {
    push (@{$fields{'author'}}, $author->as_trimmed_text());
  }
  my $descr_html = $html->look_down("_tag", "a", "name", "popis")->right()->find("td")->as_HTML('<>&');
  $descr_html =~ s/<strong>/<b>/g;
  $descr_html =~ s,</strong>,</b>,g;
  my @descr_parts = split(/<br ?\/?>/, $descr_html);
  foreach $part (@descr_parts) {
    if ($part =~ s,^.*?<b>\s*(.*?)\s*</b>,,) {
      my $field_cs_name = $1;
      my $field_name = $fields_map{$field_cs_name};
      next if (!defined ($field_name));
      my $part_html = HTML::TreeBuilder->new_from_content($part);
      $field_value = $part_html->as_trimmed_text();
      if ($field_name eq '_spec') {
        my ($pages, $size, $lang, $binding) = split(/\s*, \s*/, $field_value, 5);
        ($fields{'pages'}) = ($pages =~ /(\d+)/);
        $fields{'language'} = ($lang eq 'èesky') ? 'cs' : $lang;
        $fields{'binding'} = ($binding =~ /vázan/) ? 'Hardback' : 'Paperback';
      } else {
        if ($field_name eq 'pub_year') {
          ($field_value) = split(/\s+/, $field_value, 2);
        } elsif ($field_name eq 'isbn') {
          ($field_value) = split(/,/, $field_value, 2);
        }
        $fields{$field_name} = $field_value;
      }
    }
  }
  my $cover = $header_td->parent()->parent()->right();
  while (defined $cover) {
    last if ($cover->tag() eq 'table');
  }
  $cover = $cover->find("img");
  $cover_src = $cover->attr("src");
  if ($cover_src !~ m,http://,) {
    $cover_src = 'http://www.kosmas.cz'.$cover_src;
  }
  my $cover_res = $ua->get($cover_src);
  if ($cover_res->is_success) {
    $fields{'cover'} = $cover_res->content;
  }
  my @entries = ( \%fields );
  binmode STDOUT, ":utf8";
  print into_xml (@entries);
} else {
  print STDERR $res->status_line, "\n";
  exit 1;
}

1;
