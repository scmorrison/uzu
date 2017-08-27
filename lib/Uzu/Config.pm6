use v6.c;

use YAMLish;

unit module Uzu::Config;

sub valid-project-folder-structure(
    @template_dirs
    --> Bool()
) {
    @template_dirs.grep({ !$_.IO.e }).&{
        unless elems $_ > 0 {
            note "Project directory missing: \n * {$_.join: "\n * "}";
            exit 1;
        }
    }();
}

sub parse-config(
    IO::Path :$config_file
    --> Map()
) {
    unless $config_file.IO.f {
        note "Config file [$config_file] not found. Please run uzu init to generate.";
        exit 1;
    }

    try {

        CATCH {
            default {
                note "Invalid config yaml file [$config_file]";
                note .Str;
                exit 1;
            }
        }

        my %global_config = slurp($config_file).&load-yaml when $config_file.IO.f;

        # Collect non-core variables into :site
        my $core_vars = 'host'|'language'|'port'|'project_root'|'site'|'theme'|'url';
        %global_config<site> = %global_config.grep({ $_.key !~~ $core_vars });

        return %global_config;
    }
}

sub build-dir-exists(@seen, $dir) {
    if so @seen (cont) $dir {
        note "Cannot render multiple themes to the same build directory [{$dir}]" when so @seen (cont) $dir;
        exit 1;
    }
}

sub safe-build-dir-check($dir, :$project_root) {
    if $dir.IO ~~ $*HOME.IO|$project_root.IO {
        note "Build directory [{$dir.IO.path}] cannot be {$*HOME} or project root [{$project_root}].";
        exit 1;
    }
}

sub themes-config(
    Str      :$single_theme,   # optional, only config this theme
    IO::Path :$themes_dir,     # project themes dir
    Str      :$theme,          # yaml theme:
    Array    :$themes,         # yaml themes:
    IO::Path :$build_dir,      # default build dir
    Int      :$port,           # default port
    List     :$exclude_pages,  # default exclude pages
    IO::Path :$project_root    # project root
    --> List()
) {
    # Always use single theme if yaml `theme:` variable set
    return ("{$theme||'default'}" => %(
                theme_dir      => $themes_dir.IO.child("$theme"||'default'),
                build_dir      => $build_dir,
                port           => $port,
                exclude_pages  => $exclude_pages),) when $themes ~~ [];

    # Keep track of build dirs to avoid
    # reusing the same build dir for
    # multiple themes.
    my IO::Path @seen_build_dirs;

    # We can to keep incrementing the 
    # port to assign to the next theme
    # if a port is not defined for the
    # theme or the defined port is 
    # already used.
    my Int $working_port = $port;

    # ... otherwise use hash
    return map -> $theme {
        
        given $theme {

            # Single theme, $theme = theme name
            when Str {

                # When user passes --theme to cli only configure that theme or skip
                next when $single_theme.defined && $single_theme !~~ $theme;

                my Int $theme_port = $working_port;
                ++$working_port;

                "{$theme||'default'}" => %(
                        theme_dir      => $themes_dir.IO.child($theme||'default'),
                        build_dir      => $build_dir.IO.child($theme||'default'),
                        port           => $theme_port,
                        exclude_pages  => $exclude_pages);
            } 
            
            default {

                my Str  $theme_name    = $theme.keys.head;
                my Hash $theme_config  = $theme.values.head;
                my IO::Path $theme_dir = $themes_dir.IO.child($theme_name);

                # When user passes --theme to cli only configure that theme or skip
                next when $single_theme.defined && $single_theme !~~ $theme_name;

                do {
                    note "Theme directory [{$theme_name}] does not exist. Skipping.";
                    next;
                } unless $theme_dir.IO.e;

                my IO::Path $theme_build_dir = do given $themes.elems {
                    when 1 {
                        # Single theme defined, use default build dir
                        $build_dir;
                    } 
                    default {
                        my $theme_build_dir = $theme_config<build_dir> ?? $theme_config<build_dir> !! $build_dir.IO.child($theme_name);
                        build-dir-exists @seen_build_dirs, $theme_build_dir;
                        push @seen_build_dirs, $theme_build_dir;
                        safe-build-dir-check $theme_build_dir.IO, :$project_root;
                        $theme_build_dir.IO;
                    }
                }

                my Int $theme_port = do given $themes.elems {
                    when 1 {
                        $theme_config<port>||$working_port;
                    }
                    default {
                        $working_port = $theme_config<port> when $theme_config<port> && $theme_config<port> > $working_port;
                        $theme_config<port>||$working_port;
                    }
                }

                ++$working_port;

                $theme_name => %(
                    theme_dir      => $theme_dir,
                    build_dir      => $theme_build_dir,
                    port           => $theme_port,
                    exclude_pages  => $theme_config<exclude_pages>)
            }

        }

    }, $themes.values;
}

