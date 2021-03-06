#!/usr/bin/env tclsh
# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.
package require Tcl 8.5
package require msgcat
package require struct
package require fileutil
package require textutil
package require html
package require sqlite3

set PROFILE 0
if {$PROFILE} {
    package require profiler
    ::profiler::init
}

# Code conventions:
#
# Only use spaces for indentation. Keep the line width for code outside of
# templates under 80 characters.
#
# Procedures ("procs") have names-like-this; variables have namesLikeThis. "!"
# at the end of a proc's name means the proc modifies one or more of the
# variables it is passed by name (e.g., "unqueue!"). "?" in the same position
# means it returns a true/false value.

namespace eval tclssg {
    namespace export *
    namespace ensemble create

    variable version 1.0.0b
    variable debugMode 1

    proc version {} {
        variable version
        return $version
    }

    proc configure {{scriptLocation .}} {
        # What follows is the configuration that is generally not supposed to
        # vary from project to project.
        set ::tclssg::config(scriptLocation) $scriptLocation

        # Source utility functions.
        source [file join $::tclssg::config(scriptLocation) utils.tcl]

        set ::tclssg::config(version) $::tclssg::version

        # Change the lines below to replace the Markdown package with, e.g.,
        # sundown.
        #set ::tclssg::config(markdownProcessor) /usr/local/bin/sundown
        set ::tclssg::config(markdownProcessor) :internal:

        global auto_path
        lappend auto_path [file join $::tclssg::config(scriptLocation) external]

        # Source Markdown if needed.
        if {$::tclssg::config(markdownProcessor) eq ":internal:"} {
            package require Markdown
        }

        set ::tclssg::config(contentDirName) pages
        set ::tclssg::config(templateDirName) templates
        set ::tclssg::config(staticDirName) static
        set ::tclssg::config(articleTemplateFilename) article.thtml
        set ::tclssg::config(documentTemplateFilename) bootstrap.thtml
        set ::tclssg::config(rssArticleTemplateFilename) rss-article.txml
        set ::tclssg::config(rssDocumentTemplateFilename) rss-feed.txml
        set ::tclssg::config(websiteConfigFilename) website.conf
        set ::tclssg::config(skeletonDir) \
                [file join $::tclssg::config(scriptLocation) skeleton]
        set ::tclssg::config(defaultInputDir) [file join "website" "input"]
        set ::tclssg::config(defaultOutputDir) [file join "website" "output"]
        set ::tclssg::config(defaultDebugDir) [file join "website" "debug"]

        set ::tclssg::config(templateBrackets) {<% %>}

        return
    }

    # Procedures that are used for conversion of templates and Markdown into
    # HTML data.
    namespace eval templating {
        namespace export *
        namespace ensemble create

        # Convert raw Markdown to HTML.
        proc markdown-to-html {markdown} {
            set markdownProcessor $::tclssg::config(markdownProcessor)
            if {$markdownProcessor eq ":internal:"} {
                ::Markdown::convert $markdown
            } else {
                exec -- {*}$markdownProcessor << $markdown
            }
        }

        proc inline-markdown-to-html {text} {
            set html [markdown-to-html $text]
            # strip paragraph wrapping, we assume to be in an inline context.
            regexp {<p>(.*)</p>} $html -> html
            return $html
        }

        # Make HTML out of rawContent (remove frontmatter, if any; expand macros
        # if expandMacrosInPages is enabled in websiteConfig; convert Markdown
        # to HTML).
        proc prepare-content {rawContent id {extraVariables {}}} {
            set choppedContent \
                    [lindex [::tclssg::utils::get-page-settings $rawContent] 1]
            # Macroexpand content if needed then convert it from Markdown to
            # HTML.
            if {[tclssg pages get-website-config-setting \
                        expandMacrosInPages 0]} {
                set choppedContent [join [list \
                        [::tclssg::utils::trim-indentation \
                                [tclssg pages get-setting $id pagePrelude ""]] \
                        $choppedContent] "\n"]

                tclssg debugger save-intermediate-id \
                        $id content-1-toexpand $choppedContent
                set choppedContent [interpreter expand \
                        $choppedContent \
                        $id \
                        $extraVariables]
            }

            set cookedContent [markdown-to-html $choppedContent]

            tclssg debugger save-intermediate-id \
                    $id content-2-markdown $choppedContent
            tclssg debugger save-intermediate-id \
                    $id content-3-html $cookedContent

            return $cookedContent
        }

        # Expand template substituting in (already HTMLized) content from
        # cookedContent according to the settings in pageData. This is just
        # a wrapper for [interpreter expand] for now.
        proc apply-template {template cookedContent id {extraVariables {}}} {
            set result [interpreter expand \
                    $template \
                    $id \
                    [list content $cookedContent {*}$extraVariables]]
            return $result
        }

        # Wrapper for a safe interpreter for templates.
        namespace eval interpreter {
            namespace export *
            namespace ensemble create

            # Set variable $key to $value in the template interpreter for each
            # key-value pair in a dictionary.
            proc inject {dictionary} {
                dict for {key value} $dictionary {
                    var-set $key $value
                }
            }

            # Set up the template interpreter.
            proc up {inputDir} {
                # Create a safe interpreter to use for expanding templates (the
                # template interpreter).
                interp create -safe templateInterp
                # A command to set variable $name to $value in the template
                # interpreter.
                interp alias {} [namespace current]::var-set templateInterp set

                # Alias commands to be used in templates.
                foreach {command alias} {
                    ::tclssg::version                   tclssg-version
                    ::tclssg::utils::replace-path-root  replace-path-root
                    ::tclssg::utils::dict-default-get   dict-default-get
                    ::textutil::indent                  ::textutil::indent
                    ::tclssg::utils::slugify            slugify
                    ::tclssg::utils::choose-dir         choose-dir
                    puts                                puts
                    ::tclssg::templating::inline-markdown-to-html
                                                        markdown-to-html
                    ::tclssg::templating::interpreter::with-cache
                                                        with-cache-for-filename
                    ::tclssg::pages::get-setting        get-page-setting
                    ::tclssg::pages::get-data           get-page-data
                    ::tclssg::pages::get-website-config-setting
                                                    get-website-config-setting
                    ::tclssg::pages::get-tag-list       get-tag-list
                    ::tclssg::pages::get-link           get-page-link
                    ::tclssg::pages::get-tags           get-page-tags
                    ::tclssg::pages::get-tag-page       get-tag-page
                    ::msgcat::mc                        mc
                    ::msgcat::mcset                     mcset
                    ::msgcat::mclocale                  mclocale
                    ::html::html_entities               entities
                } {
                    interp alias templateInterp $alias {} {*}$command
                }

                # Expose built-ins.
                foreach builtIn {source} {
                    interp expose templateInterp $builtIn
                }

                # Allow templates to source Tcl files with directory failover
                # with the command interp-source.
                interp alias templateInterp interp-source {} \
                        ::tclssg::templating::interpreter::source-dirs [
                            list [
                                file join $inputDir \
                                          $::tclssg::config(templateDirName)
                            ] [
                                file join $::tclssg::config(skeletonDir) \
                                          $::tclssg::config(templateDirName)
                            ]
                        ]
            }

