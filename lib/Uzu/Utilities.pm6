use v6.c;

unit module Uzu::Utilities;

our sub decode-entities(
    Str $str
) is export {
    $str.trans:
        /'&amp;'/  => '&',
        /'&quot;'/ => '"',
        /'&lt;'/   => '<',
        /'&gt;'/   => '>',
        /'&nbsp;'/ => ' ';
}

our sub copy-dir(
    IO::Path $source,
    IO::Path $target
    --> Bool
) is export {
    given $*SPEC {
        when 'Win32' {
            shell "copy $source $target /O /X /E /H /K /Y";
        }
        default {
            shell "cp -rf $source/* $target/" when elems dir $source gt 0;
        }
    }
    return True;
}

our sub rm-dir(
    IO::Path $dir
    --> Bool
) is export {
    if $*SPEC ~~ 'Win32' {
        so shell "rmdir $dir /s /q";
    } else {
        so shell "rm -rf $dir";
    }
}
