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
    await start {
        find( :$dir, name => /'.' @$exts $/ );
    }
}

sub i18n-files(
    Str      :$language,
    IO::Path :$dir!
) {
    await start {
        find( :$dir, name => / $language '.yml' $/, type => 'file' );
    }
}

sub i18n-from-yaml(
    Str      :$language,
    IO::Path :$i18n_dir
    --> Hash 
) {
    my %i18n;
    for i18n-files(:$language, dir => $i18n_dir) -> $i18n_file {

        logger "i18n yaml file [$i18n_file] could not be loaded" and next unless so $i18n_file.IO.f;
       
        try {
            my %yaml = await start {
                load-yaml slurp($i18n_file, :r);
            }
            my $key  = $i18n_file.dirname.split('i18n')[1] || $language;
            %i18n{$key}<i18n>     = %yaml;
            %i18n{$key}<modified> = $i18n_file.modified;

            CATCH {
                default {
                    logger "Invalid i18n yaml file [$i18n_file]";
                }
            }

        }

   }
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
             :%context
) {
    my Str $i18n_key = ($path.IO.path ~~ / .* 'pages' (.*) '.' .*  / ).head.Str;
    return %( |%context,
              i18n => %( ( %context{$language}<i18n>.defined ?? |%context{$language}<i18n> !! %()), 
                         # Page-specific i18n vars?
                         ( %context{$i18n_key}.defined ?? |%context{$i18n_key}<i18n> !! %())));
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

#| Generate page uri for linked pages
sub page-uri(
    Str :$page_name,
    Str :$out_ext,
    Str :$default_language,
    Str :$language,
    Str :$i18n_format = 'default'
    --> Str
) {
    $i18n_format ~~ 'subfolder'
    ?? "/{$language}/{$page_name}.{$out_ext}"
    !! '/' ~ html-file-name(:$page_name, :$default_language, :$language) ~ ".{$out_ext}";
}

#| Parse page templates for references to other pages. Build a Hash containing
#| all a linked pages index for each template. See `Related / linked pages` in
#| the README for more details.

#| String
multi sub inject-linked-pages($p, :$template_engine, :&expand-linked-pages) {$p}
#| Iterable
multi sub inject-linked-pages(
    Iterable $p,
    :$template_engine,
    :&expand-linked-pages
) {
    my $n = $p.map({
        inject-linked-pages($_, :$template_engine, :&expand-linked-pages);
    });
    # Return Hash if all Pairs
    if $n.cache.values.all ~~ Pair { 
        $n.cache.Hash;
    # Return a List for Mustache and Hash for TT
    # when $n contains nested Hash
    } elsif $n.cache.values.any ~~ Hash|Pair {
        $template_engine ~~ 'mustache'
        ?? $n.cache.List
        !! $n.cache.Hash;
    # Default
    } else {
        $n.cache;
    }
}
#| Hash
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
         :%page_vars,
         :%site_index,
    Str  :$default_language,
    Str  :$language,
    Str  :$i18n_format = 'default',
         :@timestamps
) {
    my %linked_pages;
    for @pages -> %vars {
        my $key  = %vars<page>;
        my $url = ($key ~~ / '://' / || !%site_index{$key})
            ?? $key
            !! page-uri page_name => $key, :$default_language, :$language, out_ext => %site_index{$key}<out_ext>;

        logger "Broken link in template [$base_page]: page [$key] referenced in [$block_key] not found" when $key !~~ /'://'/ && !%site_index{$key};

        push @timestamps, %site_index{$key}<modified>;
        push %linked_pages{$block_key}, grep({ .value }, [
            |%site_index{$key}.Hash,
            # use the variables defined in the _pages block if set
            page     => $key,
            url      => $url,
            title    => %site_index{$key}<title>    ||%vars<title>,
            author   => %site_index{$key}<author>   ||%vars<author>||'',
            date     => %site_index{$key}<date>     ||'',
            modified => %site_index{$key}<modified>
        ]).Hash;
    }

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
    IO::Path :$build_dir,
    Bool     :$omit_html_ext = False
    --> Bool()
) {

    # IO write to disk
    my $page_name  = $content.key;
    my %meta       = $content.values;
    my $html       = %meta<html>;
    my $target_dir = $build_dir.IO.child(%meta<target_dir>.IO);
    my $out        = $build_dir.IO.child("{$page_name}{$omit_html_ext ?? '' !! '.' ~ %meta<out_ext>}");
    mkdir $target_dir when !$target_dir.IO.d;
    logger "Rendered page [$page_name] is empty" unless $html;
    spurt $out, ($html||'');
}