            # Tear down the template interpreter.
            proc down {} {
                interp delete templateInterp
            }

            # Source file $filename into templateInterp from the first directory
            # where it exists out of those in dirs.
            proc source-dirs {dirs filename} {
                set command [
                    subst -nocommands {
                        source [
                            choose-dir $filename {$dirs}
                        ]
                    }
                ]
                interp eval templateInterp $command
            }

            # Expand template for page pageData.
            proc expand {template id {extraVariables {}}} {
                up [tclssg pages get-website-config-setting inputDir ""]
                var-set currentPageId $id
                inject $extraVariables
                set listing [parse $template]
                set result [interp eval templateInterp $listing]
                down
                return $result
            }

            # Convert a template into Tcl code.
            # Inspired by tmpl_parser by Kanryu KATO (http://wiki.tcl.tk/20363).
            proc parse {template} {
                set result {}
                set regExpr {^(.*?)<%(.*?)%>(.*)$}
                set listing "set _output {}\n"
                while {[regexp $regExpr $template \
                        match preceding token template]} {
                    append listing [list append _output $preceding]\n
                    # Process <%= ... %> (expression), <%! ... %> (command)
                    # and <% ... %> (raw code) syntax.
                    switch -exact -- [string index $token 0] {
                        = {
                            append listing \
                                    [format {append _output [expr %s]} \
                                            [list [string range $token 1 end]]]
                        }
                        ! {
                            append listing \
                                    [format {append _output [%s]} \
                                            [string range $token 1 end]]
                        }
                        default {
                            append listing $token
                        }
                    }
                    append listing \n
                }
                append listing [list append _output $template]\n
                return $listing
            }

            # Run $script and cache the result. Return that result immediately
            # if the script has already been run for $outputFile.
            proc with-cache {outputFile script} {
                set result {}
                if {![[namespace parent]::cache::retrieve-key! \
                            $outputFile $script result]} {
                    set result [interp eval templateInterp $script]
                    [namespace parent]::cache::update-key \
                            $outputFile $script result
                }
                return $result
            }
        } ;# namespace interpreter

        # Provides a cache for data that doesn't vary between files in one
        # directory.
        namespace eval cache {
            namespace export *
            namespace ensemble create

            variable cachedFile {}
            variable data {}

            # Check if the cache is fresh for file newFile. Fresh in our case
            # means it is either the same file or a file located in the same
            # directory (because relative link paths for the sidebar and the tag
            # cloud are the same for such files, and that is what the cache is
            # used for).
            proc fresh? {newFile} {
                variable cachedFile
                variable data

                set result [expr {
                    [file dirname $cachedFile] eq [file dirname $newFile]
                }]
                return $result
            }

            proc filename {} {
                variable cachedFile
                return $cachedFile
            }

            # Update cache item $key. If the rest of the cache is no longer
            # fresh discard it.
            proc update-key {newFile key varName} {
                variable cachedFile
                variable data

                upvar 1 $varName var

                if {![fresh? $newFile]} {
                    set data {}
                    set cachedFile $newFile
                }
                dict set data $key $var
            }

            # Use varName as the key in update-key.
            proc update {newFile varName} {
                upvar 1 $varName localVar
                update-key $newFile $varName localVar
            }

            # If fresh for newFile retrieve the cached value under key and put
            # it in variable varName.
            proc retrieve-key! {newFile key varName} {
                upvar 1 $varName var

                variable data

                if {![fresh? $newFile] || ![dict exists $data $key]} {
                    return 0
                }
                set var [dict get $data $key]
                return 1
            }

            # Use varName as key for retrieve-key!.
            proc retrieve! {newFile varName} {
                upvar 1 $varName localVar
                retrieve-key! $newFile $varName localVar
            }
         } ;# namespace cache
    } ;# namespace templating

    # Website page database. Provides procs to interact with SQLite tables that
    # hold the input and intermediate data.
    namespace eval pages {
        namespace export *
        namespace ensemble create

        # Create tables necessary for various procs called by Tclssg's build
        # command.
        #
        # What follows is a very short description of the each table's
        # respective contents in the format of "<table name> -- <contents>":
        #
        # pages -- page data for every page. Page data is the information about
        # the page that is *not* set by the user directly in preamble
        # (settings) section of the page file.
        # links -- relative hyperlink HREFs to link from page $id to page
        # $targetId.
        # settings -- page settings for every page.
        # websiteConfig -- website-wide settings.
        # tags -- blog post tags for every blog post.
        # tagPages -- a list of tag pages for every tag. See add-tag-pages.
        proc init {} {
            sqlite3 tclssg-db :memory:
            # Do not store settings values as columns to allow pages to set
            # custom settings. These settings can then be parsed by templates
            # without changes to the static site generator source itself.
            tclssg-db eval {
                CREATE TABLE pages(
                    id INTEGER PRIMARY KEY,
                    inputFile TEXT,
                    outputFile TEXT,
                    rawContent TEXT,
                    cookedContent TEXT,
                    pageLinks TEXT,
                    rootDirPath TEXT,
                    articlesToAppend TEXT,
                    sortingDate INTEGER
                );
                CREATE TABLE links(
                    id INTEGER,
                    targetId INTEGER,
                    link TEXT,
                    PRIMARY KEY (id, targetId)
                );
                CREATE TABLE settings(
                    id INTEGER,
                    name TEXT,
                    value TEXT,
                    PRIMARY KEY (id, name)
                );
                CREATE TABLE websiteConfig(
                    name TEXT PRIMARY KEY,
                    value TEXT
                );
                CREATE TABLE tags(
                    id INTEGER,
                    tag TEXT
                );
                CREATE TABLE tagPages(
                    tag TEXT,
                    pageNumber INTEGER,
                    id INTEGER,
                    PRIMARY KEY (tag, pageNumber)
                );
            }
        }


        # Procs for working with the table "pages".


