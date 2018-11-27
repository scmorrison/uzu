use File::Find;

unit module Uzu::Utilities;

our sub copy-dir(
    IO::Path $source,
    IO::Path $target,
             :@exclude = []
    --> Bool
) is export {
    my @files = find(dir => $source, exclude => / <@exclude> /);
    for @files {
        next unless so $_.IO.d && $_.path !~~ /@exclude/ ;
        mkdir $_.path.subst($source.path, $target.path); 
    }
    for @files {
        next unless so $_.IO.f && $_.path !~~ /@exclude/ ;
        copy $_, $_.path.subst($source.path, $target.path); 
    }
    return True;
}

our sub rm-dir(
    IO::Path $dir
    --> Bool
) is export {
    return unless $dir.IO.d;
    if $*SPEC ~~ 'Win32' {
        so shell "rmdir $dir /s /q";
    } else {
        so shell "rm -rf $dir";
    }
}

#
# build-category-uri: convert YAML dict
# into list of URIs for each branch.
#

proto sub build-category-uri(|) is export {*}
multi sub build-category-uri(Str $item) {
    return $item;
}

multi sub build-category-uri(Str $parent, Str $item) {
    return "$parent/$item";
}

multi sub build-category-uri(Str $parent, Hash $items) {
    map -> $k, $item {
        build-category-uri "$parent/$k", $item;
    }, kv $items;
}
multi sub build-category-uri(Hash $items) {
    map -> $parent, $item {
        build-category-uri $parent, $item;
    }, kv $items;
}

multi sub build-category-uri(Str $parent, Array $items) {
    map -> $item {
        build-category-uri $parent, $item;
    }, $items.List;
}

multi sub build-category-uri(Array $dict, :$cat_label = 'categories') {
    "/$cat_label/" <<~<< (map -> $item {
        build-category-uri $item;
    }, $dict.List).flat;
}

#
# build-category-toc-html: generate bulleted list from
# category hash.
#

proto sub build-category-toc-html(|) is export {*}
multi sub build-category-toc-html(
    Str $item,
    Str :$breadcrumb
    --> Str
) {
    "<li><a href=\"{$breadcrumb}/{$item}\">{$item}</a></li>";
}

multi sub build-category-toc-html(
    Pair $item,
    Str  :$breadcrumb
    --> Str
) {
    my $bc = "{$breadcrumb}/{$item.key}";
    ['<li>', "<a href=\"{$bc}\">{$item.key}</a>", build-category-toc-html($item.value, breadcrumb => $bc), '</li>'].join('');
}

multi sub build-category-toc-html(
    Iterable $items,
    Str      :$breadcrumb
    --> Str
) {
    ['<ul>', (map -> $item {
        build-category-toc-html($item, breadcrumb => $breadcrumb) }, $items
    )].join('');
}

multi sub build-category-toc-html(
    Hash $items,
    Str  :$breadcrumb
    --> Str
) {
    [(map -> $k, $v {
        my $bc = $k ~~ Str ?? "{$breadcrumb}/{$k}" !! $breadcrumb;
        "<li><a href=\"{$bc}\">{$k}</a>", build-category-toc-html($v.flat, breadcrumb => $bc)
    }, kv $items), '</ul>', '</li>'].join('');
}
