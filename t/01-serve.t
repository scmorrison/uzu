use Test;
use Uzu;
use HTTP::Client;

plan 3;

my $r1 = Uzu::serve(config_file => 't/config');
is $r1.WHAT, Proc::Async, 'serve 1/3';
say "Waiting for web server to start serving";
sleep 5;

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

my $client = HTTP::Client.new;
my $r2 = $client.get('http://0.0.0.0:3000/index.html');
is $r2.success, True, 'serve 2/3';
is $r2.content, $html_test, 'serve 3/3';