        proc add {inputFile outputFile rawContent cookedContent sortingDate} {
            if {![string is integer -strict $sortingDate]} {
                set sortingDate 0
            }
            tclssg-db eval {
                INSERT INTO pages(
                    inputFile,
                    outputFile,
                    rawContent,
                    cookedContent,
                    sortingDate)
                VALUES (
                    $inputFile,
                    $outputFile,
                    $rawContent,
                    $cookedContent,
                    $sortingDate);
            }
            return [tclssg-db last_insert_rowid]
        }
        # Make a copy of page $id in table pages return the id of the copy.
        proc copy {id copySettings} {
            tclssg-db eval {
                INSERT INTO pages(
                    inputFile,
                    outputFile,
                    rawContent,
                    cookedContent,
                    rootDirPath,
                    articlesToAppend,
                    sortingDate)
                SELECT
                    inputFile,
                    outputFile,
                    rawContent,
                    cookedContent,
                    rootDirPath,
                    articlesToAppend,
                    sortingDate
                FROM pages WHERE id = $id;
            }
            set newPageId [tclssg-db last_insert_rowid]
            tclssg-db eval {
                INSERT INTO links(
                    id,
                    targetId,
                    link)
                SELECT
                    $newPageId,
                    targetId,
                    link
                FROM links WHERE id = $id;
            }
            if {$copySettings} {
                tclssg-db eval {
                    INSERT INTO settings(
                        id,
                        name,
                        value)
                    SELECT
                        $newPageId,
                        name,
                        value
                    FROM settings WHERE id = $id;
                }
            }
            return $newPageId
        }
        proc delete {id} {
            tclssg-db transaction {
                tclssg-db eval {
                     DELETE FROM pages WHERE id = $id;
                }
                tclssg-db eval {
                    DELETE FROM links WHERE id = $id;
                }
                tclssg-db eval {
                    DELETE FROM settings WHERE id = $id;
                }
            }
        }
        proc set-data {id field value} {
            # TODO: get rid of format?
            if {![regexp {^[a-zA-Z0-9]+$} $field]} {
                # A very simple failsafe.
                error "wrong field name: $field"
            }
            tclssg-db eval [format {
                UPDATE pages SET %s=$value WHERE id = $id;
            } $field]
        }
        proc get-data {id field {default ""}} {
            tclssg-db eval {
                SELECT * FROM pages WHERE id = $id;
            } arr {}
            if {[info exists arr($field)]} {
                return $arr($field)
            } else {
                return $default
            }
        }
        # Returns the list of ids of all pages sorted by their sortingDate, if
        # any.
        proc sorted-by-date {} {
            set result [tclssg-db eval {
                SELECT id FROM pages ORDER BY sortingDate DESC;
            }]
            return $result
        }
        proc input-file-to-id {filename} {
            set result [tclssg-db eval {
                SELECT id FROM pages WHERE inputFile = $filename LIMIT 1;
            }]
            return $result
        }
        proc output-file-to-id {filename} {
            set result [tclssg-db eval {
                SELECT id FROM pages WHERE outputFile = $filename LIMIT 1;
            }]
            return $result
        }

        # Procs for working with the table "links".


        proc add-link {sourceId targetId link} {
            tclssg-db eval {
                INSERT INTO links(id, targetId, link)
                VALUES ($sourceId, $targetId, $link);
            }
        }
        proc get-link {sourceId targetId} {
            set result [lindex [tclssg-db eval {
                SELECT link FROM links
                WHERE id = $sourceId AND targetId = $targetId;
            }] 0]
            return $result
        }
        proc copy-links {oldId newId} {
            set result [tclssg-db eval {
                INSERT INTO links(id, targetId, link)
                SELECT $newId, targetId, link FROM links
                WHERE id = $oldId;
            }]
            return $result
        }
        proc delete-links-to {targetId} {
            tclssg-db eval {
                DELETE FROM links
                WHERE targetId = $targetId;
            }
        }

        # Procs for working with the table "settings".


        proc set-setting {id name value} {
            tclssg-db eval {
                INSERT OR REPLACE INTO settings(id, name, value)
                VALUES ($id, $name, $value);
            }
        }
        proc get-setting {id name default {pageSettingsFailover 1}} {
            if {$pageSettingsFailover} {
                set default [::tclssg::utils::dict-default-get \
                        $default \
                        [get-website-config-setting pageSettings {}] \
                        $name]
                # Avoid an infinite loop when recursing by disabling failover.
                set isBlogPost [get-setting $id blogPost 0 0]
                if {$isBlogPost} {
                    set default [::tclssg::utils::dict-default-get \
                            $default \
                            [get-website-config-setting blogPostSettings {}] \
                            $name]
                }
            }

            set result [lindex [tclssg-db eval {
                SELECT ifnull(max(value), $default) FROM settings
                WHERE id = $id AND name = $name;
            }] 0]
            return $result
        }


        # Procs for working with the table "websiteConfig".


        proc set-website-config-setting {name value} {
            tclssg-db eval {
                INSERT OR REPLACE INTO websiteConfig(name, value)
                VALUES ($name, $value);
            }
        }
        proc get-website-config-setting {name default} {
            set result [lindex [tclssg-db eval {
                SELECT ifnull(max(value), $default) FROM websiteConfig
                WHERE name = $name;
            }] 0]
            return $result
        }


        # Procs for working with the tables "tags" and "tagPages".


        proc add-tags {id tagList} {
            foreach tag $tagList {
                tclssg-db eval {
                    INSERT INTO tags(id, tag)
                    VALUES ($id, $tag);
                }
            }
        }
        proc get-tags {id} {
            set result [tclssg-db eval {
                SELECT tag FROM tags WHERE id = $id;
            }]
            return $result
        }
        proc get-tag-page {tag pageNumber} {
            set result [tclssg-db eval {
                SELECT id FROM tagPages
                WHERE tag = $tag AND pageNumber = $pageNumber;
            }]
            return $result
        }
        proc add-tag-page {id tag pageNumber} {
            tclssg-db eval {
                INSERT INTO tagPages(tag, pageNumber, id)
                VALUES ($tag, $pageNumber, $id);
            }
        }
        # Return pages with tag $tag.
        proc with-tag {tag} {
            set result [tclssg-db eval {
                SELECT pages.id FROM pages
                JOIN tags ON tags.id = pages.id
                WHERE tag = $tag
                ORDER BY sortingDate DESC;
            }]
            return $result
        }
        # Return a list of all tags sorted by name or frequency.
        proc get-tag-list {{sortBy "name"} {limit -1}} {
            switch -exact -- $sortBy {
                frequency {
                    set result [tclssg-db eval {
                        SELECT DISTINCT tag FROM tags
                        GROUP BY tag ORDER BY count(id) DESC
                        LIMIT $limit;
                    }]
                }
                name {
                    set result [tclssg-db eval {
                        SELECT DISTINCT tag FROM tags ORDER BY tag LIMIT $limit;
                    }]
                }
                default {
                    error "unknown tag sorting option: $sortBy"
                }
            }
            return $result
        }
    } ;# namespace pages

