use v6;

use Uzu::HTTP;

unit module Uzu::LiveReload;

our sub reload-browser(
    Map $config,
    --> Bool()
) {
    unless $config<no_livereload> {
        Uzu::HTTP::inet-request
            "GET /reload HTTP/1.0\r\nContent-length: 0\r\n\r\n",
            $config<port>, $config<host>;
    }
}

