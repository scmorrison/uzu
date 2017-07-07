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
    return slurp($config_file).&load-yaml when $config_file.IO.f;
    note "Config file [$config_file] not found. Please run uzu init to generate.";
    exit 1;
}

our sub from-file(
    IO::Path :$config_file   = 'config.yml'.IO,
    Bool     :$no_livereload = False
    --> Map
) {

    # Gemeral config
    my Map  $config         = parse-config(config_file => $config_file);
    my List $language       = [$config<language>];

    # Network
    my Str  $host           = $config<host>||'0.0.0.0';
    my Int  $port           = $config<port>||3000;

    # Paths
    my IO::Path $project_root = "{$config<project_root>||$*CWD}".subst('~', $*HOME).IO;
    my IO::Path $build_dir    = $project_root.IO.child('build');
    my IO::Path $i18n_dir     = $project_root.IO.child('i18n');
    my IO::Path $themes_dir   = $project_root.IO.child('themes');
    my IO::Path $assets_dir   = $project_root.IO.child('themes').child("{$config<defaults><theme>||'default'}").child('assets');
    my IO::Path $layout_dir   = $project_root.IO.child('themes').child("{$config<defaults><theme>||'default'}").child('layout');
    my IO::Path $pages_dir    = $project_root.IO.child('pages');
    my IO::Path $partials_dir = $project_root.IO.child('partials');
    my IO::Path $public_dir   = $project_root.IO.child('public');
    my List $template_dirs  = [$layout_dir, $pages_dir, $partials_dir, $i18n_dir];
    my List $extensions     = ['tt', 'html', 'yml'];

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
        :themes_dir($themes_dir),
        :assets_dir($assets_dir),
        :layout_dir($layout_dir),
        :pages_dir($pages_dir),
        :public_dir($public_dir),
        :partials_dir($partials_dir),
        :i18n_dir($i18n_dir),
        :template_dirs($template_dirs),
        :extensions($extensions)
    ).Map;

    # We want to stop everything if the project root ~~ $*HOME or
    # the build dir ~~ project root. This would have bad side-effects
    if $build_dir.IO ~~ $*HOME.IO|$project_root.IO {
        note "Build directory [{$build_dir}] cannot be {$*HOME} or project root [{$project_root}].";
        exit(1);
    }

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

    my IO::Path $theme_dir      = "themes".IO.child($theme);
    my List     $template_dirs = (
        "i18n".IO, 
        "pages".IO,
        "partials".IO,
        "public".IO,
        $theme_dir.IO.child('layout'),
        $theme_dir.IO.child($theme).child('assets')
    );

    # Create project directories
    $template_dirs.map( -> $dir { mkdir $dir });

    # Write config file
    my Str $config_yaml = S:g /'...'// given save-yaml($config);
    my IO::Path $config_out  = S:g /'~'/$*HOME/ given $config_file;
    return spurt $config_out, $config_yaml;
}