    # Data dumping facilities to help debug templates and Tclssg itself.
    namespace eval debugger {
        namespace export *
        namespace ensemble create

        # When active intermediate results of processing are saved to $debugDir
        # for analysis. To enable pass the command line option "--debug" to
        # when building a project.
        variable dumpIntermediates 0

        variable inputDirSetting
        variable debugDirSetting

        variable previousFilename {}

        proc enable {} {
            variable dumpIntermediates
            set dumpIntermediates 1
        }

        proc init {inputDir debugDir} {
            variable inputDirSetting
            variable debugDirSetting
            set inputDirSetting $inputDir
            set debugDirSetting $debugDir
        }

        # Save $data for file $filename in the debug directory with filename
        # suffix $suffix.
        proc save-intermediate {filename suffix data} {
            variable dumpIntermediates
            if {!$dumpIntermediates} {
                return
            }
            variable inputDirSetting
            variable debugDirSetting
            variable previousFilename

            set dest "[::tclssg::utils::replace-path-root \
                    $filename $inputDirSetting $debugDirSetting].$suffix"
            if {$filename ne $previousFilename} {
                puts "    saving intermediate stage $suffix of\
                        $filename to $dest"
            } else {
                puts "        saving stage $suffix to $dest"
            }

            fileutil::writeFile $dest $data
            set previousFilename $filename
            return
        }

        # Same as save-intermediate but gets the filename from the pages
        # database.
        proc save-intermediate-id {id suffix data} {
            return [save-intermediate \
                    [tclssg pages get-data $id inputFile] \
                    $suffix \
                    $data]
        }
    } ;# debugger

    # Make one HTML article (HTML content enclosed in an <article>...</article>
    # tag) out of the content of page $id according to an article template.
    proc format-article {id articleTemplate {abbreviate 0} \
            {extraVariables {}}} {
        set cookedContent [tclssg pages get-data $id cookedContent]
        templating apply-template $articleTemplate $cookedContent \
                $id [list abbreviate $abbreviate {*}$extraVariables]
    }

    # Format an HTML document according to a document template. The document
    # content is taken from the variable content while page settings are taken
    # from pageData. This design allow you to make a document with custom
    # content, e.g., one with the content of multiple articles.
    proc format-document {content id documentTemplate} {
        templating apply-template $documentTemplate $content $id
    }

    # Generate an HTML document out of the pages listed in pageIds and
    # store it as $outputFile. The page data corresponding to the ids in
    # pageIds must be present in pages database table.
    proc generate-html-file {outputFile topPageId articleTemplate
            documentTemplate {extraVariables {}}} {
        set inputFiles {}
        set gen {} ;# article content accumulator
        set first 1

        set pageIds [list $topPageId \
                {*}[tclssg pages get-data $topPageId articlesToAppend {}]]
        set isCollection [expr {[llength $pageIds] > 1}]

        foreach id $pageIds {
            append gen [format-article $id $articleTemplate [expr {!$first}] \
                    [list collectionPageId $topPageId \
                            collectionTopArticle \
                                    [expr {$isCollection && $first}] \
                            collection $isCollection \
                            {*}$extraVariables]]
            lappend inputFiles [tclssg pages get-data $id inputFile]
            set first 0
        }

        set subdir [file dirname $outputFile]

        if {![file isdir $subdir]} {
            puts "creating directory $subdir"
            file mkdir $subdir
        }

        puts "processing page file [lindex $inputFiles 0] into $outputFile"
        # Take page settings form the first page.
        set output [
            format-document $gen $topPageId $documentTemplate
        ]
        ::fileutil::writeFile $outputFile $output
    }

    # Read the template named in $varName from $inputDir or (if it is not found
    # in $inputDir) from ::tclssg::config(skeletonDir). The name resolution
    # scheme is a bit convoluted right now. It can later be made per-directory
    # or metadata-based.
    proc read-template-file {inputDir varName} {
        set templateFile [
            ::tclssg::utils::choose-dir [
                tclssg pages get-website-config-setting \
                        $varName \
                        $::tclssg::config($varName)
            ] [
                list [file join $inputDir $::tclssg::config(templateDirName)] \
                        [file join $::tclssg::config(skeletonDir) \
                              $::tclssg::config(templateDirName)]
            ]
        ]
        return [read-file $templateFile]
    }

    # Add one page or a series of pages that collect the articles of those pages
    # that are listed in pageIds. The number of pages added equals ([llength
    # pageIds] / $blogPostsPerFile) rounded up to the nearest whole number. Page
    # settings are taken from the page $topPageId and its content is prepended
    # to every output page. Used for making the blog index page.
    proc add-article-collection {pageIds topPageId} {
        set blogPostsPerFile [tclssg pages get-website-config-setting \
                blogPostsPerFile 10]
        set i 0
        set currentPageArticles {}
        set pageNumber 0
        set resultIds {}

        # Filter out pages to that set hideFromCollections to 1.
        set pageIds [::struct::list filterfor x $pageIds {
            ($x ne $topPageId) &&
            ![tclssg pages get-setting $x hideFromCollections 0]
        }]

        set prevIndexPageId {}
        set topPageOutputFile [tclssg pages get-data $topPageId outputFile]

        foreach id $pageIds {
            lappend currentPageArticles $id
            # If there is enough posts for a page or this is the last post...
            if {($i == $blogPostsPerFile - 1) ||
                    ($id eq [lindex $pageIds end])} {

                set newInputFile \
                        [::tclssg::utils::add-number-before-extension \
                                [tclssg pages get-data $topPageId inputFile] \
                                [expr {$pageNumber + 1}] {-%d} 1]
                set newOutputFile \
                        [::tclssg::utils::add-number-before-extension \
                                [tclssg pages get-data $topPageId outputFile] \
                                [expr {$pageNumber + 1}] {-%d} 1]
                set newId [tclssg pages copy $topPageId 1]

                puts -nonewline "adding article collection $newInputFile"
                tclssg pages set-data \
                        $newId \
                        inputFile \
                        $newInputFile
                tclssg pages set-data \
                        $newId \
                        outputFile \
                        $newOutputFile
                tclssg pages set-data \
                        $newId \
                        articlesToAppend \
                        $currentPageArticles

                if {$pageNumber > 0} {
                    tclssg pages set-setting $newId \
                            prevPage $prevIndexPageId
                    tclssg pages set-setting $prevIndexPageId \
                            nextPage $newId
                }

                tclssg pages set-setting $newId pageNumber $pageNumber

                puts " with posts [list [::struct::list mapfor x \
                        $currentPageArticles {tclssg pages get-data \
                                $x inputFile}]]"
                lappend resultIds $newId
                set prevIndexPageId $newId
                set i 0
                set currentPageArticles {}
                incr pageNumber
            } else {
                incr i
            }
        }
        return $resultIds
    }

