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
        note "Config file [{$config_file}] not found. Please run uzu init to generate.";
        exit 1;
    }

    try {

        CATCH {
            default {
                note "Invalid config yaml file [{$config_file}]";
                note .Str;
                exit 1;
            }
        }

        my %global_config      = slurp($config_file).&load-yaml when $config_file.IO.f;
        # Normalize themes
        %global_config<themes> = %global_config<themes>.map(-> $theme {
            $theme ~~ Iterable ?? $theme.head !! $theme;
        }).List;

        # Collect non-core variables into :site
        my $core_vars = 'host'|'language'|'port'|'project_root'|'theme'|'exclude_pages'|'exclude'|'pre_command'|'post_command';
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
             :@themes,         # yaml themes:
    IO::Path :$build_dir,      # default build dir
    Int      :$port,           # default port
    List     :$exclude_pages,  # default exclude pages
    IO::Path :$project_root    # project root
) {
    # Always use single theme if yaml `theme:` variable set
    return %{
        "{$theme||'default'}" => %{
            theme_dir      => $themes_dir.IO.child("$theme"||'default'),
            build_dir      => $build_dir,
            port           => $port,
            exclude_pages  => $exclude_pages},
    } when defined $theme and $theme !~~ "";

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
    my %themes;

    # ... otherwise use hash
    for @themes -> $theme {
        
        given $theme {

            # Single theme, $theme = theme name
            when Str {

                # When user passes --theme to cli only configure that theme or skip
                next when $single_theme.defined && $single_theme !~~ $theme;

                my Int $theme_port = $working_port;
                # Increment next port
                ++$working_port;

                %themes{"{$theme||'default'}"} = %{
                    theme_dir      => $themes_dir.IO.child($theme||'default'),
                    build_dir      => $build_dir.IO.child($theme||'default'),
                    port           => $theme_port,
                    exclude_pages  => $exclude_pages
                }
            } 
            
            when Pair {

                my Str  $theme_name    = $theme.key;
                my Hash $theme_config  = $theme.value;
                my IO::Path $theme_dir = $themes_dir.IO.child($theme_name);

                # When user passes --theme to cli only configure that theme or skip
                next when $single_theme.defined && $single_theme !~~ $theme_name;

                do {
                    note "Theme directory [{$theme_name}] does not exist. Skipping.";
                    next;
                } unless $theme_dir.IO.e;

                # Single theme build dir
                my IO::Path $theme_build_dir = do if @themes.elems eq 1 {
                    $theme_config<build_dir>:exists ?? $theme_config<build_dir>.IO !! $build_dir;
                } else { # Mutiple themes build dir
                    my $theme_build_dir = $theme_config<build_dir> ?? $theme_config<build_dir> !! $build_dir.IO.child($theme_name);
                    build-dir-exists @seen_build_dirs, $theme_build_dir;
                    push @seen_build_dirs, $theme_build_dir;
                    safe-build-dir-check $theme_build_dir.IO, :$project_root;
                    $theme_build_dir.IO;
                }

                # Single theme port
                my Int $theme_port = do if @themes.elems eq 1 {
                    $theme_config<port>||$working_port;
                } else {
                    # Multiple themes port
                    $working_port = $theme_config<port> when $theme_config<port> && $theme_config<port> > $working_port;
                    $theme_config<port>||$working_port;
                }

                # Increment next port
                ++$working_port;

                %themes{"{$theme_name}"} = %{
                    theme_dir      => $theme_dir,
                    build_dir      => $theme_build_dir,
                    port           => $theme_port,
                    exclude_pages  => $theme_config<exclude_pages>
                }
            }
        }
    }
    return %themes;
}

