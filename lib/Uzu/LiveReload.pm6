use v6;

unit module Uzu::LiveReload;

our sub reload-browser(
    Map $config,
    --> Bool()
) {
    unless $config<no_livereload> {
        use HTTP::Tinyish;
        HTTP::Tinyish.new().get("http://{$config<host>}:{$config<port>}/reload");
    }
}