    # For each tag add a page that collects the articles tagged with it using
    # add-article-collection.
    proc add-tag-pages {} {
        set tagPageId [tclssg pages get-website-config-setting tagPageId ""]
        if {[string is integer -strict $tagPageId]} {
            foreach tag [tclssg pages get-tag-list] {
                set taggedPages [tclssg pages with-tag $tag]
                set tempPageId [tclssg pages copy $tagPageId 1]
                set toReplace [file rootname \
                        [lindex [file split [tclssg pages get-data \
                                $tempPageId inputFile ""]] end]]
                set replaceWith "tag-[::tclssg::utils::slugify $tag]"
                foreach varName {inputFile outputFile} {
                    tclssg pages set-data \
                            $tempPageId \
                            $varName \
                            [string map \
                                    [list $toReplace $replaceWith] \
                                    [tclssg pages get-data \
                                            $tempPageId $varName ""]]
                }
                set resultIds [add-article-collection $taggedPages $tempPageId]
                tclssg pages delete $tempPageId
                for {set i 0} {$i < [llength $resultIds]} {incr i} {
                    set id [lindex $resultIds $i]
                    tclssg pages add-tag-page $id $tag $i
                    tclssg pages set-setting $id tagPageTag $tag
                }
            }
        }
    }

    # Check the website config for errors that may not be caught elsewhere.
    proc validate-config {inputDir contentDir} {
        # Check that the website URL end with a '/'.
        set url [tclssg pages get-website-config-setting url {}]
        if {($url ne "") && ([string index $url end] ne "/")} {
            error {'url' in the website config does not end with '/'}
        }

        # Check for obsolete settings.
        if {([tclssg pages get-website-config-setting \
                pageVariables {}] ne "")  ||
                ([tclssg pages get-website-config-setting \
                        blogPostVariables {}] ne "")} {
            error "website config settings 'pageVariables' and\
                    'blogPostVariables' have been renamed\
                    'pageSettings' and 'blogPostSettings' respectively."
        }

        # Check that collection top pages actually exist.
        foreach varName {indexPage blogIndexPage tagPage} {
            set value [tclssg pages get-website-config-setting $varName ""]
            set path [file join $contentDir $value]
            if {($value ne "") && (![file exists $path])} {
                error "the file set for $varName in the website config does\
                    not exist: {$value} (actual path checked: $path)"
            }
        }
    }

    # Generate a sitemap for the static website. This requires the setting
    # "url" to be set in the website config.
    proc make-sitemap {outputDir} {
        set header [::tclssg::utils::trim-indentation {
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset
              xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
              xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xsi:schemaLocation="http://www.sitemaps.org/schemas/sitemap/0.9
                    http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd">
        %s</urlset>
        }]

        set entry [::tclssg::utils::trim-indentation {
            <url>
              <loc>%s</loc>%s
            </url>
        }]

        set result ""
        set url [tclssg page get-website-config-setting url ""]
        if {$url eq ""} {
            error "can not generate the sitemap without a base URL specified"
        }
        foreach id [tclssg pages sorted-by-date] {
            # Exclude from the site map pages that are hidden from from
            # collections, blog index page beyond the first and tag pages.
            if {(![tclssg pages get-setting $id hideFromCollections 0]) &&
                    ([tclssg pages get-setting $id prevPage ""] eq "") &&
                    ([tclssg pages get-setting $id tagPageTag ""] eq "")} {
                set date [tclssg pages get-setting $id modifiedDateScanned ""]
                if {![string is integer -strict [lindex $date 0]]} {
                    # No valid modifiedDate, so will just use the sorting date
                    # for when the page was last modified.
                    set date [tclssg pages get-setting $id dateScanned ""]
                }
                if {[string is integer -strict [lindex $date 0]]} {
                    set lastmod "\n  <lastmod>[clock format [lindex $date 0] \
                            -format [lindex $date 1]]</lastmod>"
                } else {
                    set lastmod ""
                }
                append result [format $entry \
                        $url[::fileutil::relative $outputDir \
                                [tclssg pages get-data $id outputFile]] \
                        $lastmod]\n
            }
        }
        set result [format $header $result]
        return $result
    }

    # Synonymous setting names in the page frontmatter.
    variable settingSynonyms [dict create {*}{
        blogPost blog modifiedDate modified
    }]

