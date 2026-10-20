use strict;
use warnings;
use IO::Socket::INET;

my ($port, $dir) = @ARGV;
my %routes = ('/' => ['remote.html', 'text/html; charset=utf-8'], '/icon.png' => ['icon.png', 'image/png']);
my $server = IO::Socket::INET->new(LocalPort => $port, Listen => 8, ReuseAddr => 1) or exit 0;
$SIG{CHLD} = 'IGNORE';

while (my $client = $server->accept) {
    if (fork) { close $client; next; }
    alarm 10;
    my ($path) = (<$client> // '') =~ m{^GET (/[^ ?#]*)};
    while (defined(my $line = <$client>)) { last if $line =~ /^\r?\n$/; }
    my $route = $routes{$path // ''};
    unless ($route) { print $client "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"; exit 0; }
    open my $fh, '<:raw', "$dir/$route->[0]" or exit 1;
    my $body = do { local $/; <$fh> };
    print $client "HTTP/1.1 200 OK\r\nContent-Type: $route->[1]\r\nContent-Length: " . length($body)
        . "\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n" . $body;
    exit 0;
}
