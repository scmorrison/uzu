use v6;
use lib 'lib';

use Test;
use Uzu;
use HTTP::Tinyish;

plan 3;

Uzu::config(config_file => "t/config.yml");

my $r1 = Uzu::serve();
is $r1.WHAT, Proc::Async, 'serve 1/3: spawned server as proc async';
say "Waiting for web server to start serving";

Uzu::wait_port(port => 3000);

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

my $client = HTTP::Tinyish.new(agent => "Mozilla/4.0");
my %r2 = $client.get('http://0.0.0.0:3000/index.html');
is %r2<status>, 200, 'serve 2/3: HTTP 200 OK';
is %r2<content>, $html_test, 'serve 3/3: served HTML match';

# vim: ft=perl6