    # Process input files in $inputDir to produce a static website in
    # $outputDir.
    proc compile-website {inputDir outputDir debugDir websiteConfig} {
        tclssg pages init
        tclssg debugger init $inputDir $debugDir
        foreach {key value} $websiteConfig {
            tclssg pages set-website-config-setting $key $value
        }

        tclssg pages set-website-config-setting inputDir $inputDir
        set contentDir [file join $inputDir $::tclssg::config(contentDirName)]

        validate-config $inputDir $contentDir

        variable settingSynonyms

        # Load the page files into the page database.
        foreach file [::fileutil::findByPattern $contentDir -glob *.md] {
            # May want to change the rawContent preloading behavior for very
            # large (larger than memory) websites.
            set rawContent [read-file $file]
            lassign [::tclssg::utils::get-page-settings $rawContent] \
                settings baseContent

            # Skip pages marked as drafts.
            if {[::tclssg::utils::dict-default-get 0 $settings draft]} {
                continue
            }

            tclssg debugger save-intermediate \
                    $file frontmatter-0-raw.tcl $settings
            tclssg debugger save-intermediate \
                    $file content-0-raw $baseContent

            # Set the values for empty keys to those of their synonym keys, if
            # present.
            foreach {varName synonym} $settingSynonyms {
                if {![dict exists $settings $varName] &&
                        [dict exists $settings $synonym]} {
                    dict set settings $varName [dict get $settings $synonym]
                }
            }

            # Parse date and modifiedDate into a Unix timestamp plus a format
            # string.
            set clockOptions {}
            set timezone [tclssg pages get-website-config-setting timezone ""]
            if {$timezone ne ""} {
                set clockOptions [list -timezone $timezone]
            }
            set dateScanned [::tclssg::utils::incremental-clock-scan \
                    [::tclssg::utils::dict-default-get {} $settings date] \
                    $clockOptions]
            dict set settings dateScanned $dateScanned
            set modifiedDateScanned [::tclssg::utils::incremental-clock-scan \
                    [::tclssg::utils::dict-default-get {} \
                            $settings modifiedDate] \
                    $clockOptions]
            dict set settings modifiedDateScanned $modifiedDateScanned

            # Add the current page to the page database with an appropriate
            # output filename.
            set id_ [tclssg pages add \
                            $file \
                            [file rootname \
                                    [::tclssg::utils::replace-path-root \
                                            $file $contentDir $outputDir]].html\
                            $rawContent \
                            "" \
                            [lindex $dateScanned 0]]

            tclssg pages add-tags $id_ \
                    [::tclssg::utils::dict-default-get {} $settings tags]
            dict unset settings tags

            tclssg debugger save-intermediate \
                    $file frontmatter-1-final.tcl $settings
            foreach {var value} $settings {
                tclssg pages set-setting $id_ $var $value
            }
        }

        # Read template files.
        set articleTemplate [
            read-template-file $inputDir articleTemplateFilename
        ]
        set documentTemplate [
            read-template-file $inputDir documentTemplateFilename
        ]

        # Create a list of pages that are blog posts and a list of blog posts
        # that should be linked to in the blog sidebar.
        set blogPostIds [::struct::list filterfor id \
                [tclssg pages sorted-by-date] \
                {[tclssg pages get-setting $id blogPost 0]}]
        set sidebarPostIds [::struct::list filterfor id \
                $blogPostIds \
                {![tclssg pages get-setting $id hideFromSidebarLinks 0]}]
        tclssg pages set-website-config-setting sidebarPostIds $sidebarPostIds

        # Add numerical ids that correspond to the special pages' input
        # filenames in the config to the database.
        foreach varName {indexPage blogIndexPage tagPage} {
            set value [file join $contentDir \
                    [tclssg pages get-website-config-setting $varName ""]]
            tclssg pages set-website-config-setting ${varName}Id \
                    [tclssg pages input-file-to-id $value]
        }
        # Replace the config outputDir, which may be relative to inputDir, with
        # the actual value of outputDir, which is not.
        tclssg pages set-website-config-setting outputDir $outputDir

        # Add a chronologically ordered blog index.
        set blogIndexPageId \
                [tclssg pages get-website-config-setting blogIndexPageId ""]
        if {$blogIndexPageId ne ""} {
            add-article-collection $blogPostIds $blogIndexPageId
        }

        # Add pages with blog posts collected for each tag that have it.
        add-tag-pages

        # Do not process the pages only meant to be used as the "top" pages for
        # collections: the tag page and the original blog index page. The latter
        # will feature in the database twice if you don't. Do not forget to
        # delete the links to them. The original blog index loaded from the disk
        # will share the outputFile with the first page of the one generated by
        # add-tag-pages meaning the links meant for one may end up pointing at
        # the other. This is really less obscure than it may seem. Update
        # blogIndexPageId to point at the actual blogIndexPageId.
        foreach varName {blogIndexPageId tagPageId} {
            set id [tclssg pages get-website-config-setting $varName {}]
            if {$id ne ""} {
                if {$varName ne "tagPageId"} {
                    set outputFile [tclssg pages get-data $id outputFile ""]
                }
                tclssg pages delete $id
                tclssg pages delete-links-to $id
                if {$varName ne "tagPageId"} {
                    set newId [tclssg pages output-file-to-id $outputFile]
                    tclssg pages set-website-config-setting $varName $newId
                }
            }
        }

        # Process page data into HTML output.
        foreach id [tclssg pages sorted-by-date] {
            set outputFile [tclssg pages get-data $id outputFile]

            # Use the previous list of relative links if the current file is
            # in the same directory as the previous one.
            if {[templating cache retrieve! $outputFile pageLinks]} {
                tclssg pages copy-links \
                        [tclssg pages output-file-to-id \
                                [templating cache filename]] $id
            } else {
                # Compute new pageLinks for the current page. Beware: in the
                # worst case scenario (each page is in its own directory) this
                # gives us n^2 operations for n pages.
                set pageLinks {}
                foreach otherFileId [tclssg pages sorted-by-date] {
                    # pageLinks maps page id (= input FN relative to
                    # $contentDir) to relative link to it.
                    lappend pageLinks $otherFileId \
                            [::fileutil::relative \
                                    [file dirname $outputFile] \
                                    [tclssg pages get-data \
                                            $otherFileId outputFile]]
                }
                templating cache update $outputFile pageLinks
                # Store links to other pages and website root path relative to
                # the current page.
                foreach {targetId link} $pageLinks {
                    tclssg pages add-link $id $targetId $link
                }
            }
            # Relative path to the root directory of the output.
            tclssg pages set-data $id rootDirPath \
                    [::fileutil::relative \
                            [file dirname $outputFile] \
                            $outputDir]

            # Expand templates, first for the article then for the HTML
            # document.

            tclssg pages set-data $id cookedContent [
                templating prepare-content \
                        [tclssg pages get-data $id rawContent] \
                        $id \
            ]

            generate-html-file \
                    [tclssg pages get-data $id outputFile] \
                    $id \
                    $articleTemplate \
                    $documentTemplate
        }

        # Copy static files verbatim.
        ::tclssg::utils::copy-files \
                [file join $inputDir $::tclssg::config(staticDirName)] \
                $outputDir \
                1

        # Generate a sitemap.
        if {[tclssg page get-website-config-setting generateSitemap 0]} {
            set sitemapFile [file join $outputDir sitemap.xml]
            puts "writing sitemap to $sitemapFile"
            ::fileutil::writeFile $sitemapFile [tclssg make-sitemap $outputDir]
        }

        # Generate an RSS feed.
        if {[tclssg page get-website-config-setting generateRssFeed 0]} {
            set rssFeedFilename rss.xml
            tclssg pages set-website-config-setting \
                    rssFeedFilename $rssFeedFilename
            set rssFile [file join $outputDir $rssFeedFilename]
            set rssArticleTemplate \
                    [read-template-file $inputDir rssArticleTemplateFilename]
            set rssDocumentTemplate \
                    [read-template-file $inputDir rssDocumentTemplateFilename]
            puts "writing RSS feed to $rssFile"
            tclssg pages set-website-config-setting buildDate [clock seconds]
            generate-html-file \
                    $rssFile \
                    [tclssg pages \
                            get-website-config-setting blogIndexPageId ""] \
                    $rssArticleTemplate \
                    $rssDocumentTemplate
        }
    }

