use v6;

use Uzu::Logger;
use Uzu::Utilities;
use File::Find;
use YAMLish;

unit module Uzu::Render;

sub templates(
    List     :$exts!,
    IO::Path :$dir!
    --> Seq
) {
    sort { $^a.modified < $^b.modified }, find( :$dir, name => /'.' @$exts $/ );
}

sub i18n-files(
    Str      :$language,
    IO::Path :$dir!
    --> Seq
) {
    find :$dir, name => / $language '.yml' $/, type => 'file';
}

sub i18n-from-yaml(
    Str      :$language,
    IO::Path :$i18n_dir
    --> Hash 
) {
    state %i18n;
    map -> $i18n_file {

        return %( error => "i18n yaml file [$i18n_file] could not be loaded" ) unless $i18n_file.IO.f;

        try {

            my %yaml = load-yaml slurp($i18n_file, :r);
            my $key  = $i18n_file.dirname.split('i18n')[1] || $language;
            %i18n{$key}<i18n> = %yaml;

            CATCH {
                default {
                    note "Invalid i18n yaml file [$i18n_file]";
                }
            }
        }

   }, i18n-files(:$language, dir => $i18n_dir);

   return %i18n;
}

sub i18n-context-vars(
    Str      :$language, 
    IO::Path :$path,
    Hash     :$context
) {
    my Str $i18n_key = ($path.IO.path ~~ / .* 'pages' (.*) '.' .*  / ).head.Str;
    return %( |$context,
              i18n => %( |$context{$language}<i18n>, 
                         # Page-specific i18n vars?
                         ( $context{$i18n_key}.defined ?? |$context{$i18n_key}<i18n> !! %() )));
}

sub extract-file-parts(
    IO::Path $path,
    Str      $pages_dir
    --> List
) {
    my $relative_path         = S/ $pages_dir // given $path.IO.path;
    my $file_name             = S/'.tt'|'.mustache'$// given (S/^\/// given $relative_path);
    my ($page_name, $out_ext) = split '.', $file_name;
    my $target_dir            = $relative_path.IO.parent.path;
    return $page_name, ($out_ext||'html'), $target_dir;
}

sub io-runner(
    Channel $queue
    --> Promise
) {
  start {
    $queue.list.map: -> $action {
      last if $action ~~ Str && $action ~~ 'exit';
      # else, run action
      &$action();
    }
  }
}

sub write-generated-file(
    Pair      $content,
    IO::Path :$build_dir
    --> Bool()
) {
    # IO write to disk
    my $page_name  = $content.key;
    my %meta       = $content.values[0];
    my $html       = %meta<html>;
    my $target_dir = $build_dir.IO.child(%meta<target_dir>.IO);
    mkdir $target_dir when !$target_dir.IO.d;
    spurt $build_dir.IO.child("{$page_name}.{%meta<out_ext>}"), $html;
}

sub write-generated-files(
    Hash     $content,
    IO::Path :$build_dir
    --> Bool()
) {
    # IO write to disk
    for kv $content -> $template_name, %meta {
        my $html       = %meta<html>;
        my $target_dir = $build_dir.IO.child(%meta<target_dir>.IO);
        mkdir $target_dir when !$target_dir.IO.d;
        spurt $build_dir.IO.child("{$template_name}.{%meta<out_ext>}"), $html;
    };
}

sub html-file-name(
    Str :$page_name,
    Str :$default_language,
    Str :$language
    --> Str
) {
    return "{$page_name}-{$language}" when $language !~~ $default_language;
    return $page_name;
}

our sub process-livereload(
    Str  :$content,
    Bool :$no_livereload
    --> Str
) {
    unless $no_livereload {
        # Add livejs if live-reload enabled (default)
        my Str $livejs = '<script src="/uzu/js/live.js"></script>';
        return S/'</body>'/$livejs\n<\/body>/ given $content;
    }
    return $content;
}

