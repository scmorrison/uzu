use v6;
use lib 'lib';

use Test;
use Uzu::HTTP;

plan 2;

my $root = $*CWD;
my $r1 = Uzu::HTTP::serve(config_file => $root.IO.child('t').child('serve').child('config.yml'));
is $r1.WHAT, Proc::Async, 'serve 1/2: spawned server as proc async';
say "Waiting for web server to start serving";

my $host = '127.0.0.1';
my $port = 3333;

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

# Wait for server to come online
Uzu::HTTP::wait-port($port, times => 600);
ok Uzu::HTTP::inet-request("GET /index.html HTTP/1.0\r\nContent-length: 0\r\n\r\n", $port) ~~ / $html_test /, 'serve 2/2: served HTML match';

# Clean up
$r1.kill(SIGKILL);

# vim: ft=perl6
