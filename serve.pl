use strict;
use warnings;
use IO::Socket::INET;

my ($port, $file) = @ARGV;
my $server = IO::Socket::INET->new(LocalPort => $port, Listen => 8, ReuseAddr => 1) or exit 0;
$SIG{CHLD} = 'IGNORE';

while (my $client = $server->accept) {
    if (fork) { close $client; next; }
    alarm 10;
    while (defined(my $line = <$client>)) { last if $line =~ /^\r?\n$/; }
    open my $fh, '<:raw', $file or exit 1;
    my $body = do { local $/; <$fh> };
    print $client "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: "
        . length($body) . "\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n" . $body;
    exit 0;
}