sub prepare-html-output(
    Str      :$page_name,
    Str      :$default_language,
    Str      :$language,
    Str      :$layout_contents,
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

    return $file_name => %{ 
        :$path,
        html => $layout_contents,
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
        my %yaml = $template_yaml ?? load-yaml $template_yaml.subst(/'---'$/, '') !! %();
        return $template_html, %yaml;

        CATCH {
            default {
                logger "Invalid template yaml [$path]";
                logger .Str;
                return $template_html, %{};
            }
        }
    }
}

sub build-partials-hash(
    IO::Path :$source,
    List     :$exts
) {

    templates(:$exts, dir => $source).map: -> $path { 
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
    }
}

#| Extract partial names from template
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

#| Prefix referenced partial names with parent partial / page name
sub prefix-partial-names(
    :$engine,
    :$parent,
    :$content is copy
) {
    my @partials = do given $engine {
       next unless $content;
        when 'tt' {
            ($content ~~ m:g/('[%' \s*? 'INCLUDE' \s*? '"') <( \S* )> ('"' \s*? '%]')/);
        }
        when 'mustache' {
            ($content ~~ m:g/('{{>' \s*?) <( \S* )> (\s*? '}}')/);
        }
    }

    my @replacements = @partials.map: {
        my $partial = $_.Str;
        next if $partial ~~ 'content';
        my $pre  = $_[0].Str;
        my $post = $_[1].Str;
        "{$pre}{$partial}{$post}" => "{$pre}{$parent}_{$partial}{$post}";
    };

    @replacements.map: -> %p {
        $content = $content.subst: %p.key, %p.value;
    }

    return $content;
}

#| Prerender embedded partials and cache in template
#| cache using [parent template name]_[embedded partial name]
#| as key.
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
        @partial_keys.map: -> $embedded_partial_name {

            my %context = |$context, |%partial<vars>, |($partials_all{$embedded_partial_name}<vars>||%{});

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
                        $embedded_partials{"{$partial_name}_{$embedded_partial_name}"} =
                            render-template
                                $template_engine,
                                context  => %context,
                                content  => prefix-partial-names(
                                    engine  => $template_engine,
                                    parent  => $embedded_partial_name,
                                    content => $partials_all{$embedded_partial_name}<html>
                                ),
                                from     => [$embedded_partials];
                    }
                    when 'tt' {
                        render-template
                            $template_engine,
                            context       => %context,
                            template_name => "{$partial_name}_{$embedded_partial_name}",
                            content       => prefix-partial-names(
                                engine  => $template_engine,
                                parent  => $embedded_partial_name,
                                content => $partials_all{$embedded_partial_name}<html>
                            ),
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
          :%context,
    Str   :$content,
          :@from = []
) {
    quietly {
        Template::Mustache.render: $content, %context, :@from;
    }
}
multi sub render-template(
              'tt',
              :%context,
    Str       :$template_name,
    Str       :$content,
    Template6 :$t6
) {

    try {

       CATCH {
           default {
               logger "Error rendering template [{S/'_'$// given $template_name}]";
               logger "Template6: {.Str}";
           }
       }

       if $content && %context {
           # Store and Render
           $t6.add-template: "{$template_name}_", $content;
           $t6.add-template: $template_name, $t6.process("{$template_name}_", |%context);
       } elsif !%context {
           # Store template
           $t6.add-template: $template_name, $content;
       } else {
           # Render a stored template
           $t6.add-template: $template_name, $t6.process($template_name, |%context);
       }

    }
}