    # Load the website configuration file from the directory inputDir. Return
    # the raw content of the file without validating it. If $verbose is true
    # print the content.
    proc load-config {inputDir {verbose 1}} {
        set websiteConfig [
            read-file [file join $inputDir \
                    $::tclssg::config(websiteConfigFilename)]
        ]

        # Show loaded config to user (without the password values).
        if {$verbose} {
            puts "Loaded config file:"
            puts [::textutil::indent \
                    [::tclssg::utils::dict-format \
                            [::tclssg::utils::obscure-password-values \
                                    $websiteConfig] \
                            "%s %s\n" \
                            {
                                websiteTitle
                                headExtra
                                bodyExtra
                                start
                                moreText
                                sidebarNote
                            }] \
                    {    }]
        }

        return $websiteConfig
    }

    # Commands that can be given to Tclssg on the command line.
    namespace eval command {
        namespace export *
        namespace ensemble create \
                -prefixes 0 \
                -unknown ::tclssg::command::unknown

        proc init {inputDir outputDir {debugDir {}} {options {}}} {
            foreach dir [
                list $::tclssg::config(contentDirName) \
                     $::tclssg::config(templateDirName) \
                     $::tclssg::config(staticDirName) \
                     [file join $::tclssg::config(contentDirName) blog]
            ] {
                file mkdir [file join $inputDir $dir]
            }
            file mkdir $outputDir

            # Copy project skeleton.
            set skipRegExp [
                if {"templates" in $options} {
                    lindex {}
                } else {
                    lindex {.*templates.*}
                }
            ]
            ::tclssg::utils::copy-files \
                    $::tclssg::config(skeletonDir) $inputDir 0 $skipRegExp
        }

        proc build {inputDir outputDir {debugDir {}} {options {}}} {
            set websiteConfig [::tclssg::load-config $inputDir]

            if {"debug" in $options} {
                tclssg debugger enable
            }

            if {[file isdir $inputDir]} {
                ::tclssg::compile-website $inputDir $outputDir $debugDir \
                        $websiteConfig
            } else {
                error "couldn't access directory \"$inputDir\""
            }
        }

        proc clean {inputDir outputDir {debugDir {}} {options {}}} {
            foreach file [::fileutil::find $outputDir {file isfile}] {
                puts "deleting $file"
                file delete $file
            }
        }

        proc update {inputDir outputDir {debugDir {}} {options {}}} {
            set updateSourceDirs [
                list $::tclssg::config(staticDirName) {static files}
            ]
            if {"templates" in $options} {
                lappend updateSourceDirs \
                        $::tclssg::config(templateDirName) \
                        templates
            }
            if {"yes" in $options} {
                set overwriteMode 1
            } else {
                set overwriteMode 2
            }
            foreach {dir descr} $updateSourceDirs {
                puts "updating $descr"
                ::tclssg::utils::copy-files [
                    file join $::tclssg::config(skeletonDir) $dir
                ] [
                    file join $inputDir $dir
                ] $overwriteMode
            }
        }

        proc deploy-copy {inputDir outputDir {debugDir {}} {options {}}} {
            set websiteConfig [::tclssg::load-config $inputDir]

            set deployDest [dict get $websiteConfig deployCopy path]

            ::tclssg::utils::copy-files $outputDir $deployDest 1
        }

        proc deploy-custom {inputDir outputDir {debugDir {}} {options {}}} {
            proc exec-deploy-command {key} {
                foreach varName {deployCustomCommand outputDir file fileRel} {
                    upvar 1 $varName $varName
                }
                if {[dict exists $deployCustomCommand $key] &&
                    ([dict get $deployCustomCommand $key] ne "")} {
                    set preparedCommand [subst -nocommands \
                            [dict get $deployCustomCommand $key]]
                    set exitStatus 0
                    set error [catch \
                            {set output \
                                [exec -ignorestderr -- {*}$preparedCommand]}\
                            _ \
                            options]
                    if {$error} {
                        set details [dict get $options -errorcode]
                        if {[lindex $details 0] eq "CHILDSTATUS"} {
                            set exitStatus [lindex $details 2]
                        } else {
                            error [dict get $options -errorinfo]
                        }
                    }
                    if {$exitStatus == 0} {
                        if {$output ne ""} {
                            puts $output
                        }
                    } else {
                        puts "command '$preparedCommand' returned exit code\
                                $exitStatus."
                    }
                }
            }
            set websiteConfig [::tclssg::load-config $inputDir]

            set deployCustomCommand \
                    [dict get $websiteConfig deployCustomCommand]

            puts "deploying..."
            exec-deploy-command start
            foreach file [::fileutil::find $outputDir {file isfile}] {
                set fileRel [::fileutil::relative $outputDir $file]
                exec-deploy-command file
            }
            exec-deploy-command end
            puts "done."
        }

        proc deploy-ftp {inputDir outputDir {debugDir {}} {options {}}} {
            set websiteConfig [::tclssg::load-config $inputDir]

            package require ftp
            global errorInfo
            set conn [
                ::ftp::Open \
                        [dict get $websiteConfig deployFtp server] \
                        [dict get $websiteConfig deployFtp user] \
                        [dict get $websiteConfig deployFtp password] \
                        -port [::tclssg::utils::dict-default-get 21 \
                                $websiteConfig deployFtp port] \
                        -mode passive
            ]
            set deployFtpPath [dict get $websiteConfig deployFtp path]

            ::ftp::Type $conn binary

            foreach file [::fileutil::find $outputDir {file isfile}] {
                set destFile [::tclssg::utils::replace-path-root \
                        $file $outputDir $deployFtpPath]
                set path [file split [file dirname $destFile]]
                set partialPath {}

                foreach dir $path {
                    set partialPath [file join $partialPath $dir]
                    if {[::ftp::Cd $conn $partialPath]} {
                        ::ftp::Cd $conn /
                    } else {
                        puts "creating directory $partialPath"
                        ::ftp::MkDir $conn $partialPath
                    }
                }
                puts "uploading $file as $destFile"
                if {![::ftp::Put $conn $file $destFile]} {
                    error "upload error: $errorInfo"
                }
            }
            ::ftp::Close $conn
        }

