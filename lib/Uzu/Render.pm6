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
    return find(dir => $dir, name => /'.' |$exts $/).Seq;
}

sub i18n-files(
    Str      :$language,
    IO::Path :$dir!
    --> Seq
) {
    find(dir => $dir, name => / $language '.yml' /, type => 'file').Seq;
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
    return $page_html, $page_yaml ?? load-yaml $page_yaml !! %{};
}

multi sub render(
    'mustache',
    Hash  $context,
    List :$template_dirs,
    Str  :$default_language,
    Str  :$language, 
    Hash :$pages,
    Hash :$categories,
    Bool :$no_livereload
    --> Hash()
) {

    use Template::Mustache;

    my Any %layout_vars = language => $language, |$context{$language};
    return gather {
        map -> $page_name, %meta {
            
            # Append page-specific i18n vars if available
            my Any %page_context = i18n-context-vars path => %meta<path>, :$context, :$language;

            # Render the page content
            my Str $page_contents = Template::Mustache.render:
                %meta<html>, %( |%page_context, |%meta<vars>, category => $categories ), from => $template_dirs;

            # Append page content to $context
            my Str $layout_contents =
                decode-entities Template::Mustache.render:
                    'layout',
                    %( |%layout_vars, |%meta<vars>, categories => $categories, content => $page_contents ),
                    from => $template_dirs;

            take prepare-html-output
                :$page_name,
                :$default_language,
                :$language,
                :$layout_contents,
                :$no_livereload,
                path => %meta<path>
        }, kv $pages;
    }
}

multi sub render(
    'tt',
    Hash  $context,
    List :$template_dirs,
    Str  :$default_language,
    Str  :$language, 
    Hash :$pages,
    Hash :$categories,
    Bool :$no_livereload
    --> Hash()
) {

    use Template6;
    my Template6 $t6 .= new;
    map { $t6.add-path: $_ }, @$template_dirs;

    my Any %layout_vars = language => $language, |$context{$language};
    return gather {
        $pages.kv.map: -> $page_name, %meta {
            
            # Append page-specific i18n vars if available
            my Any %page_context = i18n-context-vars path => %meta<path>, :$context, :$language;

            # Cache template
            $t6.add-template: "_{$page_name}_str", %meta<html>;

            # Render the page content
            my Str $page_contents   = $t6.process: "_{$page_name}_str", |%page_context, |%meta<vars>, categories => $categories;

            # Append page content to $context
            my Str $layout_contents = $t6.process: 
                'layout', |%layout_vars, |%meta<vars>, categories => $categories, content => $page_contents;

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
    my ($assets_dir, $public_dir, $build_dir) = $config<assets_dir public_dir build_dir>;

    # All available pages
    my List $exts = $config<template_extensions>{$config<template_engine>};
    my IO::Path @page_templates = templates(exts => $exts, dir => $config<pages_dir>);

    my %categories;

    my %pages = map -> $path { 
        my Str $page_name = ( split '.', IO::Path.new($path).basename )[0]; 
        next unless $path.IO.f;
        my $page_raw = slurp($path, :r);

        # Extract header yaml if available
        my ($page_html, %page_vars) = parse-template path => $path;

        # Append page to categories hash if available
        with %page_vars<categories> {
            await map -> $category {
                my $uri            = S/'.tt'|'.mustache'/.html/ given split('pages', $path.path).tail;
                my $title          = %page_vars<title>||$uri;
                my $category_label = S/'/categories/'// given $category;
                push %categories<labels>, { name => $category_label };
                push %categories{$category}, { :$title, :$uri };
            }, build-category-uri(%page_vars<categories>);
        }

        %( $page_name => %{ path => $path, html => $page_html, vars => %page_vars } );
    }, @page_templates;

    # Clear out build
    logger "Clear old files";
    rm-dir $build_dir;

    # Create build dir
    if !$build_dir.IO.d { 
        logger "Create build directory";
        mkdir $build_dir;
    }

    logger "Copy public, assets";
    map { copy-dir $_, $build_dir }, [$public_dir, $assets_dir];

    # Append nested pages directories
    my @template_dirs = |$config<template_dirs>, |find(dir => $config<pages_dir>, type => 'dir');

    # Append nested i18n directories
    my @i18n_dirs = $config<i18n_dir>, |find(dir => $config<i18n_dir>, type => 'dir');

    # One per language
    await gather {
        map -> $language { 
            take start {
                logger "Compile templates [$language]";
                i18n-from-yaml(
                    language         => $language,
                    i18n_dir         => $config<i18n_dir>)
                ==> render(
                    $config<template_engine>,
                    template_dirs    => @template_dirs,
                    default_language => $config<language>[0],
                    language         => $language,
                    pages            => %pages,
                    categories       => %categories,
                    no_livereload    => $config<no_livereload>)
                ==> write-generated-files(
                    build_dir        => $build_dir);
            }
        }, $config<language>;
    }

    logger "Compile complete";
}

