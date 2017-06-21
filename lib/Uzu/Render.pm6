use v6;

use Uzu::Logger;
use Uzu::Utilities;
use YAMLish;

unit module Uzu::Render;

sub templates(
    List     :$exts!,
    IO::Path :$dir!
    --> Seq
) {
    return dir $dir, :test(/:i ^ \w+ '.' |$exts $/);
}

sub build-context(
    IO::Path :$i18n_dir,
    Str      :$language
    --> Hash
) {
    my Str $i18n_file = $i18n_dir.IO.child("$language.yml").path;
    if $i18n_file.IO ~~ :f {
        try {
            CATCH {
                default {
                    note "Invalid i18n yaml file [$i18n_file]";
                }
            }
            return %( %(language => $language), load-yaml slurp($i18n_file) );
        }
    }
    return %( error => "i18n yaml file [$i18n_file] could not be loaded" );
}

sub write-generated-files(
    Hash     $content,
    IO::Path :$build_dir
    --> Bool
) {
    # IO write to disk
    for $content.keys -> $path {
        spurt "$build_dir/$path.html", $content{$path}
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
        my Str $livejs = '<script src="uzu/js/live.js"></script>';
        return $content.subst('</body>', "{$livejs}\n</body>");
    }
    return $content;
}

sub prepare-html-output(
    Hash $context,
    List :$template_dirs,
    Str  :$default_language,
    Str  :$language, 
    Hash :$pages,
    Bool :$no_livereload
    --> Hash
) {
    use Template6;
    my $t6 = Template6.new;

    $template_dirs.map(-> $dir {
        $t6.add-path: $dir
    });

    return gather {
        $pages.keys().map(-> $page_name {

            # Render the page content
            my Str $page_content = $t6.process($page_name, |$context);

            # Append page content to $context
            my %layout_context = %( |$context, %( content => $page_content ) );
            my Str $layout_content = $t6.process('layout', |%layout_context );

            # Default file_name without prefix
            my Str $file_name = 
                html-file-name(
                    page_name        => $page_name,
                    default_language => $default_language, 
                    language         => $language);

            # Return processed HTML
            my Str $processed_html =
                process-livereload(
                    content          => $layout_content,
                    no_livereload    => $no_livereload);

            take $file_name => $processed_html;

        })
    }.Hash;
};

our sub build(
    Map $config,
    ::D :&logger = Uzu::Logger::start()
    --> Bool
) {
    my $assets_dir = $config<assets_dir>;
    my $public_dir = $config<public_dir>;
    my $build_dir  = $config<build_dir>;

    # All available pages
    my List $exts = $config<extensions>;
    my IO::Path @page_templates = templates(exts => $exts, dir => $config<pages_dir>);

    my Str %pages = (@page_templates.map( -> $page { 
                         my Str $page_name = ( split '.', IO::Path.new($page).basename )[0]; 
                         %( $page_name => slurp $page, :r );
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

    # One per language
    await gather {
        $config<language>.map(-> $language { 
            take start {
                logger "Compile templates [$language]";
                build-context(
                    i18n_dir         => $config<i18n_dir>,
                    language         => $language
                ).&prepare-html-output(
                    template_dirs    => $config<template_dirs>,
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

