use Uzu::Config;
use Uzu::HTTP;
use Uzu::Render;
use Uzu::Watch;
use Terminal::ANSIColor;

my %*SUB-MAIN-OPTS = :named-anywhere;

sub USAGE is export {
  say q:to/END/;
      Usage:
        uzu init          - Initialize new project
        uzu webserver     - Start local web server
        uzu build         - Render all templates to build
        uzu clear         - Delete build directory and all of its contents
        uzu watch         - Start web server and re-render
                            build on template modification
        uzu version       - Print uzu version and exit

      Optional arguments:
        
        --config=         - Specify a custom config file
                            Default is `config`

        e.g. uzu --config=path/to/config.yml init 

        --no-livereload   - Disable livereload when
                            running uzu watch.

        --clear           - Delete build directory before 
                            render when running with build.

        --page-filter     - Restrict build to pages starting
                            from this directory

        --theme           - Limit build / watch to single theme

        e.g. uzu --theme=default build 
      END
}

multi MAIN(
    'config',
    Str :$config = 'config.yml'
) is export {
    say Uzu::Config::from-file(
        config_file => $config.IO);
}

multi MAIN(
    'webserver',
    Str :$config = 'config.yml'
) is export {
    say "ctrl+c / command+c to stop";
    await Uzu::HTTP::web-server
        Uzu::Config::from-file(
            config_file => $config.IO
        );
}

multi MAIN(
    'build',
    Str  :$config      = 'config.yml',
    Str  :$page-filter = '',
    Str  :$theme,
    Bool :$clear       = False
) is export {
    my %config = Uzu::Config::from-file
        config_file   => $config.IO,
        page_filter   => $page-filter,
        single_theme  => $theme,
        no_livereload => True;
    if $clear {
        Uzu::Render::clear %config;
    }
    Uzu::Render::build %config;
}

multi MAIN(
    'clear',
    Str :$config = 'config.yml'
) is export {
    Uzu::Render::clear
        Uzu::Config::from-file(
            config_file   => $config.IO,
            no_livereload => True);
}

multi MAIN(
    'watch',
    Str  :$config        = 'config.yml',
    Str  :$page-filter   = '',
    Str  :$theme,
    Bool :$no-livereload = False
) is export {
    Uzu::Watch::start(
        Uzu::Config::from-file(
            config_file   => $config.IO,
            page_filter   => $page-filter,
            single_theme  => $theme,
            no_livereload => $no-livereload
    ));
}

multi MAIN(
    'init',
    Str :$config = 'config.yml'
) is export {

    # config file exists, exit
    return say "Please run uzu init from an empty directory." unless elems(dir '.') eq 0;

    my Bool $continue = False;
    my Str  $site_name;
    my Str  $language;
    my Str  $template_engine = 'mustache';
  
    until $continue
          && $site_name !~~ ''
          && $template_engine ~~ 'mustache'|'tt'
          && so $language ~~ /^<[a..z]> ** 2..2 $/ {

        if $site_name ~~ '' {
            say colored "Site name must not be blank.\n", "bold white on_red";
        }

        if $template_engine && $template_engine !~~ 'mustache'|'tt' {
            say colored "Template engine must be mustache or tt.\n", "bold white on_red";
        }

        if $language && so $language !~~ /^<[a..z]> ** 2..2 $/ {
            say colored "Language must be two character abreviation (e.g. en, ja).\n", "bold white on_red";
        }
        
        say "Uzu project initialization";
        $site_name       = prompt("Please enter site name: ") ~ '';
        $template_engine = prompt("Please enter template engine (mustache / tt): ");
        $language        = prompt("Please enter language (e.g. en, ja): ");
        my $confirmation = qq:to/EOF/;
        You have entered following:
        
            Site name: {$site_name}
            Templage engine: {$template_engine}
            Language: {$language}
        
        Enter y to continue
        EOF
        $continue        = prompt($confirmation) ~~ 'y'|'Y';
    }

    if Uzu::Config::init
        config_file     => $config.IO,
        site_name       => $site_name,
        language        => $language||'en',
        template_engine => $template_engine||'mustache' {
      say "Config [$config] successfully created.";
    }
}

multi MAIN('version') is export {
    use Uzu;
    say "uzu {Uzu.^ver}";
}
