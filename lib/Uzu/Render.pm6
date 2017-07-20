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

        if $i18n_file.IO ~~ :f {
            try {
                my %yaml = load-yaml slurp($i18n_file, :r);
                CATCH {
                    default {
                        note "Invalid i18n yaml file [$i18n_file]";
                    }
                }

                my $key = $i18n_file.dirname.split('i18n')[1] || $language;
                %i18n{$key}<i18n> = %yaml;
            }
        } else {
            return %( error => "i18n yaml file [$i18n_file] could not be loaded" );
        }
   }

   return %i18n;
}

sub write-generated-files(
    Hash     $content,
    IO::Path :$build_dir
    --> Bool
) {
    # IO write to disk
    for $content.kv -> $template_name, %meta {
        my $file       = %meta<path>.Str.split('pages')[1];
        my $html       = %meta<html>;
        my $target_dir = $build_dir.IO.child($file.IO.dirname);
        mkdir $target_dir;
        spurt $target_dir.IO.child("$template_name.html"), $html;
    };
    return True;
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
    Hash  $context,
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
        $t6.add-path: $dir;
    });

    my %context = language => $language, |$context{$language};
    return gather {
        $pages.kv.map(-> $page_name, %meta {
            
            # Append page-specific i18n vars if available
            my $i18n_key = %meta<path>.IO.path.match( / .* '/pages' (.*) '.' .*  / )[0].Str;
            my %page_context = %context;
            %page_context<i18n> = $context{$language}<i18n>;
            if $context{$i18n_key}.defined {
                for $context{$i18n_key}<i18n>.keys -> $k {
                    %page_context<i18n>{$k} = $context{$i18n_key}<i18n>{$k};
                }
            }

            # Render the page content
            my Str $page_content = $t6.process($page_name, |%page_context );

            # Append page content to $context
            my %layout_context = %( |%context, %( content => $page_content ) );
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

            take $file_name => %{ 
                path => %meta<path>,
                html => $processed_html
            };

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
                ).&prepare-html-output(
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

