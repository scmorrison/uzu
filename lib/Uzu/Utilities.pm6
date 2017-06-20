use v6;

unit module Uzu::Utilities;

our sub copy-dir(
    IO::Path $source,
    IO::Path $target
    --> Bool
) is export {
    if $*SPEC ~~ 'Win32' {
        so shell "copy $source $target /O /X /E /H /K /Y";
    } else {
        so shell "cp -rf $source/* $target/";
    }
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

