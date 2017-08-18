use v6;

use Uzu::Logger;
use Uzu::Utilities;
use File::Find;
use YAMLish;
use Template6;
use Template::Mustache;

unit module Uzu::Render;

sub templates(
    List     :$exts!,
    IO::Path :$dir!
    --> Seq
) {
    find( :$dir, name => /'.' @$exts $/ );
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
    IO::Path :$i18n_dir,
    ::D :&logger,
    --> Hash 
) {
    
    state %i18n = %();

    map -> $i18n_file {

        logger "i18n yaml file [$i18n_file] could not be loaded" unless $i18n_file.IO.f;

        try {

            my %yaml = load-yaml slurp($i18n_file, :r);
            my $key  = $i18n_file.dirname.split('i18n')[1] || $language;
            %i18n{$key}<i18n>     = %yaml;
            %i18n{$key}<modified> = $i18n_file.modified;

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

sub html-file-name(
    Str :$page_name,
    Str :$default_language,
    Str :$language
    --> Str
) {
    return "{$page_name}-{$language}" when $language !~~ $default_language;
    return $page_name;
}

sub page-uri(
    Str :$page_name,
    Str :$out_ext,
    Str :$default_language,
    Str :$language,
    Str :$i18n_format = 'default'
    --> Str
) {
    return do given $i18n_format {
        when 'subfolder' {
            "/{$language}/{$page_name}.{$out_ext}";
        }
        default {
            '/' ~ html-file-name(:$page_name, :$default_language, :$language) ~ ".{$out_ext}";
        }
    }
}

sub linked-pages(
    Str  :$base_page,
    Hash :$page_vars,
    Hash :$site_index,
    Str  :$default_language,
    Str  :$language,
    Str  :$i18n_format = 'default',
    ::D  :&logger
    --> Hash
) {
    my %linked_pages;
    for $page_vars{grep { / '_pages' $/ }, keys $page_vars}:kv -> $block_key, @pages {
        for @pages -> %vars {
            my $key  = %vars<page>;
            my $url = ($key ~~ / '://' / || !$site_index{$key})
                ?? $key
                !! page-uri page_name => $key, :$default_language, :$language, out_ext => $site_index{$key}<out_ext>;

            logger "Broken link in template [$base_page]: page [$key] referenced in [$block_key] not found" when $key !~~ /'://'/ && !$site_index{$key};

            push %linked_pages{$block_key}, grep({ .value }, [
                |$site_index{$key}.Hash,
                # use the variables defined in the _pages block if set
                page     => $key,
                url      => $url,
                title    => $site_index{$key}<title>    ||%vars<title>,
                author   => $site_index{$key}<author>   ||%vars<author>||'',
                date     => $site_index{$key}<date>     ||'',
                modified => $site_index{$key}<modified>
            ]).Hash;
        }
    }

    return %linked_pages;
}

sub linked-page-timestamps(
    Hash $pages
    --> List
) {
    |grep { .defined }, flat map({ .values>><modified> }, values $pages);
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

our sub process-livereload(
    Str  :$content,
    Bool :$no_livereload
    --> Str
) {
    unless $no_livereload {
        # Add livejs if live-reload enabled (default)
        my Str $livejs = '<script src="/uzu/js/live.js"></script>';
        if $content ~~ /'</body>'/ {
            return S/'</body>'/$livejs\n<\/body>/ given $content;
        } else {
            return $content  ~ "\n$livejs";
        }
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
        my ($template_yaml, $template_html) = ~<< ( slurp($path, :r) ~~ / ( ^^ '---' .* '---' | ^^ ) [\v]? (.*) / );
        my %yaml = $template_yaml ?? load-yaml $template_yaml !! %();

        CATCH {
            default {
                note "Invalid template yaml [$path]";
            }
        }

        return $template_html, %yaml;
    }
}

sub build-partials-hash(
    IO::Path :$source,
    List     :$exts
) {
    map -> $path { 
        next unless $path.IO.f;
        my Str ($partial_name, $out_ext, $target_dir) = extract-file-parts($path, $source.IO.path);

        # Extract header yaml if available
        my ($partial_html, %partial_vars) = parse-template :$path;

        %( $partial_name => %{
            path       => $path,
            html       => $partial_html,
            vars       => %partial_vars,
            out_ext    => $out_ext,
            target_dir => $target_dir,
            modified   => $path.modified });

    }, templates(exts => $exts, dir => $source);
}

multi sub partial-names(
    'mustache',
    Str $template
    --> List
) {
    ~<< ( $template ~~ m:g/ '{{>' \h* <( \N*? )> \h* '}}' / );
}

multi sub partial-names(
    'tt',
    Str $template
    --> List
) {
    ~<< ( $template ~~ m:g/ '[% INCLUDE' \h* '"' <( \N*? )> '"' \h* '%]' / );
}

sub embedded-partials(
    Str   :$template_engine,
    Hash  :$partials_all,
    Hash  :$embedded_partials    is copy,
    Array :$partial_keys,
    Hash  :$context,
    List  :$modified_timestamps  is copy = [],
    List  :$partial_render_queue is copy = [],
    :$t6
    --> List
) {

    # Prerender any embedded partials
    for $partials_all{|@$partial_keys}:kv -> $partial_name, %partial {
        my @partial_keys = partial-names($template_engine, %partial<html>);
        for @partial_keys -> $embedded_partial_name {

            my %context = |$context, |%partial<vars>, |$partials_all{$embedded_partial_name}<vars>;

            ($modified_timestamps, $partial_render_queue, $embedded_partials) =
                embedded-partials
                   :$template_engine,
                   :$partials_all,
                   :$embedded_partials,
                   :@partial_keys,
                   :%context,
                   :$modified_timestamps,
                   :$partial_render_queue,
                   t6 => $t6||'';

            push $modified_timestamps, $partials_all{$embedded_partial_name}<modified>;
            push $partial_render_queue, &{
                given $template_engine {
                    when 'mustache' {
                        $embedded_partials{$embedded_partial_name} =
                            decode-entities render-template
                                'mustache',
                                 context  => %context,
                                 content  => $partials_all{$embedded_partial_name}<html>,
                                 from     => [$embedded_partials];
                    }
                    when 'tt' {
                        render-template
                            'tt',
                             context       => %context,
                             template_name => $embedded_partial_name,
                             content       => $partials_all{$embedded_partial_name}<html>,
                             t6            => $t6;
                    }
                }
            }
        }
    }

    return [$modified_timestamps, $partial_render_queue, $embedded_partials];
}


multi sub render-template(
    'mustache',
    Hash  :$context,
    Str   :$content,
    Array :$from = []
) {
      Template::Mustache.render: $content, $context, from => $from;
}

multi sub render-template(
    'tt',
    Hash      :$context,
    Str       :$template_name,
    Str       :$content,
    Template6 :$t6
) {
    if $content && $context {
        $t6.add-template: "{$template_name}_", $content;
        $t6.add-template: $template_name, $t6.process("{$template_name}_", |$context);
    } elsif !$context {
        $t6.add-template: $template_name, $content;
    } else {
        $t6.add-template: $template_name, $t6.process($template_name, |$context);
    }
}

multi sub render(
    Hash      $context,
    Str      :$template_engine,
    Channel  :$iorunner,
    IO::Path :$build_dir,
    Str      :$layout_template,
    Numeric  :$layout_modified,
    Str      :$theme,
    IO::Path :$theme_dir,
    Str      :$default_language,
    Str      :$language, 
    Hash     :$pages,
    Hash     :$partials_all,
    Hash     :$site_index,
    Bool     :$no_livereload,
    ::D      :&logger
) {

    my Any %layout_vars  = :$language, "lang_{$language}" => True, |$context{$language}, "theme_{$theme}" => True;
    my @layout_partials  = partial-names $template_engine, $layout_template;
    for $pages.sort({ $^a.values[0]<modified> < $^b.values[0]<modified> }) -> $page {

        my Str $page_name = $page.key;
        my Any %page      = $page.values[0];
        my @page_partials = partial-names $template_engine, %page<html>;
        my Bool $nolayout = %page<vars><nolayout>.defined || $layout_template ~~ '';

        # When was this page last rendered?
        my $last_render_time = "{$build_dir}/{$page_name}.{%page<out_ext>}".IO.modified||0;

        my Template6 $t6 .= new when $template_engine ~~ 'tt';
        with $t6 {
            render-template(
               'tt',
                template_name => 'layout',
                content       => $layout_template,
                t6            => $t6
            ) unless $nolayout;
        }
        
        # Capture i18n, template, layout, and partial modified timestamps
        my @modified_timestamps = [$layout_modified, %page<modified>];
        my @partial_render_queue;

        # i18n file timestamps
        push @modified_timestamps, |($context.map: { $_.values[0]<modified> });

        # Append page-specific i18n vars if available
        my Any %i18n_vars = i18n-context-vars path => %page<path>, :$context, :$language;

        # Prepare page links from *_pages yaml blocks
        my %linked_pages = linked-pages
            base_page => $page_name,
            page_vars => %page<vars>,
            :$site_index,
            :$default_language,
            :$language,
            :&logger;

        # Linked pages file timestamps
        push @modified_timestamps, linked-page-timestamps %linked_pages;

        my Any %partials = %() when $template_engine ~~ 'mustache';

        # Prepare embedded partials
        my %context =
            |($nolayout ?? %() !! %layout_vars),
            |%i18n_vars,
            |%page<vars>,
            |%linked_pages;

        my ($modified_timestamps, $partial_render_queue) =
             embedded-partials
                template_engine      => $template_engine,
                partials_all         => $partials_all,
                embedded_partials    => %partials,
                partial_keys         => [|@layout_partials, |@page_partials],
                context              => %context,
                modified_timestamps  => @modified_timestamps,
                partial_render_queue => @partial_render_queue,
                t6 => $t6||'';

        @modified_timestamps  = @$modified_timestamps;
        @partial_render_queue = @$partial_render_queue;
        
        # Render top-level partials content
        for $partials_all{|@page_partials, |@layout_partials}:kv -> $partial_name, %partial {
            my %context = 
                |($nolayout ?? %() !! %layout_vars),
                |%i18n_vars,
                |%page<vars>,
                |%partial<vars>,
                |%linked_pages;

            push @modified_timestamps, %partial<modified>;
            push @partial_render_queue, &{
                given $template_engine {
                    when 'mustache' {
                        %partials{$partial_name} =
                            decode-entities render-template
                               'mustache',
                                context  => %context,
                                content  => %partial<html>,
                                from     => [%partials];
                    }
                    when 'tt' {
                        render-template
                            'tt',
                             context       => %context,
                             template_name => $partial_name,
                             content       => %partial<html>,
                             t6            => $t6;
                    }
                }
            }
        }

        # Skip rendering if layout, page, or partial templates
        # have not been modified
        next when max(@modified_timestamps) < $last_render_time;

        $iorunner.send: &{

            # Continue... render partials
            @partial_render_queue>>.();

            my %context =
                |($nolayout ?? %() !! %layout_vars),
                |%i18n_vars,
                |%page<vars>,
                |%linked_pages,
                :$site_index;

            # Render the page content
            my Str $page_contents = do given $template_engine {
                when 'mustache' {
                    render-template
                       'mustache',
                        context  => %context,
                        content  => %page<html>,
                        from     => [%partials];
                }
                when 'tt' {
                    # Cache template
                    render-template
                        'tt',
                         template_name => "{$page_name}_",
                         content       => %page<html>,
                         t6            => $t6;
                    render-template
                        'tt',
                         template_name => "{$page_name}_",
                         context       => %context,
                         t6            => $t6;
                }
            }

            logger "No content found for page [$page_name] " when $page_contents ~~ '';

            # Append page content to $context
            my Str $layout_contents = do given %page<out_ext> {
                my %context = 
                    |%layout_vars,
                    |%page<vars>,
                    |%linked_pages,
                    :$site_index,
                    content => $page_contents;

                when 'html' { 
                    $nolayout
                    ?? $page_contents
                    !! do given $template_engine {
                        when 'mustache' {
                            decode-entities render-template
                               'mustache',
                                context  => %context,
                                content  => $layout_template,
                                from     => [%partials];
                        }
                        when 'tt' {
                            render-template
                                'tt',
                                 context       => %( |%context ),
                                 template_name => 'layout',
                                 t6            => $t6;
                        }
                    }
                }

                # Do not wrap non-html files with layout
                default { $page_contents }
            }

            prepare-html-output(
                :$page_name,
                :$default_language,
                :$language,
                :$layout_contents,
                :$no_livereload,
                path          => %page<path>,
                target_dir    => %page<target_dir>,
                out_ext       => %page<out_ext>)
            ==> write-generated-file(
                build_dir     => $build_dir);

        }
    }
}
our sub build(
    Map $config,
    ::D :&logger = Uzu::Logger::start()
    --> Promise
) {
    my List $exts = $config<template_extensions>{$config<template_engine>};

    # Capture page meta
    # data for related,
    # categories, and sitemaps
    my %site_index;

    # All available pages
    my Any %pages = map -> $path { 
        next unless $path.IO.f;
        my Str ($page_name, $out_ext, $target_dir) = extract-file-parts($path, $config<pages_dir>.IO.path);

        # Extract header yaml if available
        my ($page_html, %page_vars)  = parse-template :$path;

        # Add to site index
        %site_index{$page_name}           = %page_vars;
        %site_index{$page_name}<modified> = $path.modified;
        %site_index{$page_name}<out_ext>  = $out_ext;

        # Append page to categories hash if available
        #with %page_vars<categories> {
        #    map -> $category {
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
            target_dir => $target_dir,
            modified   => $path.modified });

    }, templates(:$exts, dir => $config<pages_dir>);

    # All available partials
    my Any %partials       = build-partials-hash source => $config<partials_dir>, :$exts;
    my Any %theme_partials =
        $config<theme_dir>.IO.child('partials').IO.d
        ?? build-partials-hash source => $config<theme_dir>.IO.child('partials'), :$exts !! %();

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

    my IO::Path $layout_path = grep( / 'layout.' @$exts $ /, templates(:$exts, dir => $config<theme_dir>)).head;
    my Str $layout_template  = $layout_path.defined ?? slurp $layout_path !! '';

    my Channel $iorunner .= new;
    my Promise $iorunner_manager = io-runner($iorunner);

    # One per language
    map -> $language { 

        logger "Compile templates [$language]";

        i18n-from-yaml(
            language         => $language,
            i18n_dir         => $config<i18n_dir>,
            logger           => &logger)
        ==> render(
            template_engine  => $config<template_engine>,
            iorunner         => $iorunner,
            build_dir        => $config<build_dir>,
            theme            => $config<theme>,
            layout_template  => $layout_template,
            layout_modified  => ($layout_path.defined ?? $layout_path.modified !! 0),
            theme_dir        => $config<theme_dir>,
            default_language => $config<language>[0],
            language         => $language,
            pages            => %pages,
            partials_all     => %( |%partials, |%theme_partials  ),
            site_index       => %site_index,
            no_livereload    => $config<no_livereload>,
            logger           => &logger);

        LAST {
            $iorunner.send: 'exit';
        }
         
    }, $config<language>;

    await $iorunner_manager;
    logger "Compile complete";
}

our sub clear(
    Map $config,
    ::D :&logger = Uzu::Logger::start()
) {
    # Clear out build
    logger "Deleting build directory";
    rm-dir $config<build_dir>;
}
