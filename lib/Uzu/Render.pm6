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

            CATCH {
                default {
                    logger "Invalid i18n yaml file [$i18n_file]";
                    logger .Str;
                }
            }

            my %yaml = load-yaml slurp($i18n_file, :r);
            my $key  = $i18n_file.dirname.split('i18n')[1] || $language;
            %i18n{$key}<i18n>     = %yaml;
            %i18n{$key}<modified> = $i18n_file.modified;
        }

   }, i18n-files(:$language, dir => $i18n_dir);

   return %i18n;
}

sub i18n-valid-hash(
    %h
    --> Bool
) {
    so %h.values.all ~~ Pair;
}


sub i18n-context-vars(
    Str      :$language, 
    IO::Path :$path,
    Hash     :$context
) {
    my Str $i18n_key = ($path.IO.path ~~ / .* 'pages' (.*) '.' .*  / ).head.Str;
    return %( |$context,
              i18n => %( ( $context{$language}<i18n>.defined ?? |$context{$language}<i18n> !! %()), 
                         # Page-specific i18n vars?
                         ( $context{$i18n_key}.defined ?? |$context{$i18n_key}<i18n> !! %())));
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

multi sub inject-linked-pages($p, :$template_engine, :&expand-linked-pages) {$p}
multi sub inject-linked-pages(
    Iterable $p,
    :$template_engine,
    :&expand-linked-pages
) {
    my $n = $p.map({
        .&inject-linked-pages(:$template_engine, :&expand-linked-pages);
    }).map({
        .&inject-linked-pages(:$template_engine, :&expand-linked-pages);
    });
    if $n.cache.values.all ~~ Pair { 
        $n.cache.Hash;
    } elsif $n.cache.values.any ~~ Hash|Pair {
        $template_engine ~~ 'mustache'
        ?? $n.cache.List
        !! $n.cache.Hash;
    } else {
        $n.cache;
    }
}
multi sub inject-linked-pages(
    Hash $p,
    :$template_engine,
    :&expand-linked-pages
    --> Hash()
) {
    map -> $k, $v {
        if $k ~~ /'_pages'$/ {
           expand-linked-pages(block_key => $k, pages => $v).Hash;
        } else {
            $k => inject-linked-pages($v, :$template_engine, :&expand-linked-pages);
        }
    }, kv $p;
}

sub linked-pages(
    Str  :$base_page,
    Str  :$block_key,
         :@pages,
    Hash :$page_vars,
    Hash :$site_index,
    Str  :$default_language,
    Str  :$language,
    Str  :$i18n_format = 'default',
         :@timestamps,
    ::D  :&logger
) {
    my %linked_pages;
    map -> %vars {
        my $key  = %vars<page>;
        my $url = ($key ~~ / '://' / || !$site_index{$key})
            ?? $key
            !! page-uri page_name => $key, :$default_language, :$language, out_ext => $site_index{$key}<out_ext>;

        logger "Broken link in template [$base_page]: page [$key] referenced in [$block_key] not found" when $key !~~ /'://'/ && !$site_index{$key};

        push @timestamps, $site_index{$key}<modified>;
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
    }, @pages;

    return %linked_pages;
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
    return '' when !$content.defined;
    unless $no_livereload {
        # Add livejs if live-reload enabled (default)
        my Str $livejs = '<script src="/uzu/js/live.js"></script>';
        if $content ~~ /'</body>'/ {
            return S/'</body>'/$livejs\n<\/body>/ given $content;
        } else {
            return $content ~ "\n$livejs";
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
    IO::Path :$path,
    ::D      :&logger
    --> List
) {
    # Extract header yaml if available
    try {

        CATCH {
            default {
                logger "Invalid template yaml [$path]";
                logger .Str;
            }
        }

        my ($template_yaml, $template_html) = ~<< ( slurp($path, :r) ~~ / ( ^^ '---' .* '---' | ^^ ) [\v]? (.*) / );
        my %yaml = $template_yaml ?? load-yaml $template_yaml.subst(/'---'$/, '') !! %();
        return $template_html, %yaml;
    }
}

sub build-partials-hash(
    IO::Path :$source,
    List     :$exts,
    ::D      :&logger
) {
    map -> $path { 
        next unless $path.IO.f;
        my Str ($partial_name, $out_ext, $target_dir) = extract-file-parts($path, $source.IO.path);

        # Extract header yaml if available
        my ($partial_html, %partial_vars) = parse-template :$path, :&logger;

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
        @partial_keys.hyper.map: -> $embedded_partial_name {

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
                            render-template
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
    Array :$from = [],
    ::D   :&logger
) {
   Template::Mustache.render: $content, $context, from => $from;
}

multi sub render-template(
    'tt',
    Hash      :$context,
    Str       :$template_name,
    Str       :$content,
    Template6 :$t6,
    ::D       :&logger
) {

    try {

       CATCH {
           default {
               logger "Error rendering template [{S/'_'$// given $template_name}]";
               logger "Template6: {.Str}";
           }
       }

       if $content && $context {
           # Store and Render
           $t6.add-template: "{$template_name}_", $content;
           $t6.add-template: $template_name, $t6.process("{$template_name}_", |$context);
       } elsif !$context {
           # Store template
           $t6.add-template: $template_name, $content;
       } else {
           # Render a stored template
           $t6.add-template: $template_name, $t6.process($template_name, |$context);
       }

    }
}

multi sub render(
    Hash      $context,
    Supplier :$page_queue,
    Str      :$template_engine,
    IO::Path :$build_dir,
    Str      :$layout_template,
    Hash     :$layout_vars,
    Numeric  :$layout_modified,
    Str      :$theme,
    List     :$themes,
    IO::Path :$theme_dir,
    Str      :$default_language,
    Str      :$language, 
    Hash     :$pages,
    List     :$exclude_pages,
    Hash     :$partials_all,
    Hash     :$site_index,
    Bool     :$no_livereload,
    ::D      :&logger
) {

    my Any %global_vars  = 
        language           => $language,
        "lang_{$language}" => True,
        "theme_{$theme}"   => True,
        layout             => $layout_vars,
        |%( $context{$language}.defined ?? |$context{$language} !! %() );

    my @layout_partials   = partial-names $template_engine, $layout_template;
    for $pages.sort({ $^a.values[0]<modified> < $^b.values[0]<modified> }) -> $page {

        my Str $page_name = $page.key;
        my Any %page      = $page.values[0];
        my @page_partials = partial-names $template_engine, %page<html>;
        my Bool $nolayout = %page<vars><nolayout>.defined || $layout_template ~~ '';

        # Skip rendering when this page hasn't been modified or is 
        # specifically excluded in config.yml
        next unless %page<render> && $exclude_pages !(cont) $page_name;

        $page_queue.emit: &{

            # When was this page last rendered?
            my $last_render_time =
                $language ~~ $default_language
                ?? "{$build_dir}/{$page_name}.{%page<out_ext>}".IO.modified||0
                !! ($build_dir ~ page-uri :$page_name, :$default_language, :$language, out_ext => %page<out_ext>).IO.modified||0;

            # Capture i18n, template, layout, and partial modified timestamps
            my @modified_timestamps = [$layout_modified, %page<modified>];
            my @partial_render_queue;

            # i18n file timestamps
            push @modified_timestamps, |(map { .values[0]<modified> }, $context);

            # Append page-specific i18n vars if available
            my Any %i18n_vars = i18n-context-vars path => %page<path>, :$context, :$language;

            # Prepare page links from *_pages yaml blocks
            my $page_vars = inject-linked-pages(
                %page<vars>, :$template_engine, expand-linked-pages => ->
                    :$base_page           = $page_name,
                    :$block_key,
                    :$pages,
                    :$r_site_index        = $site_index,
                    :$r_default_language  = $default_language,
                    :$r_language          = $language {
                        linked-pages(
                            :$base_page,
                            :$block_key,
                            :$pages,
                            site_index       => $r_site_index,
                            default_language => $r_default_language,
                            language         => $r_language,
                            timestamps       => @modified_timestamps,
                            logger           => &logger);
                    }
            );

            # Render engine storage
            my Template6 $t6 .= new when $template_engine ~~ 'tt';
            my Any %partials  = %() when $template_engine ~~ 'mustache';

            # Prepare base context variables
            my %base_context = |%global_vars, |%i18n_vars, |$page_vars;

            my ($modified_timestamps, $partial_render_queue) =
                 embedded-partials
                    template_engine      => $template_engine,
                    partials_all         => $partials_all,
                    embedded_partials    => %partials,
                    partial_keys         => [|@layout_partials, |@page_partials],
                    context              => %base_context,
                    modified_timestamps  => @modified_timestamps,
                    partial_render_queue => @partial_render_queue,
                    t6 => $t6||'';

            @modified_timestamps  = @$modified_timestamps;
            @partial_render_queue = @$partial_render_queue;
            
            # Render top-level partials content
            map -> $partial_name, %partial {

                my %context = |%base_context, |%partial<vars>;

                push @modified_timestamps, %partial<modified>;
                push @partial_render_queue, &{
                    given $template_engine {
                        when 'mustache' {
                            %partials{$partial_name} =
                                render-template
                                   'mustache',
                                    context  => %context,
                                    content  => %partial<html>,
                                    from     => [%partials],
                                    logger   => &logger;
                        }
                        when 'tt' {
                            render-template
                                'tt',
                                 context       => %context,
                                 template_name => $partial_name,
                                 content       => %partial<html>,
                                 t6            => $t6,
                                 logger        => &logger;
                        }
                    }
                }
            }, $partials_all{|@page_partials, |@layout_partials}:kv;

            # Skip rendering if layout, page, or partial templates
            # have not been modified
            next when max(@modified_timestamps) < $last_render_time;

            # Continue... render partials
            @partial_render_queue>>.();

            my %context = |%base_context, :$site_index;

            # Render the page content
            my Str $page_contents = do given $template_engine {
                when 'mustache' {
                    render-template
                       'mustache',
                        context  => %context,
                        content  => %page<html>,
                        from     => [%partials],
                        logger   => &logger;
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
                         t6            => $t6,
                         logger        => &logger;
                }
            }

            logger "No content found for page [$page_name] " when $page_contents ~~ '';

            # Append page content to $context
            my Str $layout_contents = do given %page<out_ext> {

                my %context = |%base_context, :$site_index;

                when 'html' { 
                    $nolayout
                    ?? $page_contents
                    !! do given $template_engine {
                        when 'mustache' {
                            render-template
                               'mustache',
                                context  => %context,
                                content  => $layout_template,
                                from     => [%( |%partials, content => $page_contents )],
                                logger   => &logger;
                        }
                        when 'tt' {
                            # Cache layout template
                            render-template
                               'tt',
                                template_name => 'layout',
                                content       => $layout_template,
                                t6            => $t6;
                            # Cache page template
                            render-template
                                'tt',
                                 template_name => 'content',
                                 content       => $page_contents,
                                 t6            => $t6;
                            # Render layout
                            render-template
                                'tt',
                                 context       => %context,
                                 template_name => 'layout',
                                 t6            => $t6,
                                 logger        => &logger;
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

        } # end page_queue
    };
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
    my Any %pages = templates(:$exts, dir => $config<pages_dir>).map: -> $path { 

        next unless $path.IO.f;
        my Str ($page_name, $out_ext, $target_dir) = extract-file-parts($path, $config<pages_dir>.IO.path);

        # Extract header yaml if available
        my ($page_html, %page_vars)  = parse-template :$path, :&logger;

        # Add to site index
        %site_index{$page_name}           = %page_vars;
        %site_index{$page_name}<modified> = $path.modified;
        %site_index{$page_name}<out_ext>  = $out_ext;
        my $pages_watch_dir = $config<pages_watch_dir>.IO.path;

        %( $page_name => %{
            path       => $path,
            html       => $page_html,
            vars       => %page_vars,
            out_ext    => $out_ext,
            target_dir => $target_dir,
            modified   => $path.modified,
            render     => so $path.IO.path ~~ /^ $pages_watch_dir /});
    }

    # All available partials
    my Any %partials       = build-partials-hash source => $config<partials_dir>, :$exts, :&logger;

    for $config<themes> -> $theme_config {

        my $theme_name     = $theme_config.keys.head;
        my %theme          = $theme_config.values.head;
        my $build_dir      = %theme<build_dir>;
        my $theme_dir      = %theme<theme_dir>;
        my $exclude_pages  = %theme<exclude_pages>||[];

        my Any %theme_partials =
            $theme_dir.IO.child('partials').IO.d
            ?? build-partials-hash source => $theme_dir.IO.child('partials'), :$exts, :&logger !! %();

        # Create build dir
        if !$build_dir.IO.d { 
            logger "Create build directory";
            mkdir $build_dir;
        }

        logger "Copy public, assets";
        copy-dir($config<public_dir>, $build_dir) when $config<public_dir>.IO.e;
        copy-dir($theme_dir.IO.child('assets'), $build_dir) when $theme_dir.IO.child('assets').IO.e;

        # Append nested pages directories
        my @template_dirs = |$config<template_dirs>, |find(dir => $config<pages_dir>, type => 'dir');

        # Append nested i18n directories
        my IO::Path @i18n_dirs = $config<i18n_dir>, |find(dir => $config<i18n_dir>, type => 'dir');

        my IO::Path $layout_path = grep(/ 'layout.' @$exts $ /, templates(:$exts, dir => $theme_dir)).head;

        # Extract layout header yaml if available
        my ($layout_template, $layout_vars) =
            $layout_path.defined
            ?? parse-template(path => $layout_path, :&logger)
            !! ["", %{}];

        logger "Theme [{$theme_name}] does not contain a layout template" unless $layout_path.defined;

        my @exclude_pages = [ |$config<exclude_pages>, |$exclude_pages ].grep(*.defined);

        # Queue for page renders
        my $page_queue     = Supplier.new;
        my $page_supply    = $page_queue.Supply;
        my $rendered_pages = 0; 
        my Promise $render_complete .= new;
        $page_supply.tap({ .() });

        # One per language
        for $config<language> -> $language { 

            logger "Compile templates [$language]";

            i18n-from-yaml(
                language         => $language,
                i18n_dir         => $config<i18n_dir>,
                logger           => &logger)
            ==> render(
                page_queue       => $page_queue,
                template_engine  => $config<template_engine>,
                build_dir        => $build_dir,
                theme            => $theme_name,
                layout_template  => $layout_template,
                layout_vars      => $layout_vars,
                layout_modified  => ($layout_path.defined ?? $layout_path.modified !! 0),
                theme_dir        => $theme_dir,
                default_language => $config<language>[0],
                language         => $language,
                pages            => %pages,
                exclude_pages    => @exclude_pages,
                partials_all     => %( |%partials, |%theme_partials  ),
                site_index       => %site_index,
                no_livereload    => $config<no_livereload>,
                logger           => &logger);
       }

    }

    logger "Compile complete";
}

our sub clear(
    Map $config,
    ::D :&logger = Uzu::Logger::start()
) {
    # Clear out build
    for $config<themes> {
        logger "Deleting build directory";
        rm-dir .values.head<build_dir>;
    }
}