sub prepare-html-output(
    Str      :$page_name,
    Str      :$default_language,
    Str      :$language,
    Str      :$layout_contents,
    Bool     :$no_livereload,
    IO::Path :$path,
    Str      :$target_dir,
    Str      :$out_ext
    --> Pair
) {
    # Default file_name without prefix
    my Str $file_name = 
        html-file-name
            :$page_name,
            :$default_language, 
            :$language;

    # Return processed HTML
    my Str $html =
        process-livereload
            content          => $layout_contents,
            no_livereload    => $no_livereload;

    return $file_name => %{ 
        :$path,
        :$html,
        :$target_dir,
        :$out_ext
    }
}


sub parse-template(
    IO::Path :$path
    --> List
) {
    # Extract header yaml if available
    try {
        my ($template_yaml, $template_html) = ~<< ( slurp($path, :r) ~~ / ( ^^ '---' .* '---' | ^^ ) (.*) / );
        my %yaml = $template_yaml ?? load-yaml $template_yaml !! %();

        CATCH {
            default {
                note "Invalid template yaml [$path]";
            }
        }

        return $template_html, %yaml;
    }
}

multi sub render(
    'mustache',
    Hash      $context,
    Channel  :$iorunner,
    IO::Path :$build_dir,
    Str      :$layout_template,
    IO::Path :$theme_dir,
    Str      :$default_language,
    Str      :$language, 
    Hash     :$pages,
    Hash     :$partials,
    Hash     :$categories,
    Bool     :$no_livereload
) {
    use Template::Mustache;
    my Any %layout_vars = :$language, |$context{$language};

    for kv $pages -> $page_name, %meta {

        # Append page-specific i18n vars if available
        my Any %page_context = i18n-context-vars path => %meta<path>, :$context, :$language;

        # Render the partials content
        my Any %partials;
        for kv $partials -> $partial_name, %p {
            %partials{$partial_name} = Template::Mustache.render:
                %p<html>, %( |%layout_vars, |%page_context, |%meta<vars>, |%p<vars> );
        };

        # Render the page content
        my Str $page_contents = Template::Mustache.render:
            %meta<html>, %( |%layout_vars, |%page_context, |%meta<vars>, :$categories ), from => [%partials];

        # Append page content to $context
        my Str $layout_contents = do given %meta<out_ext> {
            when 'html' {
                decode-entities Template::Mustache.render:
                    $layout_template,
                    %( |%layout_vars, |%meta<vars>, :$categories, content => $page_contents ),
                    from => [%partials]
            }

            # Do not wrap non-html files with layout
            default { $page_contents  }
        }

        $iorunner.send: {
            prepare-html-output(
                :$page_name,
                :$default_language,
                :$language,
                :$layout_contents,
                :$no_livereload,
                path          => %meta<path>,
                target_dir    => %meta<target_dir>,
                out_ext       => %meta<out_ext>)
            ==> write-generated-file(
                build_dir     => $build_dir);
        }
    };

    $iorunner.send: 'exit';
}

multi sub render(
    'tt',
    Hash      $context,
    Channel  :$iorunner,
    IO::Path :$build_dir,
    Str      :$layout_template,
    IO::Path :$theme_dir,
    Str      :$default_language,
    Str      :$language, 
    Hash     :$pages,
    Hash     :$partials,
    Hash     :$categories,
    Bool     :$no_livereload
) {
    use Template6;
    my Any %layout_vars     = language => $language, |$context{$language};

    for kv $pages -> $page_name, %meta {

        my Template6 $t6 .= new;
        $t6.add-template: 'layout', $layout_template;
        
        # Append page-specific i18n vars if available
        my Any %page_context = i18n-context-vars path => %meta<path>, :$context, :$language;

        # Render the partials content
        for kv $partials -> $partial_name, %p {
            $t6.add-template: "{$partial_name}_", %p<html>;
            $t6.add-template: $partial_name, $t6.process( "{$partial_name}_", |%layout_vars, |%page_context, |%meta<vars>, |%p<vars> );
        };

        # Cache template
        $t6.add-template: "_{$page_name}_", %meta<html>;

        # Render the page content
        my Str $page_contents   = $t6.process: "_{$page_name}_", |%layout_vars, |%page_context, |%meta<vars>, :$categories;

        # Append page content to $context
        my Str $layout_contents = do given %meta<out_ext> {
            when 'html' {
                $t6.process: 'layout', |%layout_vars, |%meta<vars>, :$categories, content => $page_contents;
            }

            # Do not wrap non-html files with layout
            default { $page_contents }
        }

        $iorunner.send: &{
            prepare-html-output(
                :$page_name,
                :$default_language,
                :$language,
                :$layout_contents,
                :$no_livereload,
                path          => %meta<path>,
                target_dir    => %meta<target_dir>,
                out_ext       => %meta<out_ext>)
            ==> write-generated-file(
                build_dir     => $build_dir);
        }
    };

    $iorunner.send: 'exit';

}

