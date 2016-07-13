Uzu (渦)
===

Simple static site generator with built-in web server and file-modification change detector.

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
├── assets
│   ├── fonts
│   ├── img
│   ├── js
│   ├── favicon.ico
├── config
├── partials
│   ├── content.mustache
│   ├── footer.mustache
│   ├── head.mustache
│   ├── jumbotron.mustache
│   └── navigation.mustache
└── themes
    └── default.mustache
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
  * Pages, currently only single page
  * Posts for blogs

Requirements
============

* [Perl 6](http://perl6.org/)

AUTHORS
=======

* [Sam Morrison](@samcns)