multi sub render(
    Hash      $context,
             :%extended,
    Supplier :$page_queue,
    Str      :$template_engine,
    IO::Path :$build_dir,
    Str      :$layout_template,
    Hash     :$site_vars,
    Hash     :$layout_vars,
    Numeric  :$layout_modified,
    Str      :$theme,
    List     :$themes,
    IO::Path :$theme_dir,
    Str      :$default_language,
    Str      :$language, 
             :@pages,
             :@exclude_pages,
    Hash     :$partials_all,
    Hash     :$site_index
) {

    my %global_vars  = 
        language           => $language,
        "lang_{$language}" => True,
        "theme_{$theme}"   => True,
        site               => $site_vars,
        layout             => $layout_vars,
        dt                 => date-hash(),
        randnum            => (rand * 10**16).Int,
        # Extra vars from local app
        |%extended,
        # i18n vars
        |%( $context{$language}.defined ?? |$context{$language} !! %() );

    my @layout_partials = partial-names $template_engine, $layout_template;

    # Build / render all pages (sorted by file modified)
    for @pages.sort({ $^a.value<modified>.Int < $^b.value<modified>.Int }) -> Pair $page {

        my $page_name = $page.key;
        my %page      = $page.value;
        my @page_partials = partial-names $template_engine, %page<html>;
        my Bool $nolayout = %page<vars><nolayout>.defined || $layout_template ~~ '';

        # Skip rendering when this page hasn't been modified or is 
        # specifically excluded in config.yml
        next unless %page<render> && @exclude_pages !(cont) $page_name;

        $page_queue.emit: &{

            # When was this page last rendered?
            my $last_render_time =
                $language ~~ $default_language
                ?? "{$build_dir}/{$page_name}.{%page<out_ext>}".IO.modified||0
                !! ($build_dir ~ page-uri :$page_name, :$default_language, :$language, out_ext => %page<out_ext>).IO.modified||0;

            # Capture i18n, template, layout, and partial modified timestamps
            my @modified_timestamps = [$layout_modified, %page<modified>];
            my @partial_render_queue;

            # Page specific i18n yaml modified timestamp
            push @modified_timestamps, $context{'/' ~ $page_name}<modified> if $context{'/' ~ $page_name}:exists;
            # Langeuage i18n yaml modified timestamp
            push @modified_timestamps, $context{$language}<modified>        if $context{$language}:exists;

            # Append page-specific i18n vars if available
            my %i18n_vars = i18n-context-vars path => %page<path>, :$context, :$language;

            # Prepare page links from *_pages yaml blocks
            my $page_vars = inject-linked-pages(
                %page<vars>, :$template_engine, expand-linked-pages => ->
                    :$base_page           = $page_name,
                    :$block_key,
                    :@pages,
                    :$r_site_index        = $site_index,
                    :$r_default_language  = $default_language,
                    :$r_language          = $language {
                        linked-pages(
                            :$base_page,
                            :$block_key,
                            :@pages,
                            site_index       => $r_site_index,
                            default_language => $r_default_language,
                            language         => $r_language,
                            timestamps       => @modified_timestamps);
                    }
            );

            # Render engine storage
            my Template6 $t6 .= new when $template_engine ~~ 'tt';
            my %partials      = %() when $template_engine ~~ 'mustache';

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
            for $partials_all{|@page_partials, |@layout_partials}:kv -> $partial_name, %partial {

                my %context = |%base_context, |%partial<vars>;

                push @modified_timestamps, %partial<modified>;
                push @partial_render_queue, &{
                    given $template_engine {
                        when 'mustache' {
                            %partials{"{$page_name}_{$partial_name}"} =
                                render-template
                                   $template_engine,
                                   context    => %context,
                                   content    => prefix-partial-names(
                                       engine  => $template_engine,
                                       parent  => $partial_name,
                                       content => %partial<html>
                                   ),
                                   from       => [%partials];
                        }
                        when 'tt' {
                            render-template
                                $template_engine,
                                context       => %context,
                                template_name => "{$page_name}_{$partial_name}",
                                content       => prefix-partial-names(
                                    engine  => $template_engine,
                                    parent  => $partial_name,
                                    content => %partial<html>
                                ),
                                t6            => $t6;
                        }
                    }
                }
            } #/partials map

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
                       $template_engine,
                       context   => %context,
                       content       => prefix-partial-names(
                           engine  => $template_engine,
                           parent  => $page_name,
                           content => %page<html>
                       ),
                       from      => [%partials];
                }
                when 'tt' {
                    # Cache template
                    render-template
                        $template_engine,
                        template_name => "{$page_name}_",
                        content       => prefix-partial-names(
                            engine  => $template_engine,
                            parent  => $page_name,
                            content => %page<html>
                        ),
                        t6            => $t6;
                    render-template
                        $template_engine,
                        template_name => "{$page_name}_",
                        context       => %context,
                        t6            => $t6;
                }
            }

            # Append page content to $context
            my Str $layout_contents = do given %page<out_ext> {

                my %context = |%base_context, :$site_index;

                when 'html' { 
                    $nolayout
                    ?? $page_contents
                    !! do given $template_engine {
                        when 'mustache' {
                            render-template
                                 $template_engine,
                                 context       => %context,
                                 content       => prefix-partial-names(
                                     engine  => $template_engine,
                                     parent  => $page_name,
                                     content => $layout_template
                                 ),
                                 from          => [%( |%partials, content => $page_contents )];
                        }
                        when 'tt' {
                            # Cache layout template
                            render-template
                                $template_engine,
                                template_name => 'layout',
                                content       => prefix-partial-names(
                                    engine  => $template_engine,
                                    parent  => $page_name,
                                    content => $layout_template
                                ),
                                t6            => $t6;
                            # Cache page template
                            render-template
                                $template_engine,
                                template_name => 'content',
                                content       => $page_contents,
                                t6            => $t6;
                            # Render layout
                            render-template
                                $template_engine,
                                context       => %context,
                                template_name => 'layout',
                                t6            => $t6;
                        }
                    }
                }

                # Do not wrap non-html files with layout
                default { $page_contents }
            }

            write-generated-file(
                prepare-html-output(
                    :$page_name,
                    :$default_language,
                    :$language,
                    :$layout_contents,
                    path       => %page<path>,
                    target_dir => %page<target_dir>,
                    out_ext    => %page<out_ext>),
                :$build_dir

            );

        } # end page_queue
    } # /pages map
}

