use v6.c;

use Uzu::HTTP;
use Uzu::LiveReload;
use Uzu::Logger;
use Uzu::Render;
use File::Find;
use Terminal::ANSIColor;

unit module Uzu::Watch;

sub find-dirs(
    IO::Path $p
    --> Slip
) {
    slip ($p.IO, slip find :dir($p.path), :type<dir>);
}

sub watch-dir(
    Str $p
    --> Tap
) {
    whenever IO::Notification.watch-path($p.path) -> $c {
        if $c.event ~~ FileRenamed && $c.path.IO ~~ :d {
            find-dirs($c.path).map(watch-dir $_);
        }
        emit $c;
    }
}

sub file-change-monitor(
    List $dirs
    --> Supply
) {
    supply {
        watch-dir(~$_.path) for $dirs.map: { find-dirs $_ };
    }
}

sub build-and-reload(
    Map $config,
    ::D :&logger
    --> Bool
) {
    Uzu::Render::build($config, logger => &logger);
    Uzu::LiveReload::reload-browser($config);
}

sub user-input(
    Map     $config,
    ::D     :&logger
    --> Bool
) {
    loop {
        logger colored "`r enter` to [rebuild]\n" ~ \
                       "`c enter` to [clear] build directory and rebuild\n" ~ \
                       "`q enter` to [quit]", "bold green on_blue";
        given prompt('') {
            when 'r' {
                logger colored "Rebuild triggered", "bold green on_blue";
                build-and-reload($config, logger => &logger);
            }
            when 'c' {
                logger colored "Clear build directory and rebuild triggered", "bold green on_blue";
                Uzu::Render::clear($config, logger => &logger);
                build-and-reload($config, logger => &logger);
            }
            when 'q'|'quit' {
                exit 1;
            }
        }
    }
}

our sub start(
    Map $config,
    --> Bool
) {
    my &logger = Uzu::Logger::start();
    
    # Initialize build
    logger "Initial build";
    Uzu::Render::build($config, logger => &logger);
    
    # Track time delta between File events. 
    # Some editors trigger more than one event per
    # edit. 
    my List $exts = $config<extensions>;
    my List $dirs = |$config<template_dirs>.grep(*.IO.e);
    $dirs.map(-> $dir {
        logger "Starting watch on {$dir.subst("{$*CWD}/", '')}";
    });

    # Start server
    my $app = start { Uzu::HTTP::web-server $config }

    # Keep track of the last render timestamp
    state Instant $last_run = now;

    # Watch directories for modifications
    start {
        react {
            whenever file-change-monitor($dirs) -> $e {
                # Make sure the file change is a 
                # known extension; don't re-render too fast
                if so $e.path.IO.extension ∈ $exts and (now - $last_run) > 2 {
                    logger colored "Change detected [{$e.path()}]", "bold green on_blue";
                    build-and-reload($config, logger => &logger);
                    $last_run = now;
                }
            }
        }
    }

    # Listen for keyboard input
    user-input($config, logger => &logger);
}