our sub build(
    Map $config,
    ::D :&logger = Uzu::Logger::start()
    --> Promise
) {
    my List $exts = $config<template_extensions>{$config<template_engine>};
    my %categories;

    # All available pages
    my Any %pages = map -> $path { 
        next unless $path.IO.f;
        my Str ($page_name, $out_ext, $target_dir) = extract-file-parts($path, $config<pages_dir>.IO.path);
        my Str $page_raw = slurp $path, :r;

        # Extract header yaml if available
        my ($page_html, %page_vars) = parse-template :$path;

        # Append page to categories hash if available
        #with %page_vars<categories> {
        #    await map -> $category {
        #        my $uri            = S/'.tt'|'.mustache'/.html/ given split('pages', $path.path).tail;
        #        my $title          = %page_vars<title>||$uri;
        #        my $category_label = S/'/categories/'// given $category;
        #        push %categories<labels>, { name => $category_label };
        #        push %categories{$category}, { :$title, :$uri };
        #    }, build-category-uri(%page_vars<categories>);
        #}

        %( $page_name => %{
            path       => $path,
            html       => $page_html,
            vars       => %page_vars,
            out_ext    => $out_ext,
            target_dir => $target_dir });

    }, templates(:$exts, dir => $config<pages_dir>);

    # All available partials
    my Any %partials = map -> $path { 
        next unless $path.IO.f;
        my Str $partial_name = ( split '.', IO::Path.new($path).basename )[0]; 
        my Str $partial_raw  = slurp $path, :r;

        # Extract header yaml if available
        my ($partial_html, %partial_vars) = parse-template :$path;

        %( $partial_name => %{
            path => $path,
            html => $partial_html,
            vars => %partial_vars });

    }, templates(exts => $exts, dir => $config<partials_dir>);

    # Clear out build
    logger "Clear old files";
    rm-dir $config<build_dir>;

    # Create build dir
    if !$config<build_dir>.IO.d { 
        logger "Create build directory";
        mkdir $config<build_dir>;
    }

    logger "Copy public, assets";
    map { copy-dir $_, $config<build_dir> }, [$config<public_dir>, $config<assets_dir>];

    # Append nested pages directories
    my @template_dirs = |$config<template_dirs>, |find(dir => $config<pages_dir>, type => 'dir');

    # Append nested i18n directories
    my @i18n_dirs = $config<i18n_dir>, |find(dir => $config<i18n_dir>, type => 'dir');

    my Str $layout_template =
        slurp grep( / 'layout.' @$exts $ /, templates(:$exts, dir => $config<theme_dir>)).head, :r;

    my Channel $iorunner = Channel.new;

    # One per language
    map -> $language { 

        logger "Compile templates [$language]";

        i18n-from-yaml(
            language         => $language,
            i18n_dir         => $config<i18n_dir>)
        ==> render(
            $config<template_engine>,
            iorunner         => $iorunner,
            build_dir        => $config<build_dir>,
            layout_template  => $layout_template,
            theme_dir        => $config<theme_dir>,
            default_language => $config<language>[0],
            language         => $language,
            pages            => %pages,
            partials         => %partials,
            categories       => %categories,
            no_livereload    => $config<no_livereload>);
         
    }, $config<language>;

    await io-runner($iorunner);
    logger "Compile complete";
}
