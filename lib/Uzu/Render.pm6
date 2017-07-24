use v6.c;

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
    return find(dir => $dir, name => /'.' |$exts/).Seq;
}

sub i18n-files(
    Str      :$language,
    IO::Path :$dir!
    --> Seq
) {
    find(dir => $dir, name => / $language '.yml' /, type => 'file').Seq;
}

sub i18n-from-yaml(
    IO::Path :$i18n_dir,
    Str      :$language
    --> Hash 
) {
    state %i18n;

    i18n-files(:$language, dir => $i18n_dir).map: -> $i18n_file {

        return %( error => "i18n yaml file [$i18n_file] could not be loaded" ) unless $i18n_file.IO.f;

        try {

            my %yaml = load-yaml slurp($i18n_file, :r);
            my $key = $i18n_file.dirname.split('i18n')[1] || $language;
            %i18n{$key}<i18n> = %yaml;

            CATCH {
                default {
                    note "Invalid i18n yaml file [$i18n_file]";
                }
            }
        }
   }

   return %i18n;
}

sub i18n-context-vars(
    Hash     :$context,
    Str      :$language, 
    IO::Path :$path
) {
    my Str $i18n_key = ( $path.IO.path ~~ / .* 'pages' (.*) '.' .*  / ).head.Str;
    return %( |$context,
              i18n => %( |$context{$language}<i18n>, 
                         # Page-specific i18n vars?
                         ( $context{$i18n_key}.defined ?? |$context{$i18n_key}<i18n> !! %() )));
}


sub write-generated-files(
    Hash     $content,
    IO::Path :$build_dir
    --> Bool()
) {
    # IO write to disk
    for $content.kv -> $template_name, %meta {
        my $file       = %meta<path>.Str.split('pages')[1];
        my $html       = %meta<html>;
        my $target_dir = $build_dir.IO.child($file.IO.dirname);
        mkdir $target_dir;
        spurt $target_dir.IO.child("$template_name.html"), $html;
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
        return $content.subst('</body>', "{$livejs}\n</body>");
    }
    return $content;
}

sub prepare-html-output(
    Str      :$page_name,
    Str      :$default_language,
    Str      :$language,
    Str      :$layout_contents,
    Bool     :$no_livereload,
    IO::Path :$path
    --> Pair
) {
    # Default file_name without prefix
    my Str $file_name = 
        html-file-name
            page_name        => $page_name,
            default_language => $default_language, 
            language         => $language;

    # Return processed HTML
    my Str $processed_html =
        process-livereload
            content          => $layout_contents,
            no_livereload    => $no_livereload;

    return $file_name => %{ 
        path => $path,
        html => $processed_html
    }
}


sub parse-template(
    IO::Path :$path
    --> List
) {
    # Extract header yaml if available
    my ($page_yaml, $page_html) = ~<< ( slurp($path, :r) ~~ / ( ^^ '---' .* '---' | ^^ ) (.*) / );
    my %page_vars = $page_yaml ?? load-yaml $page_yaml !! %{};
    return $page_html, %page_vars;
}

sub render-mustache(
    Hash  $context,
    List :$template_dirs,
    Str  :$default_language,
    Str  :$language, 
    Hash :$pages,
    Bool :$no_livereload
    --> Hash()
) {

    use Template::Mustache;

    my Any %layout_vars = language => $language, |$context{$language};
    return gather {
        $pages.kv.map: -> $page_name, %meta {
            
            # Append page-specific i18n vars if available
            my Any %page_context = i18n-context-vars path => %meta<path>, :$context, :$language;

            # Extract header yaml if available
            my ($page_html, %page_vars) = parse-template path => %meta<path>;

            # Render the page content
            my Str $page_contents   = Template::Mustache.render:
                $page_html, %( |%page_context, |%page_vars ), from => $template_dirs;

            # Append page content to $context
            my Str $layout_contents =
                decode-entities Template::Mustache.render:
                    'layout',
                    %( |%layout_vars, |%page_vars, content => $page_contents ),
                    from => $template_dirs;

            take prepare-html-output
                :$page_name,
                :$default_language,
                :$language,
                :$layout_contents,
                :$no_livereload,
                path => %meta<path>
        }
    }
}

sub render-tt(
    Hash  $context,
    List :$template_dirs,
    Str  :$default_language,
    Str  :$language, 
    Hash :$pages,
    Bool :$no_livereload
    --> Hash()
) {

    use Template6;
    my Template6 $t6 .= new;
    $template_dirs.map: { $t6.add-path: $_ };

    my Any %layout_vars = language => $language, |$context{$language};
    return gather {
        $pages.kv.map: -> $page_name, %meta {
            
            # Append page-specific i18n vars if available
            my Any %page_context = i18n-context-vars path => %meta<path>, :$context, :$language;

            # Extract header yaml if available
            my ($page_html, %page_vars) = parse-template path => %meta<path>;

            # Cache template
            $t6.add-template: "_{$page_name}_str", $page_html;

            # Render the page content
            my Str $page_contents   = $t6.process: "_{$page_name}_str", |%page_context, |%page_vars;

            # Append page content to $context
            my Str $layout_contents = $t6.process: 
                'layout', |%layout_vars, |%page_vars, content => $page_contents;

            take prepare-html-output
                :$page_name,
                :$default_language,
                :$language,
                :$layout_contents,
                :$no_livereload,
                path => %meta<path>
        }
    }
}

our sub build(
    Map $config,
    ::D :&logger = Uzu::Logger::start()
    --> Bool
) {
    my $assets_dir = $config<assets_dir>;
    my $public_dir = $config<public_dir>;
    my $build_dir  = $config<build_dir>;

    # All available pages
    my List $exts = $config<template_exts>{$config<template_engine>};
    my IO::Path @page_templates = templates(exts => $exts, dir => $config<pages_dir>);

    my %pages = (@page_templates.map( -> $page { 
        my Str $page_name = ( split '.', IO::Path.new($page).basename )[0]; 
        %( $page_name => %{ path => $page, html => slurp($page, :r) } );
    }));

    # Clear out build
    logger "Clear old files";
    rm-dir $build_dir;

    # Create build dir
    if !$build_dir.IO.d { 
        logger "Create build directory";
        mkdir $build_dir;
    }

    logger "Copy public, assets";
    [$public_dir, $assets_dir].map: { copy-dir $_, $build_dir };

    # Append nested pages directories
    my @template_dirs = |$config<template_dirs>, |find(dir => $config<pages_dir>, type => 'dir');

    # Append nested i18n directories
    my @i18n_dirs = $config<i18n_dir>, |find(dir => $config<i18n_dir>, type => 'dir');

    # One per language
    await gather {
        $config<language>.map(-> $language { 
            take start {
                logger "Compile templates [$language]";
                i18n-from-yaml(
                    i18n_dir        => $config<i18n_dir>,
                    language         => $language
                ).&::("render-{$config<template_engine>}")(
                    template_dirs    => @template_dirs,
                    default_language => $config<language>[0],
                    language         => $language,
                    pages            => %pages,
                    no_livereload    => $config<no_livereload>
                ).&write-generated-files(
                    build_dir        => $build_dir);
            }
        });
    }

    logger "Compile complete";
}