our sub from-file(
    IO::Path :$config_file   = 'config.yml'.IO,
    Str      :$page_filter   = '',
    Str      :$single_theme,
    Bool     :$no_livereload = False
    --> Map
) {

    # Gemeral config
    my Map  $config         = parse-config(config_file => $config_file);
    my List $language       = [$config<language>];

    # Network
    my Str  $host           = $config<host>||'0.0.0.0';
    my Int  $port           = $config<port>||3000;

    # Misc.
    my List $exclude_pages  = [$config<exclude_pages>];

    # Paths
    my IO::Path $project_root     = "{$config<project_root>||$*CWD}".subst('~', $*HOME).IO;
    my IO::Path $build_dir        = $project_root.IO.child('build');
    my IO::Path $i18n_dir         = $project_root.IO.child('i18n');
    my IO::Path $themes_dir       = $project_root.IO.child('themes');
    my IO::Path $assets_dir       = $project_root.IO.child('themes').child("{$config<theme>||'default'}").child('assets');
    my IO::Path $theme_dir        = $project_root.IO.child('themes').child("{$config<theme>||'default'}");
    my List $themes               =
        themes-config(
           :$single_theme, :$themes_dir, :$build_dir, :$port, :$exclude_pages, :$project_root,
           theme        => ($config<theme>||''),
           themes       => ($config<themes> ~~ Array ?? $config<themes> !! []));

    my IO::Path $layout_dir       = $theme_dir.IO.child('layout');
    my IO::Path $pages_watch_dir  = $project_root.IO.child('pages').child($page_filter)||$project_root.IO.child('pages');
    my IO::Path $pages_dir        = $project_root.IO.child('pages');
    my IO::Path $partials_dir     = $project_root.IO.child('partials');
    my IO::Path $public_dir       = $project_root.IO.child('public');
    my List $template_dirs        = [$pages_watch_dir, $partials_dir, $i18n_dir];
    my List %template_exts        = tt => ['tt'], mustache => ['ms', 'mustache'];
    my Str $template_engine       = $config<template_engine> ∈ %template_exts.keys ?? $config<template_engine> !! 'tt',
    my List $extensions           = [ |%template_exts{$template_engine}, 'html', 'yml'];

    # Confirm all template directories exist
    # before continuing.
    valid-project-folder-structure($template_dirs);

    my Map $config_plus = (
        :host($host),
        :port($port),
        :language($language),
        :no_livereload($no_livereload),
        :project_root($project_root),
        :path($config_file),
        :build_dir($build_dir),
        :themes($themes),
        :themes_dir($themes_dir),
        :assets_dir($assets_dir),
        :theme_dir($theme_dir),
        :layout_dir($layout_dir),
        :pages_watch_dir($pages_watch_dir),
        :pages_dir($pages_dir),
        :exclude_pages($exclude_pages),
        :public_dir($public_dir),
        :partials_dir($partials_dir),
        :i18n_dir($i18n_dir),
        :template_dirs($template_dirs),
        :template_engine($template_engine),
        :template_extensions(%template_exts),
        :extensions($extensions)
    ).Map;

    # We want to stop everything if the project root ~~ $*HOME or
    # the build dir ~~ project root. This would have bad side-effects
    safe-build-dir-check($build_dir.IO, :$project_root);

    # Merged config as output
    return Map.new($config.pairs, $config_plus.pairs);
}

our sub init(
    IO::Path :$config_file  = 'config.yml'.IO, 
    Str      :$project_name = 'New Uzu Project',
    Str      :$url          = 'http://example.com',
    Str      :$language     = 'en',
    Str      :$theme        = 'default'
    --> Bool
) {
    my Map $config = (
        :name($project_name),
        :url($url),
        :language($language),
        :theme($theme)
    ).Map;

    my IO::Path $theme_dir     = "themes".IO.child($theme);
    my List     $template_dirs = (
        "i18n".IO, 
        "pages".IO,
        "partials".IO,
        "public".IO,
        $theme_dir.IO.child('assets')
    );

    # Create project directories
    $template_dirs.map( -> $dir { mkdir $dir });

    # Create placeholder files
    spurt $theme_dir.IO.child("layout.tt"), ""; 
    spurt "pages".IO.child('index.tt'), "";
    spurt "i18n".IO.child("{$language}.yml"), "---\nproject_name: $project_name\n";

    # Write config file
    my Str $config_yaml = S:g /'...'// given save-yaml($config);
    my IO::Path $config_out  = S:g /'~'/$*HOME/ given $config_file;
    return spurt $config_out, $config_yaml;
}
