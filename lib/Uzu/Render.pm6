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
    find(dir => $dir, name => /'.' @$exts $/);
}

sub i18n-files(
    Str      :$language,
    IO::Path :$dir!
    --> Seq
) {
    find(dir => $dir, name => / $language '.yml' $/, type => 'file');
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
    my ($page_name, $out_ext) = split('.', $file_name);
    my $target_dir            = $relative_path.IO.parent.path;
    return $page_name, ($out_ext||'html'), $target_dir;
}


sub write-generated-files(
    Hash     $content,
    IO::Path :$build_dir
    --> Bool()
) {
    # IO write to disk
    my Promise @write_queue;
    map -> $template_name, %meta {
        push @write_queue, start {
            my $html       = %meta<html>;
            my $target_dir = $build_dir.IO.child(%meta<target_dir>.IO);
            mkdir $target_dir;
            spurt $build_dir.IO.child("{$template_name}.{%meta<out_ext>}"), $html;
        }
    }, kv $content;
    await @write_queue;
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
    IO::Path :$path,
    Str      :$target_dir,
    Str      :$out_ext
    --> Pair
) {
    # Default file_name without prefix
    my Str $file_name = 
        html-file-name
            page_name        => $page_name,
            default_language => $default_language, 
            language         => $language;

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
    IO::Path :$theme_dir,
    Str      :$default_language,
    Str      :$language, 
    Hash     :$pages,
    Hash     :$partials,
    Hash     :$categories,
    Bool     :$no_livereload
    --> Hash()
) {

    use Template::Mustache;
    my Str $layout_template = slurp grep( / 'layout.mustache' $ /, templates(exts => ['mustache'], dir => $theme_dir) )[0], :r;
    my Any %layout_vars     = language => $language, |$context{$language};

    my Promise @page_queue;
    map -> $page_name, %meta {
        push @page_queue, start {

            # Append page-specific i18n vars if available
            my Any %page_context = i18n-context-vars path => %meta<path>, :$context, :$language;

            # Render the partials content
            my Promise @partials_queue;
            map -> $partial_name, %p {
                push @partials_queue, start {
                    $partial_name => Template::Mustache.render: %p<html>, %( |%layout_vars, |%page_context, |%meta<vars>, |%p<vars> );
                }
            }, kv $partials;
            await Promise.allof: @partials_queue;
            my Any %partials = @partials_queue».result;

            # Render the page content
            my Str $page_contents = Template::Mustache.render:
                %meta<html>, %( |%layout_vars, |%page_context, |%meta<vars>, category => $categories ), from => [%partials];

            # Append page content to $context
            my Str $layout_contents = do given %meta<out_ext> {
                when 'html' {
                    decode-entities Template::Mustache.render:
                        $layout_template,
                        %( |%layout_vars, |%meta<vars>, categories => $categories, content => $page_contents ),
                        from => [%partials]
                }

                # Do not wrap non-html files with layout
                default { $page_contents  }
            }

            prepare-html-output
                :$page_name,
                :$default_language,
                :$language,
                :$layout_contents,
                :$no_livereload,
                path => %meta<path>,
                target_dir => %meta<target_dir>,
                out_ext    => %meta<out_ext>;
        }
    }, kv $pages;

    return @page_queue».result;
}

multi sub render(
    'tt',
    Hash      $context,
    IO::Path :$theme_dir,
    Str      :$default_language,
    Str      :$language, 
    Hash     :$pages,
    Hash     :$partials,
    Hash     :$categories,
    Bool     :$no_livereload
    --> Hash()
) {

    use Template6;

    my Str $layout_template = slurp grep( / 'layout.tt' $ /, templates(exts => ['tt'], dir => $theme_dir) )[0], :r;
    my Any %layout_vars     = language => $language, |$context{$language};

    my Promise @page_queue;
    $pages.kv.map: -> $page_name, %meta {
        push @page_queue, start {

            my Template6 $t6 .= new;
            $t6.add-template: 'layout', $layout_template;
            
            # Append page-specific i18n vars if available
            my Any %page_context = i18n-context-vars path => %meta<path>, :$context, :$language;

            # Render the partials content
            my Promise @partials_queue;
            map -> $partial_name, %p {
                push @partials_queue, start {
                    $t6.add-template: "{$partial_name}_", %p<html>;
                    $t6.add-template: $partial_name, $t6.process( "{$partial_name}_", |%layout_vars, |%page_context, |%meta<vars>, |%p<vars> );
                }
            }, kv $partials;
            await Promise.allof: @partials_queue;

            # Cache template
            $t6.add-template: "_{$page_name}_", %meta<html>;

            # Render the page content
            my Str $page_contents   = $t6.process: "_{$page_name}_", |%layout_vars, |%page_context, |%meta<vars>, categories => $categories;

            # Append page content to $context
            my Str $layout_contents = do given %meta<out_ext> {
                when 'html' {
                    $t6.process: 'layout', |%layout_vars, |%meta<vars>, categories => $categories, content => $page_contents;
                }

                # Do not wrap non-html files with layout
                default { $page_contents  }
            }

            prepare-html-output
                :$page_name,
                :$default_language,
                :$language,
                :$layout_contents,
                :$no_livereload,
                path       => %meta<path>,
                target_dir => %meta<target_dir>,
                out_ext    => %meta<out_ext>;
        }
    }

    return @page_queue».result;
}

our sub build(
    Map $config,
    ::D :&logger = Uzu::Logger::start()
    --> Bool
) {
    my List $exts = $config<template_extensions>{$config<template_engine>};
    my %categories;

    # All available pages
    my %pages = map -> $path { 

        my Str ($page_name, $out_ext, $target_dir) = extract-file-parts($path, $config<pages_dir>.IO.path);
        next unless $path.IO.f;
        my $page_raw = slurp $path, :r;

        # Extract header yaml if available
        my ($page_html, %page_vars) = parse-template path => $path;

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

        %( $page_name => %{ path => $path, html => $page_html, vars => %page_vars, out_ext => $out_ext, target_dir => $target_dir } );
    }, templates(exts => $exts, dir => $config<pages_dir>);

    # All available partials
    my %partials = map -> $path { 
        my Str $partial_name = ( split '.', IO::Path.new($path).basename )[0]; 
        next unless $path.IO.f;
        my $partial_raw = slurp($path, :r);

        # Extract header yaml if available
        my ($partial_html, %partial_vars) = parse-template path => $path;

        %( $partial_name => %{ path => $path, html => $partial_html, vars => %partial_vars } );
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

    # One per language
    my Promise @language_queue;
    map -> $language { 
            push @language_queue, start {
                logger "Compile templates [$language]";
                i18n-from-yaml(
                    language         => $language,
                    i18n_dir         => $config<i18n_dir>)
                ==> render(
                    $config<template_engine>,
                    theme_dir        => $config<theme_dir>,
                    default_language => $config<language>[0],
                    language         => $language,
                    pages            => %pages,
                    partials         => %partials,
                    categories       => %categories,
                    no_livereload    => $config<no_livereload>)
                ==> write-generated-files(
                    build_dir        => $config<build_dir>);
            }
    }, $config<language>;
    await @language_queue;

    logger "Compile complete";
}