our sub from-file(
    IO::Path :$config_file   = 'config.yml'.IO,
    Str      :$page_filter   = '',
    Str      :$single_theme,
    Bool     :$no_livereload = False
) {

    # Gemeral config
    my %_config       = parse-config(config_file => $config_file);
    my $project_root  = "{%_config<project_root>||$*CWD}".subst('~', $*HOME).IO;
    my %config        = %{
        project_root     => $project_root,
        language         => [%_config<language>.flat],

        # Network        
        host                => %_config<host>||'0.0.0.0',
        port                => (%_config<port>:exists ?? %_config<port>.Int !! 3000),

        # Paths
        build_dir           => $project_root.IO.child('build'),
        i18n_dir            => $project_root.IO.child('i18n'),
        themes_dir          => $project_root.IO.child('themes'),
        assets_dir          => $project_root.IO.child('themes').child("{%_config<theme>||'default'}").child('assets'),
        theme_dir           => $project_root.IO.child('themes').child("{%_config<theme>||'default'}"),
        pages_watch_dir     => $project_root.IO.child('pages').child($page_filter)||$project_root.IO.child('pages'),
        pages_dir           => $project_root.IO.child('pages'),
        partials_dir        => $project_root.IO.child('partials'),
        public_dir          => $project_root.IO.child('public'),

        # Misc.
        template_extensions => %{ tt => ['tt'], mustache => ['ms', 'mustache'] },
        exclude_pages       => (%_config<exclude_pages>||[]),
        exclude             => (%_config<exclude>||[]),
        omit_html_ext       => (so %_config<ommit_html_ext>:exists||False),
        no_livereload       => $no_livereload,
        config_file         => $config_file,
        single_theme        => $single_theme,

        # Pre/post build commands
        pre_command         => (%_config<pre_command>||''),
        post_command        => (%_config<post_command>||'')

    }

    # Template / layout
    %config<layout_dir>      = %config<theme_dir>.IO.child('layout');
    %config<template_dirs>   = [
        %config<pages_watch_dir>,
        %config<partials_dir>,
        %config<i18n_dir>
    ];
    %config<template_engine> = ( %_config<template_engine> ∈ %config<template_extensions>.keys ?? %_config<template_engine> !! 'tt' );
    %config<extensions>      = [ |%config<template_extensions>{%config<template_engine>}, 'html', 'yml'];

    # Themes config
    %config<themes> = themes-config(
        # Render single theme? ignore multi config
        single_theme  => %config<single_theme>,
        themes_dir    => %config<themes_dir>,
        build_dir     => %config<build_dir>,
        # Serve port
        port          => %config<port>,
        exclude_pages => %config<exclude_pages>,
        project_root  => %config<project_root>,
        # Single theme default
        theme         => %_config<theme>||'',
        # Mutli themes options
        themes        => %_config<themes>||[],
    );

    # Confirm all template directories exist
    # before continuing.
    valid-project-folder-structure(%config<template_dirs>);

    # We want to stop everything if the project root ~~ $*HOME or
    # the build dir ~~ project root. This would have bad side-effects
    safe-build-dir-check(%config<build_dir>.IO, project_root => %config<project_root>.IO);

    # Merged config as output
    return %config;
}

our sub init(
    IO::Path :$config_file     = 'config.yml'.IO, 
    Str      :$site_name       = 'New Uzu Project',
    Str      :$template_engine = 'mustache',
    Str      :$language        = 'en',
    Str      :$theme           = 'default'
    --> Bool
) {
    my Map %config = (
        :name($site_name),
        :language($language),
        :theme($theme),
        :template_engine($template_engine)
    ).Map;

    my IO::Path $theme_dir     = "themes".IO.child($theme);
    my List     $template_dirs = (
        "i18n".IO, 
        "pages".IO,
        "partials".IO,
        "public".IO,
        $theme_dir.IO.child('assets')
    );

    # Copy template files
    my %templates =
        pages    => ['index'],
        partials => ['footer','head'],
        themes   => ['layout'];

    # Create project directories
    $template_dirs.map( -> $dir { mkdir $dir });

    %templates.kv.map: -> $root, @files {
        for @files -> $file {
            my $target_filename = "{$file}.{$template_engine}";
            my $target_path     =
                $root ~~ 'themes'
                ?? 'default'.IO.child($target_filename)
                !! $target_filename;
            my $source_filename =
                $root ~~ 'themes'
                ?? "{$template_engine}/{$root}/default/{$file}.{$template_engine}"
                !! "{$template_engine}/{$root}/{$file}.{$template_engine}";

            spurt $root.IO.child($target_path), slurp(%?RESOURCES{$source_filename}.IO); 
        }
    }

    # Save default language yaml
    spurt "i18n".IO.child("{$language}.yml"), "---\nsite_name: $site_name\n";

    # Write config file
    my Str %config_yaml     = S:g /'...'// given save-yaml(%config);
    my IO::Path %config_out = S:g /'~'/$*HOME/ given $config_file;
    return spurt %config_out, %config_yaml;
}
