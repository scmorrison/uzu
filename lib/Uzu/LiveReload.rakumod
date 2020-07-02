use Uzu::HTTP;

unit module Uzu::LiveReload;

our sub reload-browser(
    %config,
    --> Bool()
) {
    unless %config<no_livereload> {
        for %config<themes> -> $theme_config {
            my %theme      = $theme_config.values.head;
            my $theme_port = %theme<port>;

            Uzu::HTTP::inet-request
                "GET /reload HTTP/1.0\r\nContent-length: 0\r\n\r\n",
                %theme<port>, %config<host>;
        }
    }
}

