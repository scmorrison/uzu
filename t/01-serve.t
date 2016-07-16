use Test;
use Uzu;
use HTTP::Tinyish;

plan 3;

my $r1 = Uzu::serve(config_file => 't/config.yml');
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

my $client = HTTP::Tinyish.new(agent => "Mozilla/4.0");
my %r2 = $client.get('http://0.0.0.0:3000/index.html');
is %r2<status>, 200, 'serve 2/3';
is %r2<content>, $html_test, 'serve 3/3';
