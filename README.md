Tclssg
=======

A static site generator with template support written in Tcl for danyilbohdan.com. Intended to make it easy to manage a small personal website with an optional blog.

**Warning! Tclssg is still in early development and may change rapidly in incompatible ways.**

Features
--------

* Markdown for content formatting.
* [Bootstrap](http://getbootstrap.com/) for layout. Supports Bootstrap themes.
* Support for plain old pages and blogs post. [1]
* A single command deploys the resulting website over FTP.
* Tcl code embedded in HTML for templating. [2]
* Generated links are all relative.
* Output is valid HTML5 and CSS level 3.

1\. Blog posts differ from plain old pages in that they have a sidebar with links to other blog posts sorted by recency, tags and the latest are featured on the blog index. A "tag cloud" can generated to find pages by tag.

2\. Templating example:

        <article>
        <% textutil::indent $content {        } %>
        </article>

Page screenshot
---------------
![Test page generated by Tclssg](screenshot.png)

Getting started
---------------

Tclssg is known to run on Linux, FreeBSD, OpenBSD, OS X and Windows XP/7/8.x.

To use it you will need Tcl 8.5 or newer and Tcllib installed. You will also need a Markdown processor to turn Markdown into HTML. The default Markdown processor shipped with Tclssg is [Markdown 1.0.1](http://daringfireball.net/projects/markdown/), which requires Perl 5.6 or newer.

To install Tcl and Tcllib on **Debian/Ubuntu** run the following command:

    sudo apt-get install tcl tcllib

On **Fedora/RHEL/CentOS**:

    su -
    yum install tcl tcllib

On **Windows** the easiest option is to install ActiveTcl and ActivePerl from [ActiveState](http://activestate.com/). The copy of Tcl that comes with [Git for Windows](http://msysgit.github.io/) doesn't come with Tcllib, so it won't run Tclssg out of the box.

Once you have the requirements installed clone this repository, `cd` into it then run

    ./ssg.tcl init
    ./ssg.tcl build
    ./ssg.tcl open

or on Windows

    ssg.cmd init
    ssg.cmd build
    ssg.cmd open

This will create a new website project in the directory `website/input`, build it in `website/output` and open the result in the default web browser.

Concepts
--------

| Concept | Explanation |
|---------|-------------|
| Page | The main building block of your static website. A page is a file with extension `.md` and Markdown content based on which a single page of HTML output is produced. When a page from `inputDir` is processed by Tclssg the HTML file is placed under the same relative path with the same file name in `outputDir`. E.g., the page `test/page1.md` will generate the HTML file `test/page1.html` in output directory. A page can be a blog post (see below) or not. |
| Blog post | Blog posts are pages that have special features to help organize a blog, tags and a sidebar with links to other blog posts. Those features are enable by default but can be selectively disabled for any individual blog post. The latest blog posts are featured on the blog index page. A blog post's order in the sidebar is determined by its date (the `date` variable). |
| Index | |
| Blog index | | |
| Template | A file with Tcl code embedded in HTML markup. Once a page has been converted from Markdown to HTML its content is rendered according to the template's logic (code), which interprets the settings specified in that page's file and your config file. Templating in Tclssg is powered by Tcllib's [`textutil::expander`](http://tcllib.sourceforge.net/doc/expander.html). |
| Configuration file | The file `website.conf` in the input directory that specifies the settings (variables) that apply to the static website as a whole like the website title. |
| Variable | A variable specifies a Tclssg setting for either the whole website or an individual page. Those range from the page title, which you'd normally want to set for each page, to the password for the FTP server your want to deploy your website to. When a variable is set in a page file it specifies a setting for that individual page. When a variable is set the configuration (config) file it specifies a setting for the website as a whole. |
| Static file | A file that should be copied verbatim into to the output directory. Those are stored in a subdirectory of the input directory (`inputDir/static`). File paths relative to `inputDir/static` are preserved, which means that, e.g., `website/input/static/blah/file.zip` will be copied to `website/output/blah/file.zip`.  |
| Output | The static website ready to be presented to the world. Consists of HTML files created by Tclssg based on the content in the input directory plus the static files. It is placed in the output directory `outputDir`. |

Usage
-----

    usage: ./ssg.tcl <command> [options] [inputDir [outputDir]]

`inputDir` specifies the directory where the input for Tclssg is located. It defaults to `website/input` in the current directory.
`outputDir` is where the static website's files are placed when generated. It defaults to `website/output` when neither `inputDir` nor `outputDir` is supplied on the command line; if `inputDir` is supplied but not `outputDir` then Tclssg will use the value of the variable `outputDir` in the configuration file `inputDir/website.conf`.

Possible commands are

* `init [--templates]` — сreate new project from the default project skeleton (a starting point for Tclssg websites contained in the `skeleton` directory).

> The option `--templates` will make `init` copy the template files from the project skeleton into a subdirectory named `templates` in `inputDir`. You should only use it if you intend to customize your page's layout (HTML code); it is not necessary if you only intend to customize the websites' look using CSS.

>By default your project will use the page template from the project skeleton directly. Not keeping a separate copy of the template is a good idea because it means you won't have to update it manually when a new version of Tclssg introduces changes to templating (which at this point in development it may).

* `build` — build a static website in `outputDir` based on the data in `inputDir`.
* `clean` — delete all files in `outputDir`.
* `update [--templates]` — replace static files in `inputDir` that have matching ones in the project skeleton with those in the project skeleton. Do the same with templates if the option `--templates` is given. Tclssg will prompt you whether to replace each file. This is used to update your website project when Tclssg itself is updated.
* `deploy-copy` — copy files to the destination set in the configuration file (`website.conf`).This can be used, e.g., if your build machine is your web server or if you have the server's documents directory mounted as a local path.
* `deploy-ftp` — deploy files to the FTP server according to the settings specified in the configuration file.
* `open` — open the index page in the default browser.

The default layout of the input directory is

    .
    ├── pages <-- Markdown files from which HTML is generated.
    │   ├── blog <-- Blog posts.
    │   │   └── index.md <-- Blog index page with tag list
    │   │                    and links to blog posts.
    │   ├── index.md <-- Website index page.
    ├── static <-- Files copied verbatim to the output
    │   │          directory.
    │   └── main.css
    ├── templates <-- The website's layout templates (HTML + Tcl).
    │   ├── article.thtml
    │   └── bootstrap.thtml
    │
    └── website.conf <-- Configurating file.

Once you've initialized your website project with `init` you can customize it by specifying general and per-page settings. Specify its general settings by setting variables in `website.conf` and the per-page settings by setting variables in the individual page files.

Website settings
----------------

The following settings are specified in the file `website.conf` in `inputDir` and affect all pages. The format of `website.conf` is as follows:

    variableNameOne short_value
    variableNameTwo {A variable value with spaces.}

| Variable name | Example value(s) | Description |
|---------------|------------------|-------------|
| websiteTitle | `{My Awesome Website}` | Appended to the `<title>` tag of every page. E.g., in this example if `pageTitle` of a page is `{Hello!}` the `<title>` tag will say "Hello! &#124; My Awesome Website".  |
| url | `{http://example.com/}` | Currently not used. |
| outputDir | `../output`, `/var/www/` | The destination directory under which HTML output is produced if no `outputDir` is given in the command line arguments. Relative paths are taken as relative to `inputDir`; if `outputDir` is set to `../output` and you run Tclssg with the command line arguments `build myproject/input` the effective output directory will be `myproject/output`. |
| articleTemplateFileName | `article.thtml` | The article template define what goes between the `<article>...</article>` tags for each page. If none is specified then `default.thtml` is used. Tclssg looks for templates in `inputDir/templates` first then in the `templates` subdirectory of the project skeleton.  |
| documentTemplateFileName | `article.thtml` | The document template define the HTML document structure (expect for article structure). If none is specified then `default.thtml` is used. Tclssg looks for templates in `inputDir/templates` first then in the `templates` subdirectory of the project skeleton. |
| deployCopyPath | `{/var/www/}` | The location to copy the output (the generated static website) to when the command `deploy-copy` is given. |
| deployFtpServer | `{ftp.hosting.example.net}` | The server to deploy the static website to when the command `deploy-ftp` is given. |
| deployFtpPort | `21` | FTP server port. |
| deployFtpPath | `{htdocs}` | The directory on the FTP server where to deploy the static website. |
| deployFtpUser | `{user}` | FTP user name. |
| deployFtpPassword | `{password}` | FTP password. Not displayed in Tclssg output. |
| expandMacrosInPages | 0/1 | Whether template macros in the format of `<% tclcommand args %>` are allowed in pages. |
| charset | `utf-8` | The pages' character set. |
| indexPage | `{index.md}` | The page normal pages will have a link back to. |
| blogIndexPage | `{blog/index.md}` | |
| blogPostsPerDocument | 10 | How many of the latest posts go on a page of the blog index. |
| tagPage | `{blog/index.md}` | The "tag page", i.e., the one that all tags on blog posts link to. Enable `showTagCloud` on the tag page. |
| copyright | `{Copyright (C) 2014 You}` | A copyright line to display in the footer. |

All 0/1 settings default to `0`.

Per-page settings
------------------
A page variable alters a setting for just the page it is set on. Page variables are set in the page source file (e.g., `{index.md}`), each one on a separate line that starts with `!` (an exclamation mark) and has the form of `! variableName {Value}`. Those lines are normally placed at the top of the page source file but can be placed anywhere in the file. Example usage:

    ! variableNameOne short_value
    ! variableNameTwo {A variable value with spaces.}
    Lorem ipsum... (The rest of the page content follows.)

Variables that have an effect for any page:

| Variable name | Example value(s) | Description |
|---------------|------------------|-------------|
| pageTitle | `{Some title}` | Title of the individual page. By default it goes in the `<title>` tag and the article header at the top of the page. It is also used as the text for sidebar/tag cloud links to the page. |
| hideTitle | 0/1 | Do not put `pageTitle` in the `<title>` tag and do not display it at the top of the page. The page title will then only be used for sidebar/tag cloud links to the page. |
| blogPost | 0/1 | If this is set to 1 the page will be a blog post. It will show in the blog post list. |
| date | `2014`, `2014/06/23`, `2014-06-23`, `2014-06-23 14:35`, `2014-06-23 14:35:01` | . Blog posts are sorted on the `date` field. The date must be in a [ISO 8601](https://en.wikipedia.org/wiki/ISO_8601)-like format of year-month-day-hour-minute. Dashes, spaces, colons, slashes, dots and `T` are all treated the same for sorting, so `2014-06-23T14:35:01` is equivalent to `2014 06 23 14 35 01`. |
| headExtra | `{<link rel="stylesheet" href="./page-specific.css">}` | Line to append to `<head>`. |
| hideFooter | 0/1 | Disable the "Powered by" footer. The copyright notice, if enabled, is still displayed. |

Variables that only have an effect for blog posts:

| Variable name | Example value(s) | Description |
|---------------|------------------|-------------|
| hideFromSidebar | 0/1 | Unlists the post from other posts' sidebar. |
| hideSidebar | 0/1 | Don't show the sidebar *on the present page.* |
| hidePostTags | 0/1 | Don't show whatever tags the present blog post has. |
| showTagCloud | 0/1 | Show the list of all tags and links to those blog posts that have each. Presently does not actually look like a cloud. |
| tags | `{tag1 tag2 {tag three with multiple words} {tag four} tag-five}` | Blog post tags for categorization. Each tag will link to the page `tagPage`. |

Like with website settings all 0/1 settings default to `0`.

Page variable values set as shown above can't exceed a single line. For multiline page variable values set `expandMacrosInPages` to `1` and put a macro like the following in the page:

    <%
    dict set pages $currentPageId variables headExtra {
        <link rel="stylesheet"
        href="./contact.css">
    }
    return
    %>

You can also use macros to manipulate website variables like the website title or the copyright notice just for the current page:

    <%
    set websiteTitle blah
    return
    %>

FAQ
---

Answers to question about Tclssg can be on the [FAQ wiki page](https://github.com/dbohdan/tclssg/wiki/FAQ).

Sample use session
------------------

    $ ./ssg.tcl build
    Loaded config file:
        websiteTitle Danyil Bohdan
        url http://danyilbohdan.com/
        deployCopyPath /tmp/dest
        deployFtpServer ftp.<webhost>.com
        deployFtpPath danyilbohdan.com
        deployFtpUser dbohdan
        deployFtpPassword ***
        expandMacrosInPages 0
        indexPage index.md
        tagPage blog/index.md
    processing page file website/input/pages/contact.md into website/output/contact.html
    processing page file website/input/pages/index.md into website/output/index.html
    processing page file website/input/pages/total.md into website/output/total.html
    processing page file website/input/pages/blog/index.md into website/output/blog/index.html
    copying file website/input/static/main.css to website/output/main.css
    copying file website/input/static/contact.css to website/output/contact.css
    $ ./ssg.tcl deploy-ftp
    Loaded config file:
        websiteTitle Danyil Bohdan
        url http://danyilbohdan.com/
        deployCopyPath /tmp/dest
        deployFtpServer ftp.<webhost>.com
        deployFtpPath danyilbohdan.com
        deployFtpUser dbohdan
        deployFtpPassword ***
        expandMacrosInPages 0
        indexPage index.md
        tagPage blog/index.md
    uploading website/output/index.html as danyilbohdan.com/index.html
    uploading website/output/total.html as danyilbohdan.com/total.html
    uploading website/output/contact.html as danyilbohdan.com/contact.html
    uploading website/output/main.css as danyilbohdan.com/main.css
    uploading website/output/contact.css as danyilbohdan.com/contact.css
    uploading website/output/blog/index.html as danyilbohdan.com/blog/index.html

(The password value is automatically replaced with "***" in Tclssg log output.)

License
-------

MIT. See the file `LICENSE` for details.

Markdown 1.0.1 is copyright (c) 2004 John Gruber and is distributed under a three-clause BSD license. See `external/Markdown_1.0.1/License.text`.

Bootstrap 3.2.0 is copyright (c) 2011-2014 Twitter, Inc and is distributed under the MIT license. See `skeleton/static/external/bootstrap-3.2.0-dist/LICENSE`.
