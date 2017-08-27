use v6;
use lib 'lib';

use Test;
use Test::Output;
use Uzu::Config;
use Uzu::HTTP;

plan 4;

my $root = $*CWD;
my $host = '127.0.0.1';
my $port = 3333;

my $output = output-from {
    Uzu::Config::from-file(
        config_file   => $root.IO.child('t').child('serve').child('config.yml'),
        no_livereload => True).&Uzu::HTTP::web-server()
}
say $output if %*ENV<UZUSTDOUT>;

subtest {
    plan 1;

    # Wait for server to come online
    is Uzu::HTTP::wait-port($port, times => 600), True, 'spawned development web server';
}, 'Single theme';

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

subtest {
    plan 2;

    my $t1_output = output-from {
        Uzu::Config::from-file(
            config_file   => $root.IO.child('t').child('serve').child('config-multi.yml'),
            no_livereload => True).&Uzu::HTTP::web-server();
    }
    say $t1_output if %*ENV<UZUSTDOUT>;

    # Wait for server to come online
    my $t1_default_server    = Uzu::HTTP::wait-port(3333, times => 600);
    my $t1_summer2017_server = Uzu::HTTP::wait-port(3335, times => 600);

    is ($t1_default_server && $t1_summer2017_server), True, 'spawned development web server';

    my $t2_output = output-from {
        Uzu::Config::from-file(
            config_file   => $root.IO.child('t').child('serve').child('config-multi-port-increment.yml'),
            no_livereload => True).&Uzu::HTTP::web-server();
    }
    say $t2_output if %*ENV<UZUSTDOUT>;

    # Wait for server to come online
    my $t2_default_server    = Uzu::HTTP::wait-port(4000, times => 600);
    my $t2_summer2017_server = Uzu::HTTP::wait-port(4001, times => 600);

    is ($t2_default_server && $t2_summer2017_server), True, 'auto-increment port number when not defined in config';
}, 'Multi-theme'
# vim: ft=perl6
