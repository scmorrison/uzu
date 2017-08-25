use v6;
use lib 'lib';

use Test;
use Uzu::Config;
use Uzu::HTTP;

plan 3;

my $root = $*CWD;
my $app = Uzu::Config::from-file(
    config_file   => $root.IO.child('t').child('serve').child('config.yml'),
    no_livereload => True).&Uzu::HTTP::web-server();

say "Waiting for web server to start serving";

my $host = '127.0.0.1';
my $port = 3333;

# Wait for server to come online
is Uzu::HTTP::wait-port($port, times => 600), True, 'spawned development web server';

subtest {
    plan 1;

    my $html_test = q:to/END/;
    <html>
      <head>
        <title>Test</title>
      </head>
      <body>
        Uzu test html
      </body>
    </html>
    END

    my $results = Uzu::HTTP::inet-request("GET /index.html HTTP/1.0\r\nContent-length: 0\r\n\r\n", $port);
    ok $results ~~ / $html_test /, 'served HTML match';
}, 'Top-level page';

subtest {
    plan 1;

    my $html_test = q:to/END/;
    <html>
      <head>
        <title>Fiji Vacation 2017</title>
      </head>
      <body>
        2017/07/18<br/>
        Our trip to Fiji
      </body>
    </html>
    END

    my $results = Uzu::HTTP::inet-request("GET /blog/fiji.html HTTP/1.0\r\nContent-length: 0\r\n\r\n", $port);
    ok $results ~~ / $html_test /, 'served nested page HTML match';
}, 'Nested page';

# vim: ft=perl6