        proc open {inputDir outputDir {debugDir {}} {options {}}} {
            set websiteConfig [::tclssg::load-config $inputDir]

            package require browse
            ::browse::url [
                file rootname [
                    file join $outputDir [
                        ::tclssg::utils::dict-default-get index.md \
                                $websiteConfig indexPage
                    ]
                ]
            ].html
        }

        proc version {inputDir outputDir {debugDir {}} {options {}}} {
            puts $::tclssg::config(version)
        }

        proc help {{inputDir ""} {outputDir ""} {debugDir ""} {options ""}} {
            global argv0

            # Format: {command description {option optionDescription ...} ...}.
            set commandHelp [list {*}{
                init {create a new project by cloning the default project\
                        skeleton} {
                    --templates {copy template files from the project skeleton\
                            to inputDir}
                }
                build {build the static website} {
                    --debug {dump the results of intermediate stages of content\
                        processing to disk}
                }
                clean {delete all files in outputDir} {}
                update {update the inputDir for a new version of Tclssg by\
                        copying the static files (e.g., CSS) of the project\
                        skeleton over the static files in inputDir and having\
                        the user confirm replacement} {
                    --templates {*also* copy the templates of the project\
                            skeleton over the templates in inputDir}
                    --yes       {assume the answer to all questions to be "yes"\
                            (replace all)}
                }
                deploy-copy {copy the output to the file system path set\
                        in the config file} {}
                deploy-custom {run the custom deployment commands specified in\
                        the config file on the output} {}
                deploy-ftp  {upload the output to the FTP server set in the\
                        config file} {}
                open {open the index page in the default web browser} {}
                version {print the version number and exit} {}
                help {show this message}
            }]

            set commandHelpText {}
            foreach {command description options} $commandHelp {
                append commandHelpText \
                        [::tclssg::utils::text-columns \
                                "" 4 \
                                $command 15 \
                                $description 43]
                foreach {option optionDescr} $options {
                    append commandHelpText \
                            [::tclssg::utils::text-columns \
                                    "" 8 \
                                    $option 12 \
                                    $optionDescr 42]
                }
            }

            puts [format [
                    ::tclssg::utils::trim-indentation {
                        usage: %s <command> [options] [inputDir [outputDir]]

                        Possible commands are:
                        %s

                        inputDir defaults to "%s"
                        outputDir defaults to "%s"
                    }
                ] \
                $argv0 \
                $commandHelpText \
                $::tclssg::config(defaultInputDir) \
                $::tclssg::config(defaultOutputDir)]
        }

        proc unknown args {
            return ::tclssg::command::help
        }
    } ;# namespace command

    # Read the setting $settingName from website config in $inputDir
    proc read-path-setting {inputDir settingName} {
        set value [
            ::tclssg::utils::dict-default-get {} [
                ::tclssg::load-config $inputDir 0
            ] $settingName
        ]
        # Make relative path from config relative to inputDir.
        if {$value ne "" &&
                [::tclssg::utils::path-is-relative? $value]} {
            set value [
                ::fileutil::lexnormalize [
                    file join $inputDir $value
                ]
            ]
        }
        return $value
    }

    # This proc is run if Tclssg is the main script.
    proc main {argv0 argv} {
        # Note: Deal with symbolic links pointing to the actual
        # location of the application to ensure that we look for the
        # supporting code in the actual location, instead from where
        # the link is.
        #
        # Note further the trick with ___; it ensures that the
        # resolution of symlinks also applies to the nominally last
        # segment of the path, i.e. the application name itself. This
        # trick then requires the second 'file dirname' to strip off
        # the ___ again after resolution.

        tclssg configure \
                [file dirname [file dirname [file normalize $argv0/___]]]

        # Version.
        catch {
            set currentPath [pwd]
            cd $::tclssg::config(scriptLocation)
            append ::tclssg::config(version) \
                    " (commit [string range [exec git rev-parse HEAD] 0 9])"
            cd $currentPath
        }

        # Get command line options, including directories to operate on.
        set command [::tclssg::utils::unqueue! argv]

        set options {}
        while {[lindex $argv 0] ne "--" &&
                [string match -* [lindex $argv 0]]} {
            lappend options [string trimleft [::tclssg::utils::unqueue! argv] -]
        }
        set inputDir [::tclssg::utils::unqueue! argv]
        set outputDir [::tclssg::utils::unqueue! argv]
        set debugDir {}

        # Defaults for inputDir and outputDir.
        if {($inputDir eq "") && ($outputDir eq "")} {
            set inputDir $::tclssg::config(defaultInputDir)
            catch {
                set outputDir [read-path-setting $inputDir outputDir]
            }
            if {$outputDir eq ""} {
                set outputDir $::tclssg::config(defaultOutputDir)
            }
        } elseif {$outputDir eq ""} {
            catch {
                set outputDir [read-path-setting $inputDir outputDir]
            }
            if {$outputDir eq ""} {
                puts [
                    ::tclssg::utils::trim-indentation {
                        error: no outputDir given.

                        please either a) specify both inputDir and outputDir or
                                      b) set outputDir in your configuration
                                         file.
                    }
                ]
                exit 1
            }
        }
        if {$debugDir eq ""} {
            catch {
                set debugDir [read-path-setting $inputDir debugDir]
            }
            if {$debugDir eq ""} {
                set debugDir $::tclssg::config(defaultDebugDir)
            }
        }

        # Execute command.
        if {[catch {
                tclssg command $command $inputDir $outputDir $debugDir $options
            } errorMessage]} {
            puts "\n*** error: $errorMessage ***"
            if {$::tclssg::debugMode} {
                global errorInfo
                puts "\nTraceback:\n$errorInfo"
            }
            exit 1
        }
    }
} ;# namespace tclssg

# Check if we were run as the primary script by the interpreter. Code from
# http://wiki.tcl.tk/40097.
proc main-script? {} {
    global argv0

    if {[info exists argv0] &&
            [file exists [info script]] &&
            [file exists $argv0]} {
        file stat $argv0 argv0Info
        file stat [info script] scriptInfo
        expr {$argv0Info(dev) == $scriptInfo(dev)
           && $argv0Info(ino) == $scriptInfo(ino)}
    } else {
        return 0
    }
}

if {[main-script?]} {
    ::tclssg::main $argv0 $argv
    if {$PROFILE} {
        puts [::profiler::sortFunctions exclusiveRuntime]
    }
}
