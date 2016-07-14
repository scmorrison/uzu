Uzu (渦) [![build status](https://gitlab.com/samcns/uzu/badges/master/build.svg)](https://gitlab.com/samcns/uzu/commits/master)
===

Simple static site generator with built-in web server and file-modification change detector.

Features
========
* **Easy to use**: Based on existing static site generator conventions
* **Built-in development webserver**: Test your modifications (http://localhost:3000) as you work
* **Auto Re-render**: `uzu watch` monitors the `theme/[your-theme]/layout/`, `pages`, `partials/`, and `i18n/` folders for modifications and auto-renders to build
* **i18n support**: Use YAML to define each language in the `i18n/` folder (e.g. `i18n/en.yml`)
* **Page / layout support**: Generate individual pages wrapped in the same theme layout
* **Actively developed**: More features coming soon (e.g. more tests, AWS, Github Pages, SSH support...)

Usage
=====

```
Usage:
  uzu init       - Initialize new project
  uzu webserver  - Start local web server
  uzu build      - Render all templates to build
  uzu watch      - Start web server and re-render
                   build on template modification

Optional arguments:
  
  --config=      - Specify a custom config file
                   Default: `config`

  e.g. uzu --config=path/to/config init
```

Project folder structure
========================
```
├── config
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

Install `Perl 6` using the following process:

1. Install `rakudobrew`

    ```bash
    git clone https://github.com/tadzik/rakudobrew ~/.rakudobrew
    export PATH=~/.rakudobrew/bin:$PATH
    rakudobrew init # Instructions for permanent installation.
    ```

2. Run `rakudobrew init` and follow instructions / output

    It should be something similar to this, changing the username `sam` to your own username:

    ```bash
    echo 'eval "$(/home/sam/.rakudobrew/bin/rakudobrew init -)"' >> ~/.profile
    ```

3. Install latest `Perl 6` and `panda`. 

    Note: This will take about ~5-10 minutes to compile

    ```bash
    rakudobrew build moar 2016.06
    rakudobrew build panda
    ```

4. Clone the repository locally 

    ```
    git clone https://gitlab.com/samcns/uzu.git
    ```

5. Install project requirements

    ```
    # We are using Bailador for the static web server
    # it currently fails. Please use `--notests` to 
    # install.

    cd uzu/
    panda -force --notests install .
    rakudobrew rehash
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
