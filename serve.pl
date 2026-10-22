use strict;
use warnings;
use IO::Socket::INET;

my ($port, $dir, $frames) = @ARGV;
my %routes = ('/' => ["$dir/remote.html", 'text/html; charset=utf-8'], '/icon.png' => ["$dir/icon.png", 'image/png']);
my $server = IO::Socket::INET->new(LocalPort => $port, Listen => 8, ReuseAddr => 1) or exit 0;
$SIG{CHLD} = 'IGNORE';

while (my $client = $server->accept) {
    if (fork) { close $client; next; }
    alarm 10;
    my ($path) = (<$client> // '') =~ m{^GET (/[^ ?#]*)};
    while (defined(my $line = <$client>)) { last if $line =~ /^\r?\n$/; }
    $path //= '';
    my $route = $path =~ m{^/frame/(\d+)\.jpg$} ? ["$frames/$1.jpg", 'image/jpeg'] : $routes{$path};
    my $fh;
    unless ($route && open $fh, '<:raw', $route->[0]) {
        print $client "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
        exit 0;
    }
    my $body = do { local $/; <$fh> };
    print $client "HTTP/1.1 200 OK\r\nContent-Type: $route->[1]\r\nContent-Length: " . length($body)
        . "\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n" . $body;
    exit 0;
}
