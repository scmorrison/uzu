Uzu (渦) [![build status](https://gitlab.com/samcns/uzu/badges/master/build.svg)](https://gitlab.com/samcns/uzu/commits/master)
===

Uzu is a static site generator with built-in web server, file modification watcher, i18n, themes, and multi-page support.

Features
========
* **Easy to use**: Based on existing static site generator conventions
* **Built-in development webserver**: Test your modifications (http://localhost:3000) as you work
* **Auto Re-render**: `uzu watch` monitors the `theme/[your-theme]/layout/`, `pages`, `partials/`, and `i18n/` folders for modifications and auto-renders to build
* **i18n support**: Use YAML to define each language in the `i18n/` folder (e.g. `i18n/en.yml`)
* **Page / layout support**: Generate individual pages wrapped in the same theme layout
* **Actively developed**: More features coming soon (e.g. more tests, AWS, Github Pages, SSH support...)

**Note**: Uzu is a work in progress. It is functional and does a bunch of cool stuff, but it isn't perfect. Please post any [issues](https://gitlab.com/samcns/uzu/issues) you find.

Usage
=====

```
Usage:
  uzu init       - Initialize new project
  uzu webserver  - Start local web server
  uzu build      - Render all templates to build
  uzu watch      - Start web server and re-render
                   build on template modification
  uzu version    - Print uzu version and exit

Optional arguments:
  
  --config=      - Specify a custom config file
                   Default: `config`

  e.g. uzu --config=path/to/config init
```

Config
======

Each project has its own `config.yml` which uses the following format:

```yaml
---
# Name of the project
name: uzu-starter

# Language to use, determines which
# i18n/*.yml file to use for string variables
language: en

# Themes are stored in themes/[theme-name]
theme: default

# Site URL
url: https://gitlab.com/samcns/uzu-starter

# Optional parameters (also, comments like this are ok)

# Use a custom dev server port, default is 3000
port: 4040

# Specify a custom project root path
# default is .
project_root: path/to/project/folder
```

Project folder structure
========================
```
├── config.yml
├── pages
│   ├── about.mustache
│   └── index.mustache
├── partials
│   ├── footer.mustache
│   ├── head.mustache
│   ├── home.mustache
│   ├── jumbotron.mustache
│   ├── navigation.mustache
│   └── profiles.mustache
├── i18n
│   ├── en.yml
│   ├── fr.yml
│   ├── ja.yml
└── themes
    └── default
        ├── assets
        │   ├── css
        │   ├── favicon.ico
        │   ├── fonts
        │   ├── img
        │   ├── js
        └── layout
            └── layout.mustache
```

See [uzu-starter](https://gitlab.com/samcns/uzu-starter) for a full example.

Installation
============

```
panda install Uzu
```

Todo
====

* Add tests
* Add build steps to build.pl6
* Uglify JS / CSS
* Build deploy process push to S3
* Features
  * Posts for blogs

Requirements
============

* [Perl 6](http://perl6.org/)

AUTHORS
=======

[Sam Morrison](@samcns)