our sub build(
     %config
    --> Promise
) {

    state $first_run;

    # Pre-build command
    if %config<pre_command>:exists {
        logger QX %config<pre_command>;
    }
    # Refresh extended data
    my %extended;
    if %config<refresh_extended> && $first_run {
        %extended = %config<_extended>();
    }
    my List $exts = %config<template_extensions>{%config<template_engine>};

    # Capture page meta
    # data for related,
    # categories, and sitemaps
    my %site_index;

    # All available pages
    my @pages = templates(:$exts, dir => %config<pages_dir>).map: -> $path { 

        next unless $path.IO.f;
        my Str ($page_name, $out_ext, $target_dir) = extract-file-parts($path, %config<pages_dir>.IO.path);

        # Extract header yaml if available
        my ($page_html, %page_vars) = parse-template :$path;

        # Add to site index
        %site_index{$page_name}           = %page_vars;
        %site_index{$page_name}<modified> = $path.modified;
        %site_index{$page_name}<out_ext>  = $out_ext;
        my $pages_watch_dir = %config<pages_watch_dir>.IO.path;

        $page_name => %{
            path       => $path,
            html       => $page_html,
            vars       => %page_vars,
            out_ext    => $out_ext,
            target_dir => $target_dir,
            modified   => $path.modified,
            render     => (so $path.IO.path ~~ /^ $pages_watch_dir /)
        }
    }

    # All available partials
    my %partials = build-partials-hash source => %config<partials_dir>, :$exts;

    for %config<themes>.List -> $theme_config {
        my $theme_name     = $theme_config.key;
        my %theme          = $theme_config.value;
        my $build_dir      = %theme<build_dir>;
        my $theme_dir      = %theme<theme_dir>;

        my %theme_partials =
            $theme_dir.IO.child('partials').IO.d
            ?? build-partials-hash source => $theme_dir.IO.child('partials'), :$exts
            !! %();

        # Create build dir
        if !$build_dir.IO.d { 
            logger "Create build directory";
            mkdir $build_dir;
        }

        logger "Copy public, assets";
        copy-dir(%config<public_dir>, $build_dir, exclude => %config<exclude>)           when %config<public_dir>.IO.e;
        copy-dir($theme_dir.IO.child('assets'), $build_dir, exclude => %config<exclude>) when $theme_dir.IO.child('assets').IO.e;

        # Append nested pages directories
        my @template_dirs = |%config<template_dirs>, |find(dir => %config<pages_dir>, type => 'dir');

        # Append nested i18n directories
        my IO::Path @i18n_dirs   = %config<i18n_dir>, |find(dir => %config<i18n_dir>, type => 'dir');
        my IO::Path $layout_path = grep(/ 'layout.' @$exts $ /, templates(:$exts, dir => $theme_dir)).head;

        # Extract layout header yaml if available
        my ($layout_template, $layout_vars) =
            $layout_path.defined
            ?? parse-template(path => $layout_path)
            !! ["", %{}];

        logger "Theme [{$theme_name}] does not contain a layout template" unless $layout_path.defined;

        # Queue for page renders
        my $page_queue     = Supplier.new;
        my $page_supply    = $page_queue.Supply;
        my $rendered_pages = 0; 
        my Promise $render_complete .= new;
        $page_supply.tap({ .() });

        # One per language
        for %config<language>.flat -> $language { 

            logger "Compile templates [$language]";

            render(
                i18n-from-yaml(
                    :$language,
                    i18n_dir => %config<i18n_dir>
                ),
                :$page_queue,
                :$build_dir,
                :$layout_template,
                site_vars        => %config<site>,
                :$layout_vars,
                :$theme_dir,
                :$language,
                :@pages,
                :%site_index,
                exclude_pages    => [ |%theme<exclude_pages>, |%config<exclude_pages> ].grep(*.defined),
                template_engine  => %config<template_engine>,
                theme            => $theme_name,
                layout_modified  => ($layout_path.defined ?? $layout_path.modified !! 0),
                default_language => %config<language>[0],
                partials_all     => %( |%partials, |%theme_partials ),
                extended         => (%extended||%config<extended>)
            );

        } #/language

    }

    $first_run = True;

    logger "Compile complete";

    # Post-build command
    if %config<post_command>:exists {
        logger QX %config<post_command>;
    }

}

our sub clear(
    %config
) {
    # Clear out build
    for %config<themes> {
        logger "Deleting build directory";
        rm-dir .values.head<build_dir>;
    }
}
