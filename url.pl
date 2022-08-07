#!/usr/bin/perl
#
# Retrieve a web page.
# Designed to work with procmail.
#
# Testing via command line:
#
# echo -n "" | ./url.pl MODE URL
#
# Mode is "-s" for source, "-t" for processed text.

use File::Temp;
use HTML::TokeParser;
use IO::File;
use LWP;
use LWP::UserAgent;
use URI::URL;
use Text::Wrap;
use strict;


my ($Parameters) = $ARGV[1];
my ($Mode) = $ARGV[0];
my ($FileName, $QuotaStuff, $OldCD, $dir, $ua, $req, $res);
my ($Results, $Config, $Subject, $UserData, $MaxSize);
my ($fh);

if ($Parameters !~ /^[a-z]+:\/\//i)
{
    $Parameters = "http://$Parameters" if ($Parameters =~ /^www/i);
    $Parameters = "ftp://$Parameters" if ($Parameters =~ /^ftp/i);
}

if ($Parameters !~ /^http:\/\//i && $Parameters !~ /^ftp:\/\//i &&
    $Parameters !~ /^gopher:\/\//i && $Parameters !~ /^news:/i &&
    $Parameters !~ /^https:\/\//i)
{
    $Parameters = 'http://' . $Parameters;
}

$dir = File::Temp->newdir(); # Automatically create new, temp directory and cleaned up at termination
$ua = LWP::UserAgent->new(
    ssl_opts => {
        verify_hostname => 0
    }
);
$ua->agent("WebPage/1.0 " . $ua->agent);
$ua->max_size(1024 * 4096);
$req = new HTTP::Request GET => $Parameters;
$FileName = $dir . '/request';
$res = $ua->request($req, $FileName);
if (! $res->is_success)
{
    print "Failure getting the URL $Parameters\n";
    print "Error:  " . ($res->code()) . " " . ($res->message()) . "\n";
    exit();
}

if ($res->content_type !~ /^text\//i && $res->content_type !~ /^application\/json$/)
{
    print "Sorry, this file has an invalid content type.\n";
    print "Only HTML, text, and JSON files are allowed.\n";
    print "The Content-Type provided is:  " . $res->content_type . "\n";
    exit();
}

if ($res->header("X-Content-Range"))
{
    print "File was too large -- sending " .
        $res->header("X-Content-Range") . "\n";
}

if ($res->content_type =~ /^text\/html$/i && $Mode ne '-s')
{
    print HTML2TXT($FileName, $Parameters);
}
else
{
    ShowFile($FileName);
}



sub HTML2TXT
{
    # Slightly altered from convert.pl by 
    # Christopher Heschong <chris@screwdriver.net>
    my ($FileName, $UrlBase) = @_;
    my ($p, $token, @ListType, @Links);
    my ($doctext, $url, $i, $oldterminator);
    
    $p = HTML::TokeParser->new(file => $FileName);
    @ListType = ();


    while ($token = $p->get_token) {
        # NOTE:  <pre> tags are broken
        if ($token->[0] eq 'S')
        {
            if ($token->[1] eq 'a')
            {
                my $url = $token->[2]{href} || '';
                if ($url ne '')
                {
                    push (@Links, $url);
                    $doctext .= '[' . scalar(@Links) . ']';
                }
            }
            elsif ($token->[1] eq 'frame')
            {
                my $url = $token->[2]{src} || '';
                if ($url ne '')
                {
                    push (@Links, $url);
                    my $t = $p->get_trimmed_text;
                    $t =~ s/[\r\n]/ /g;
                    $doctext .= '[' . scalar(@Links) . ' -- Frame:  ' .
                      $t . ']';
                }
            }
            elsif ($token->[1] eq 'br')
            {
                $doctext .= "\n";
            }
            elsif ($token->[1] eq 'p')
            {
                $doctext .= "\n \n";
            }
            elsif ($token->[1] eq 'title' ||
                $token->[1] eq 'script' ||
                $token->[1] eq 'style')
            {
                # Skip
                $p->get_text;
            }
            elsif ($token->[1] eq 'ul')
            {
                push (@ListType, -1);
            }
            elsif ($token->[1] eq 'ol')
            {
                push (@ListType, 1);
            }
            elsif ($token->[1] eq 'li')
            {
                my $type = pop(@ListType);
                if (! defined($type) || $type < 1)
                {
                    $type = -1;
                    $doctext .= "\n * ";
                }
                else
                {
                    $doctext .= "\n " . $type . ". ";
                    $type ++;
                }
                push(@ListType, $type);
            }
            elsif ($token->[1] eq 'hr')
            {
                $doctext .= "\n----------------------------------------" .
                  "------------------------------\n";
            }
            elsif ($token->[1] =~ /^h\d/)
            {
                $doctext .= "\n \n";
            }
            elsif ($token->[1] eq 'img')
            {
                my $alt = $token->[2]{alt} || 'Img';
                $doctext .= '[' . $alt . ']';
            }
            elsif ($token->[1] eq 'dt')
            {
                $doctext .= "\n";
            }
            elsif ($token->[1] eq "dd")
            {
                $doctext .= "\n    ";
            }
            else
            {
                $doctext .= DumpToken($token);
            }
        }
        elsif ($token->[0] eq 'E')
        {
            if ($token->[1] eq 'ul' ||
                $token->[1] eq 'ol')
            {
                pop(@ListType);
            }
            elsif ($token->[1] eq 'td')
            {
                $doctext .= '   ';
            }
            elsif ($token->[1] eq 'tr' ||
                   $token =~ /^h\d/)
            {
                $doctext .= "\n";
            }
            elsif ($token->[1] eq 'table')
            {
                $doctext .= " \n";
            }
            else
            {
                $doctext .= DumpToken($token);
            }
        }
        elsif ($token->[0] eq 'T')
        {
            my $more = RecodeText($token->[1]);
            $more =~ s/[\r\n]/ /g;
            if (substr($more, 0, 1) eq ' ' &&
                (substr($doctext, -1, 1) eq ' ' ||
                 substr($doctext, -1, 1) eq "\n" ||
                 $doctext eq ''))
            {
                $more = substr($more, 1);
            }
            $doctext .= $more;
        }
        else
        {
            $doctext .= DumpToken($token);
        }
        # print join(", ", @$token) . "\n";
    }
    
    $i = 1;
    $doctext =~ s/ {10,}/         /g;
    $doctext =~ s/\n+/\n/g;
    $doctext = Rewrap($doctext);

    $doctext .= "\n\n\nLinks found:\n";
    while (@Links)
    {
        $doctext .= "  [$i] ";
        $url = url(shift(@Links), $UrlBase);
        $doctext .= $url->abs . "\n";
        $i ++;
    }
    
    print $doctext;
    return;
    
    

    # Get rid of some character for some reason that I forgot
    # $doctext =~ s/\x0D/\x0A/gi;

    # open(CONVERT, ">$FileName");
    # print CONVERT $doctext;
    # close(CONVERT);
    $/ = $oldterminator;
    return $doctext;
}


sub Escapes
{
    return ( # initialize hash-table of some HTML escapes
        # first, the big four HTML escapes
        'quot',       '"',    # quote
        'amp',        '&',    # ampersand
        'lt',         '<',    # less than
        'gt',         '>',    # greater than
        # Sam got most of the following HTML 4.0 names from
        # http://spectra.eng.hawaii.edu/~msmith/ASICs/HTML/Style/allChar.htm
        'emsp',       "\x80", # em space (HTML 2.0)
        'sbquo',      "\x82", # single low-9 (bottom) quotation mark (U+201A)
        'fnof',       "\x83", # Florin or Guilder (currency) (U+0192)
        'bdquo',      "\x84", # double low-9 (bottom) quotation mark (U+201E)
        'hellip',     "\x85", # horizontal ellipsis (U+2026)
        'dagger',     "\x86", # dagger (U+2020)
        'Dagger',     "\x87", # double dagger (U+2021)
        'circ',       "\x88", # modifier letter circumflex accent
        'permil',     "\x89", # per mill sign (U+2030)
        'Scaron',     "\x8A", # latin capital letter S with caron (U+0160)
        'lsaquo',     "\x8B", # left single angle quotation mark (U+2039)
        'OElig',      "\x8C", # latin capital ligature OE (U+0152)
        'diams',      "\x8D", # diamond suit (U+2666)
        'clubs',      "\x8E", # club suit (U+2663)
        'hearts',     "\x8F", # heart suit (U+2665)
        'spades',     "\x90", # spade suit (U+2660)
        'lsquo',      "\x91", # left single quotation mark (U+2018)
        'rsquo',      "\x92", # right single quotation mark (U+2019)
        'ldquo',      "\x93", # left double quotation mark (U+201C)
        'rdquo',      "\x94", # right double quotation mark (U+201D)
        'endash',     "\x96", # dash the width of ensp (Lynx)
        'ndash',      "\x96", # dash the width of ensp (HTML 2.0)
        'emdash',     "\x97", # dash the width of emsp (Lynx)
        'mdash',      "\x97", # dash the width of emsp (HTML 2.0)
        'tilde',      "\x98", # small tilde
        'trade',      "\x99", # trademark sign (HTML 2.0)
        'scaron',     "\x9A", # latin small letter s with caron (U+0161)
        'rsaquo',     "\x9B", # right single angle quotation mark (U+203A)
        'oelig',      "\x9C", # latin small ligature oe (U+0153)
        'Yuml',       "\x9F", # latin capital letter Y with diaeresis (U+0178)
        'ensp',       "\xA0", # en space (HTML 2.0)
        'thinsp',     "\xA0", # thin space (Lynx)
        # from this point on, we're all (but 2) HTML 2.0
        'nbsp',       "\xA0", # non breaking space
        'iexcl',      "\xA1", # inverted exclamation mark
        'cent',       "\xA2", # cent (currency)
        'pound',      "\xA3", # pound sterling (currency)
        'curren',     "\xA4", # general currency sign (currency)
        'yen',        "\xA5", # yen (currency)
        'brkbar',     "\xA6", # broken vertical bar (Lynx)
        'brvbar',     "\xA6", # broken vertical bar
        'sect',       "\xA7", # section sign
        'die',        "\xA8", # spacing dieresis (Lynx)
        'uml',        "\xA8", # spacing dieresis
        'copy',       "\xA9", # copyright sign
        'ordf',       "\xAA", # feminine ordinal indicator
        'laquo',      "\xAB", # angle quotation mark, left
        'not',        "\xAC", # negation sign
        'shy',        "\xAD", # soft hyphen
        'reg',        "\xAE", # circled R registered sign
        'hibar',      "\xAF", # spacing macron (Lynx)
        'macr',       "\xAF", # spacing macron
        'deg',        "\xB0", # degree sign
        'plusmn',     "\xB1", # plus-or-minus sign
        'sup2',       "\xB2", # superscript 2
        'sup3',       "\xB3", # superscript 3
        'acute',      "\xB4", # spacing acute
        'micro',      "\xB5", # micro sign
        'para',       "\xB6", # paragraph sign
        'middot',     "\xB7", # middle dot
        'cedil',      "\xB8", # spacing cedilla
        'sup1',       "\xB9", # superscript 1
        'ordm',       "\xBA", # masculine ordinal indicator
        'raquo',      "\xBB", # angle quotation mark, right
        'frac14',     "\xBC", # fraction 1/4
        'frac12',     "\xBD", # fraction 1/2
        'frac34',     "\xBE", # fraction 3/4
        'iquest',     "\xBF", # inverted question mark
        'Agrave',     "\xC0", # capital A, grave accent
        'Aacute',     "\xC1", # capital A, acute accent
        'Acirc',      "\xC2", # capital A, circumflex accent
        'Atilde',     "\xC3", # capital A, tilde
        'Auml',       "\xC4", # capital A, dieresis or umlaut mark
        'Aring',      "\xC5", # capital A, ring
        'AElig',      "\xC6", # capital AE diphthong (ligature)
        'Ccedil',     "\xC7", # capital C, cedilla
        'Egrave',     "\xC8", # capital E, grave accent
        'Eacute',     "\xC9", # capital E, acute accent
        'Ecirc',      "\xCA", # capital E, circumflex accent
        'Euml',       "\xCB", # capital E, dieresis or umlaut mark
        'Igrave',     "\xCC", # capital I, grave accent
        'Iacute',     "\xCD", # capital I, acute accent
        'Icirc',      "\xCE", # capital I, circumflex accent
        'Iuml',       "\xCF", # capital I, dieresis or umlaut mark
        'Dstrok',     "\xD0", # capital Eth, Icelandic (Lynx)
        'ETH',        "\xD0", # capital Eth, Icelandic
        'Ntilde',     "\xD1", # capital N, tilde
        'Ograve',     "\xD2", # capital O, grave accent
        'Oacute',     "\xD3", # capital O, acute accent
        'Ocirc',      "\xD4", # capital O, circumflex accent
        'Otilde',     "\xD5", # capital O, tilde
        'Ouml',       "\xD6", # capital O, dieresis or umlaut mark
        'times',      "\xD7", # multiplication sign
        'Oslash',     "\xD8", # capital O, slash
        'Ugrave',     "\xD9", # capital U, grave accent
        'Uacute',     "\xDA", # capital U, acute accent
        'Ucirc',      "\xDB", # capital U, circumflex accent
        'Uuml',       "\xDC", # capital U, dieresis or umlaut mark
        'Yacute',     "\xDD", # capital Y, acute accent
        'THORN',      "\xDE", # capital THORN, Icelandic
        'szlig',      "\xDF", # small sharp s, German (sz ligature)
        'agrave',     "\xE0", # small a, grave accent
        'aacute',     "\xE1", # small a, acute accent
        'acirc',      "\xE2", # small a, circumflex accent
        'atilde',     "\xE3", # small a, tilde
        'auml',       "\xE4", # small a, dieresis or umlaut mark
        'aring',      "\xE5", # small a, ring
        'aelig',      "\xE6", # small ae diphthong (ligature)
        'ccedil',     "\xE7", # small c, cedilla
        'egrave',     "\xE8", # small e, grave accent
        'eacute',     "\xE9", # small e, acute accent
        'ecirc',      "\xEA", # small e, circumflex accent
        'euml',       "\xEB", # small e, dieresis or umlaut mark
        'igrave',     "\xEC", # small i, grave accent
        'iacute',     "\xED", # small i, acute accent
        'icirc',      "\xEE", # small i, circumflex accent
        'iuml',       "\xEF", # small i, dieresis or umlaut mark
        'dstrok',     "\xF0", # small eth, Icelandic (Lynx)
        'eth',        "\xF0", # small eth, Icelandic
        'ntilde',     "\xF1", # small n, tilde
        'ograve',     "\xF2", # small o, grave accent
        'oacute',     "\xF3", # small o, acute accent
        'ocirc',      "\xF4", # small o, circumflex accent
        'otilde',     "\xF5", # small o, tilde
        'ouml',       "\xF6", # small o, dieresis or umlaut mark
        'divide',     "\xF7", # division sign
        'oslash',     "\xF8", # small o, slash
        'ugrave',     "\xF9", # small u, grave accent
        'uacute',     "\xFA", # small u, acute accent
        'ucirc',      "\xFB", # small u, circumflex accent
        'uuml',       "\xFC", # small u, dieresis or umlaut mark
        'yacute',     "\xFD", # small y, acute accent
        'thorn',      "\xFE", # small thorn, Icelandic
        'yuml',       "\xFF", # small y, dieresis or umlaut mark
    );
}


sub ShowFile
{
    my ($FileName) = @_;
    my ($oldterminator, $doctext);
    
    open (CONVERT, $FileName);
    $oldterminator = $/;
    undef $/;
    $doctext = <CONVERT>;
    close(CONVERT);
    $/ = $oldterminator;
    print $doctext;
}    


sub RecodeText
{
    my ($Text) = @_;
    my (%escapes);

    # \r and \n have been taken care of already
    $Text =~ s/(\t| +)/ /g;
    
    # Convert Special HTML Characters
    # From: "Yannick Bergeron" <bergery@videotron.ca>
    # And Especially:  Sam Denton <Sam.Denton@maryville.com>
    %escapes = Escapes();

    foreach (32..126, 160..255) {
       $escapes{'#'.$_} = pack('c',$_);
    }

    foreach (keys(%escapes))
    {
        $Text =~ s/&$_;/$escapes{$_}/eg;
    }

    return $Text;
}



sub DumpToken
{
    my ($token) = @_;
    
    return '';
    return '<' . $token->[0] . ' ' . $token->[1] . '>';
}


sub Rewrap
{
    my ($in) = @_;
    my ($l, @out);
    
    foreach $l (split("\n", $in))
    {
        $l =~ /^( +)?(.*)$/;
        push(@out, wrap($1, $1, $2));
    }
    
    return join("\n", @out);
}
