;;; blorg.el --- export a blog from an org file

(defconst blorg-version "0.75e" "`blorg' version.")

;; Copyright 2006 Bastien Guerry
;;
;; Author: Bastien Guerry <bzg AT altern DOT org>
;; Version: $Id: blorg.el,v 0.67 2008/01/29 14:08:13 guerry Exp guerry $
;; Keywords: org-mode blog publishing html feed atom rss
;; X-URL: <http://www.cognition.ens.fr/~guerry/u/blorg.el>
;;
;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

;;; Commentary:

;; blorg creates a blog from an org file.  Just edit your `org-mode'
;; buffer then do M-x `blorg-publish'.  This is bound to C-c ".
;;
;; Here is the list of pages created by `blorg':
;;
;; - index page
;; - atom/rss feed for index page
;; - tags pages
;; - atom/rss feeds for tags pages
;; - months pages
;; - posts pages
;;
;; Each page is rendered with a specific HTML layout.  You can change
;; the layout of all theses pages (and of the post itself) by using
;; templates.  Have a look at M-x customize-group `blorg-templates'.
;; 
;; If a post or a tag-page already exists, `blorg' won't overwrite it.
;; To force publishing of all the pages, add a prefix: C-u M-x
;; `blorg-publish'.
;; 
;; `blorg' will only publish posts marked with the "DONE" todo
;; keyword.  You can use another string either by explicitely adding
;; the #+DONE_STRING: option at the beginning of the file or by
;; changing the last keyword in `org-todo-keywords'.  This TODO
;; keywords are also set by #+SEQ_TODO: in the buffer.
;;
;; If the heading of an entry is followed by a CLOSED keyword,
;; `blorg' will use this date as the publication date.
;;
;; If the heading if followed by tags, `blorg' will publish a tag
;; page for each one of them.
;; 
;; You can set up a few options, either by customizing the variable
;; `blorg-default-options' (for all your Org) files or by adding
;; options at the beginning of the file:
;;
;; Main informations:
;; #+TITLE       : the title of your blog
;; #+SUBTITLE    : the subtitle of your blog
;; #+AUTHOR      : the author of the blog
;; #+EMAIL       : the author's e-mail address
;; #+LANGUAGE    : language of the blog
;;
;; Publishing options:
;; #+BLOG_URL    : the full url of the blog
;; #+PUBLISH_DIR : absolute directory name (where to publish files)
;; #+UPLOAD_DIR  : relative upload directory name
;; #+IMAGES_DIR  : relative images directory name
;; #+CONFIG_FILE : elisp config file for this blog
;;
;; Other informations::
;; #+CREATED     : <%Y-%m-%d>
;; #+KEYWORDS    : global keywords for this blog
;; #+HOMEPAGE    : the author's homepage (not her blog)OB
;; #+ENCODING    : encoding of the blog
;; #+HTML_CSS    : stylesheet URL for html pages
;; #+XML_CSS     : stylesheet URL for xml feeds
;; #+FEED_TYPE   : atom or rss (which is rss 2.0 by default)
;; #+DONE_STRING : (maybe special) DONE string
;; 
;; See M-x `customize-group' RET `blorg' for further details.
;;

;; Warning: you should better run `blorg' with the latest
;; `org-mode' - at least org-mode v4.53.  You can get org-mode from
;; here : <http://staff.science.uva.nl/~dominik/Tools/org/>

;; Put this file into your load-path and the following into your
;; ~/.emacs: (require 'blorg)

;;; Todo:

;; See <http://www.cognition.ens.fr/~guerry/blorg.html>

;;; Notes:

;;; History:
;;
;; First released <2006-06-09 lun>
;; Started <2006-05-01 lun>

;;; Code:


;;; Requirements
(provide 'blorg)

(require 'org)
(require 'calendar)
(require 'time-stamp)
(require 'eshell)
;; (require 'esh-maint)
(require 'em-unix)

;; Not necessary since emacs 22
(when (< (string-to-number (substring emacs-version 0 2)) 22)
  (require 'regexp-opt))

;; XEmacs prior to 21.5 is not dumped with replace-regexp-in-string.  In
;; those cases it can be found in the xemacs-base package.
(eval-and-compile
  (unless (and (fboundp 'replace-regexp-in-string)
	       (not (featurep 'xemacs)))
    (require 'easy-mmode))
  (require 'cl))

;;; Make the compiler quiet 
;;; Don't mess around with namespaces

(defvar blorgv-time-stamp-formats nil)
(defvar blorgv-publish-index-only nil)
(defvar blorgv-tagstotal nil)
(defvar blorgv-tagsaverage nil)
(defvar blorgv-encoding nil)
(defvar blorgv-header nil)
(defvar blorgv-feed-type nil)
(defvar blorgv-feed-file-name nil)
(defvar blorgv-blog-title nil)
(defvar blorgv-post-title nil)
(defvar blorgv-post-rel-url nil)
(defvar blorgv-xml-css nil)
(defvar blorgv-updated "")
(defvar blorgv-published nil)
(defvar blorgv-content nil)
(defvar blorgv-subtitle "")
(defvar blorgv-blog-url "")
(defvar blorgv-done-string "")
(defvar blorgv-keywords "")
(defvar blorgv-language "")
(defvar blorgv-author "")
(defvar blorgv-homepage "")
(defvar blorgv-email "")
(defvar blorgv-ins-full nil)
(defvar blorgv-tags-links nil)
(defvar blorgv-template-d nil)
(defvar blorgv-publish-d "~/public_html/")
(defvar blorgv-images-d "upload/")
(defvar blorgv-upload-d "images/")

;;; Set aliases, keys, constants, advicest
(define-key org-mode-map "\C-c\"" 'blorg-publish)

(defconst blorg-generator-url
  "http://www.cognition.ens.fr/~guerry/u/blorg.el"
  "`blorg' permanent URL.")

(defconst blorg-generated-by-string
  (concat "Done with blorg " blorg-version
	  " -- org-mode " org-version
	  " and GNU Emacs " emacs-version))

;; see org-infile-export-plist ?
(defconst blorg-options-regexps-alist
  '((:blog-title "^#\\+TITLE:[ \t]+\\(.+\\)$")
    (:subtitle "^#\\+SUBTITLE:[ \t]+\\(.+\\)$")
    (:author "^#\\+AUTHOR:[ \t]+\\(.+\\)$")
    (:email "^#\\+EMAIL:[ \t]+\\(.+\\)$")
    (:modified "^#\\+Time-stamp:[ \t]+<\\([^>]+\\)>$")
    (:blog-url "^#\\+BLOG_URL:[ \t]+\\(.+\\)$")
    (:homepage "^#\\+HOMEPAGE:[ \t]+\\(.+\\)$")
    (:language "^#\\+LANGUAGE:[ \t]+\\(.+\\)$")
    (:encoding "^#\\+ENCODING:[ \t]+\\(.+\\)$")
    (:keywords "^#\\+KEYWORDS:[ \t]+\\(.+\\)$")
    (:html-css "^#\\+HTML_CSS:[ \t]+\\(.+\\)$")
    (:xml-css "^#\\+XML_CSS:[ \t]+\\(.+\\)$")
    (:feed-type "^#\\+FEED_TYPE:[ \t]+\\(.+\\)$")
;;    (:seq-todo "^#\\+SEQ_TODO:[ \t]+\\(.+\\)$")
    (:done-string "^#\\+DONE_STRING:[ \t]+\\(.+\\)$")
    (:publish-dir "^#\\+PUBLISH_DIR:[ \t]+\\(.+\\)$")
	(:template-dir "^#\\+TEMPLATE_DIR:[ \t]+\\(.+\\)$")
    (:upload-dir "^#\\+UPLOAD_DIR:[ \t]+\\(.+\\)$")
    (:images-dir "^#\\+IMAGES_DIR:[ \t]+\\(.+\\)$")
    (:config-file "^#\\+CONFIG_FILE:[ \t]+\\(.+\\)$"))
    "Alist of options and matching regexps.")

(defun blorg-version nil
  "Display blorg version."
  (interactive)
  (message "blorg version %s" blorg-version))

;; FIXME: Is it the right place for it?
(defadvice Footnote-add-footnote
  (before narrow-to-level)
  "Narrow to current level when adding a footnote in `org-mode'."
  (when (equal mode-name "Org")
    (org-narrow-to-subtree)))

(defadvice Footnote-add-footnote
  (after widen) "Widen after editing a footnote in `org-mode'."
  (when (equal mode-name "Org")
    (widen)))

(ad-activate 'Footnote-add-footnote)

;;; Customize groups

(defgroup blorg nil
  "Export an `org-mode' buffer into a blog."
  :group 'org)

;; Put convert options for medium and small thumbnail
;; (defgroup blorg-images nil
;;   "Handle images for `blorg'."
;;   :group 'blorg)

(defgroup blorg-templates-for-pages nil
  "HTML templates for `blorg'."
  :group 'blorg)

(defgroup blorg-templates-for-posts nil
  "HTML templates for `blorg'."
  :group 'blorg)

;;; Customize variables

;; (defcustom blorg-use-registry nil
;;   "Non-nil means blorg will keep a registry for each blog."
;;   :type 'boolean
;;   :group 'blorg)

(defcustom blorg-config-file ""
  "Customization file for blorg."
  :type 'file
  :group 'blorg)

(defcustom blorg-submit-post-string 
  "Submit this post"
  "A string for the title of social bookmarking links."
  :type '(string)
  :group 'blorg)

(defcustom blorg-strings
  `(:index-page-name "index"
    :page-extension ".html"
    :feed-extension ".xml"
    :meta-robots "index,follow"
    :read-more "Read more"
    :time-format "%A, %B %d %Y @ %R %z"
    :title-separator " - ")
  "A list of default strings."
  :type '(plist)
  :group 'blorg)

(defcustom blorg-default-options
  `(:blog-title "[No_title]"
    :subtitle "[No_subtitle]"
    :author ,user-full-name
    :email ,user-mail-address
    :modified nil
    :blog-url "./"
    :homepage "[No_homepage]"
    :language ,(if (getenv "LANG") (substring (getenv "LANG") 0 2) "en")
    :encoding "UTF-8"
    :keywords ""
    :html-css "index.css"
    :xml-css "http://www.blogger.com/styles/atom.css"
    :feed-type "atom"
;;    :seq-todo ,org-todo-keywords
    :done-string "DONE"
    :number-of-posts "12"
    :publish-dir "~/public_html/"
	:template-dir nil
    :upload-dir "upload/"
    :images-dir "images/")
  "A list of default options.

Changes in this list will apply globally to every `blorg'
call.  These options are overriden by their equivalent in the
header of a file."
  :type '(plist)
  :group 'blorg)

(defcustom blorg-post-number-per-page 
  '((index . 10) (feed . 10) (tag . 10) (month . 10))
  "Set how many posts you want to be displayed on each page."
  :type '(list (cons (const :tag "Index page" :value index)
		     (integer :tag "Number"))
	       (cons (const :tag "Feeds" :value feed)
		     (integer :tag "Number"))
	       (cons (const :tag "Tag page" :value tag)
		     (integer :tag "Number"))
	       (cons (const :tag "Month page" :value month)
		     (integer :tag "Number")))
  :group 'blorg)


(defcustom blorg-publish-page-type '(feed tag month post)
  "Defines the blog structure.  

Allowed symbols are: feed tag month post.  

If `blorg-publish-page-type' is nil or '(feed), the blog consists
in one single index page, without any tag or month page.  In this
case `blorg-publish' will ignore `blorg-put-full-post' and always
put full posts in the index."
  :type '(repeat (symbol :tag "Page: "))
  :group 'blorg)

(defcustom blorg-reverse-posts-order t
  "Non-nil means reverse order of posts publication."
  :type 'boolean
  :group 'blorg)

(defcustom blorg-previous-posts-number 12
  "Number of previous posts to display."
  :type 'number
  :group 'blorg)

(defcustom blorg-publish-feed '(index tag)
  "Publish feed for these pages.  
Allowed symbols are: index tag."
  :type '(repeat (symbol :tag "Feed for: "))
  :group 'blorg)

;; (defcustom blorg-previous-posts-with-picture nil
;;   "Insert small thumbnails within previous posts list."
;;   :type 'boolean
;;   :group 'blorg-images)

(defcustom blorg-parg-in-headlines 1
  "Number of paragraphs in the short version of a post."
  :type 'number
  :group 'blorg)

(defcustom blorg-tags-sort 'alphabetical
  "Sort tags by importance or by alphabetical order."
  :type '(radio (const :tag "Importance" importance)
		(const :tag "Alphabetical" alphabetical))
  :group 'blorg)

(defcustom blorg-rss-content-format 'html
  "The format for rendering the content of RSS feeds."
  :group 'blorg
  :type '(radio (const :tag "Render in HTML" html)
		(const :tag "Leave as text" txt)))

;;; Templates

(defcustom blorg-index-template
  "
<body>
  <div id=\"content\">
	<div id=\"blog-title\">
	  <h1><a href=\"(blorg-insert-index-url)\">(blorg-insert-page-title)</a></h1>
	</div>

	<div id=\"sidemenu\">
	  <div id=\"blog-author\">
		<h3>(blorg-insert-author)</h3>
		<ul>
		  <li><a href=\"(blorg-insert-mailto-email)\">email</a></li>
		</ul>
	  </div>

	  <div id=\"tags\">
		<h3>Tags</h3>
		(blorg-insert-tags-as-cloud)
	  </div>

	  <div>
		<h3>Archive</h3>
		(blorg-insert-archives)
	  </div>
	</div>

	<div id=\"rightmenu\">
	  <h3>Older posts</h3>
	  (blorg-insert-previous-posts)
	</div>

	<div id=\"main\">
	  (blorg-insert-content)
	</div>
  </div>
</body>
"
  "Template of the index page.

Here is the list of defuns that you can insert in this template:

 (blorg-insert-index-url)      : the URL of the index page
 (blorg-insert-homepage)       : the URL of the author's homepage
 (blorg-insert-page-title)     : the page title
 (blorg-insert-page-subtitle)  : the page subtitle
 (blorg-insert-mailto-email)   : mailto:your@email.com
 (blorg-insert-email)          : your@email.com
 (blorg-insert-author)         : author's name
 (blorg-insert-previous-posts) : a list of previous posts
 (blorg-insert-tags-as-cloud)  : a cloud of tags
 (blorg-insert-tags-as-list)   : a list of tags
 (blorg-insert-archives)       : a list of months
 (blorg-insert-content)        : the main content"
  :type 'string
  :group 'blorg-templates-for-pages)

(defcustom blorg-tag-page-template
  "
<body>
  <div id=\"content\">
	<div id=\"blog-title\">
	  <h1><a href=\"(blorg-insert-index-url)\">(blorg-insert-page-title)</a></h1>
	</div>

	<div id=\"sidemenu\">
	  <div id=\"blog-author\">
		<h3>(blorg-insert-author)</h3>
		<ul>
		  <li><a href=\"(blorg-insert-mailto-email)\">email</a></li>
		</ul>
	  </div>

	  <div id=\"tags\">
		<h3>Tags</h3>
		(blorg-insert-tags-as-cloud)
	  </div>

	  <div>
		<h3>Archive</h3>
		(blorg-insert-archives)
	  </div>
	</div>

	<div id=\"rightmenu\">
	  <h3>Older posts</h3>
	  (blorg-insert-previous-posts)
	</div>

	<div id=\"main\">
	  (blorg-insert-content)
	</div>
  </div>
</body>
"
  "Template for the tag pages.

Here is the list of defuns that you can insert in this template:

 (blorg-insert-index-url)      : the URL of the index page
 (blorg-insert-homepage)       : the URL of the author's homepage
 (blorg-insert-page-title)     : the page title
 (blorg-insert-page-subtitle)  : the page subtitle
 (blorg-insert-mailto-email)   : mailto:your@email.com
 (blorg-insert-email)          : your@email.com
 (blorg-insert-author)         : author's name
 (blorg-insert-previous-posts) : a list of previous posts
 (blorg-insert-tags-as-cloud)  : a list of tags
 (blorg-insert-tags-as-list)   : a list of tags
 (blorg-insert-archives)       : a list of months
 (blorg-insert-content)        : the main content"
  :type 'string
  :group 'blorg-templates-for-pages)

(defcustom blorg-month-page-template
  "
<body>
  <div id=\"content\">
	<div id=\"blog-title\">
	  <h1><a href=\"(blorg-insert-index-url)\">(blorg-insert-page-title)</a></h1>
	</div>

	<div id=\"sidemenu\">
	  <div id=\"blog-author\">
		<h3>(blorg-insert-author)</h3>
		<ul>
		  <li><a href=\"(blorg-insert-mailto-email)\">email</a></li>
		</ul>
	  </div>

	  <div id=\"tags\">
		<h3>Tags</h3>
		(blorg-insert-tags-as-cloud)
	  </div>

	  <div>
		<h3>Archive</h3>
		(blorg-insert-archives)
	  </div>
	</div>

	<div id=\"rightmenu\">
	  <h3>Older posts</h3>
	  (blorg-insert-previous-posts)
	</div>

	<div id=\"main\">
	  (blorg-insert-content)
	</div>
  </div>
</body>
"
  "Template for the month pages.

Here is the list of defuns that you can insert in this template:

 (blorg-insert-index-url)      : the URL of the index page
 (blorg-insert-homepage)       : the URL of the author's homepage
 (blorg-insert-page-title)     : the page title
 (blorg-insert-page-subtitle)  : the page subtitle
 (blorg-insert-mailto-email)   : mailto:your@email.com
 (blorg-insert-email)          : your@email.com
 (blorg-insert-author)         : author's name
 (blorg-insert-previous-posts) : a list of previous posts
 (blorg-insert-tags-as-cloud)  : a cloud of tags
 (blorg-insert-tags-as-list)   : a list of tags
 (blorg-insert-archives)       : a list of months
 (blorg-insert-content)        : the main content"
  :type 'string
  :group 'blorg-templates-for-pages)

(defcustom blorg-post-page-template
  "
<body>
  <div id=\"content\">

	<div id=\"blog-title\">
	  <h1><a href=\"(blorg-insert-index-url)\">(blorg-insert-page-title)</a></h1>
	</div>

	(blorg-insert-content)
  </div>
</body>
"
  "Template for the post pages.

Here is the list of defuns that you can insert in this template:

 (blorg-insert-index-url)      : the URL of the index page
 (blorg-insert-homepage)       : the URL of the author's homepage
 (blorg-insert-page-title)     : the page title
 (blorg-insert-page-subtitle)  : the page subtitle
 (blorg-insert-mailto-email)   : mailto:your@email.com
 (blorg-insert-email)          : your@email.com
 (blorg-insert-author)         : author's name
 (blorg-insert-previous-posts) : a list of previous posts
 (blorg-insert-tags-as-cloud)  : a cloud of tags
 (blorg-insert-tags-as-list)   : a list of tags
 (blorg-insert-archives)       : a list of months
 (blorg-insert-content)        : the main content"
  :type 'string
  :group 'blorg-templates-for-pages)

(defcustom blorg-post-template
  "
<div class=\"post\">

  <div class=\"post-title\">
	<h2><a href=\"(blorg-insert-post-url)\">(blorg-insert-post-title)</a></h2>
  </div>

  <div class=\"post-infos\">
	(blorg-insert-post-author)
	(blorg-insert-post-dates);
	(blorg-insert-post-tags)
  </div>

  <div class=\"post-content\">
	(blorg-insert-post-content)
  </div>

</div>
"
  "Template for each post.

Here is the list of defuns that you can insert in this template:

 (blorg-insert-post-url)      : the URL of the post
 (blorg-insert-post-title)    : the title of the post
 (blorg-insert-post-author)   : the author of the post
 (blorg-insert-post-dates)    : the publication and modification dates
 (blorg-insert-post-tags)     : the tags for this post
 (blorg-insert-post-echos)    : the \"Submit this post\" links
 (blorg-insert-post-content)  : the main content of the post"
  :type 'string
  :group 'blorg-templates-for-posts)

(defcustom blorg-post-author-template
  "
<p class=\"author\">By <a href=\"(blorg-insert-mailto-email)\">(blorg-insert-author)</a></p>
"
   "Template for the (blorg-insert-post-author) defun."
   :type 'string
   :group 'blorg-templates-for-posts)

(defcustom blorg-post-dates-template
  "
<span class=\"date\">(blorg-insert-post-publication-date)</span>
"
  "Template for the (blorg-insert-post-dates) defun."
  :type 'string
  :group 'blorg-templates-for-posts)

(defcustom blorg-post-tags-template
  "
<span class=\"tags\">Tags: (blorg-insert-this-post-tags)</span>
"
  "Template for the (blorg-insert-post-tags) defun."
  :type 'string
  :group 'blorg-templates-for-posts)


(defcustom blorg-put-full-post
  '(post)
  "Pages in which posts will appear as full posts.
Posts in other pages are summarized.

This list can include the following symbols:

- index
- feed
- post
- tag
- month"
  :type '(repeat (symbol :tag "Page: "))
  :group 'blorg-templates-for-posts)


(defcustom blorg-put-author-in-post
  '(index post tag month)
  "Put author's name in posts when publishing these pages.
See `blorg-put-full-post' for the list of available pages."
  :type '(repeat (symbol :tag "Page: "))
  :group 'blorg-templates-for-posts)


(defcustom blorg-put-echos-in-post
  '(post tag month)
  "Put \"echos\" in posts when publishing these pages.
See `blorg-put-full-post' for the list of available pages."
  :type '(repeat (symbol :tag "Page: "))
  :group 'blorg-templates-for-posts)


(defcustom blorg-put-dates-in-post
  '(index post tag month)
  "Put dates in posts when publishing these pages.
See `blorg-put-full-post' for the list of available pages."
  :type '(repeat (symbol :tag "Page: "))
  :group 'blorg-templates-for-posts)


(defcustom blorg-put-tags-in-post
  '(index post tag month)
  "Put tags in posts when publishing these pages.
See `blorg-put-full-post' for the list of available pages."
  :type '(repeat (symbol :tag "Page: "))
  :group 'blorg-templates-for-posts)

;;; make this an alist var with ("foramt string" post-url post-title)
(defcustom blorg-echos-alist
  '(("<a href=\"http://del.icio.us/post?url=%s&title=%s&tags=%s\" title=\"Submit this post to del.icio.us\"/><img alt=\"Submit this post to del.icio.us\" src=\"http://www.cognition.ens.fr/~guerry/blorg/imgs/delicious.png\"></a>" post-abs-url blorgv-post-title post-tags blorg-submit-post-string blorg-submit-post-string)
    ("<a href=\"http://digg.com/submit?phase=2&url=%s&title=%s\" title=\"Submit this post to digg\"/><img alt=\"Submit this post to digg\" src=\"http://www.cognition.ens.fr/~guerry/blorg/imgs/diggman.png\"></a>" post-abs-url blorgv-post-title blorg-submit-post-string blorg-submit-post-string)
    ("<a href=\"http://www.spurl.net/spurl.php?url=%s&title=%s&tags=%s\" title=\"Submit this post to Spurl\"/><img alt=\"Submit this post to spurl\" src=\"http://www.cognition.ens.fr/~guerry/blorg/imgs/spurl.png\"></a>" post-abs-url blorgv-post-title post-tags blorg-submit-post-string blorg-submit-post-string)
    ("<a href=\"http://www.simpy.com/simpy/LinkAdd.do?href=%s&title=%s&tags=%s\" title=\"Submit this post to Simpy\"/><img alt=\"Submit this post to simpy\" src=\"http://www.cognition.ens.fr/~guerry/blorg/imgs/simpy.png\"></a>" post-abs-url blorgv-post-title post-tags blorg-submit-post-string blorg-submit-post-string)
    ("<a href=\"http://www.newsvine.com/_tools/seed&save?u=%s&h=%s&t=%s\" title=\"Submit this post to newswine\"/><img alt=\"Submit this post to newswine\" src=\"http://www.cognition.ens.fr/~guerry/blorg/imgs/newsvine.png\"></a>" post-abs-url blorgv-post-title post-tags blorg-submit-post-string blorg-submit-post-string)
    ("<a href=\"http://www.blinklist.com/index.php?Action=Blink/addblink.php&Url=%s&Title=%s&Tag=%s\" title=\"Submit this post to Blinklist\"/><img alt=\"Submit this post to blinklist\" src=\"http://www.cognition.ens.fr/~guerry/blorg/imgs/blinklist.png\"></a>" post-abs-url blorgv-post-title post-tags blorg-submit-post-string blorg-submit-post-string)
    ("<a href=\"http://www.furl.net/storeIt.jsp?u=%s&t=%s\" title=\"Submit this post to Furl\"/><img alt=\"Submit this post to furl\" src=\"http://www.cognition.ens.fr/~guerry/blorg/imgs/furl.png\"></a>" post-abs-url blorgv-post-title post-tags blorg-submit-post-string blorg-submit-post-string)
    ("<a href=\"http://reddit.com/submit?url=%s&title=%s\" title=\"Submit this post to reddit\"/><img alt=\"Submit this post to Reddig\" src=\"http://www.cognition.ens.fr/~guerry/blorg/imgs/reddit.png\"></a>" post-abs-url blorgv-post-title blorg-submit-post-string blorg-submit-post-string)
    ("<a href=\"http://myweb2.search.yahoo.com/myresults/bookmarklet?u=%s&t=%s&tag=%s\" title=\"Submit this post to Yahoo MyWeb\"/><img alt=\"Submit this post to Yahoo\" src=\"http://www.cognition.ens.fr/~guerry/blorg/imgs/yahoo.png\"></a>" post-abs-url blorgv-post-title post-tags blorg-submit-post-string blorg-submit-post-string)
    ("<a href=\"http://www.facebook.com/sharer.php?u=%s&t=%s\" title=\"Submit this post to facebook\"><img alt=\"Submit this post to facebook\" src=\"http://www.cognition.ens.fr/~guerry/blorg/imgs/facebook.png\"></a>" post-abs-url post-tags blorg-submit-post-string blorg-submit-post-string)
    ("<a href=\"http://www.connotea.org/add?uri=%s&usertitle=%s&tags=%s\" title=\"Submit this post to connotea\"/><img alt=\"Submit this post to connotea\" src=\"http://www.cognition.ens.fr/~guerry/blorg/imgs/connotea.png\"></a>" post-abs-url blorgv-post-title post-tags blorg-submit-post-string blorg-submit-post-string))
  "A alist of links to publish as \"echos\" of the post.
Each cell in this list is a list of the form:

 \"[Formatting string] strings...\""
  :type '(alist :key-type (string) 
		:value-type (repeat symbol))
  :group 'blorg-templates-for-posts)

(defcustom blorg-before-publish-hook nil
  "Psuedo-mode load hook for blorg, run before the blog is published."
  :group 'blorg
  :type 'hook)

(defcustom blorg-after-publish-hook nil
  "Psuedo-mode cleanup hook for blorg, run after the blog is published."
  :group 'blorg
  :type 'hook)

;;; Main code
(defun blorg-set-header-vars nil
  "Set each var from the header."
  (setq blorgv-header (blorg-parse-header))
  (setq blorgv-publish-index-only 
	(not (and (memq 'tag blorg-publish-page-type)
		  (memq 'month blorg-publish-page-type)
		  (memq 'post blorg-publish-page-type)))
	blorgv-blog-url (plist-get blorgv-header :blog-url)
        blorgv-author (plist-get blorgv-header :author)
        blorgv-email (plist-get blorgv-header :email)
        blorgv-blog-title (plist-get blorgv-header :blog-title)
	blorgv-subtitle (plist-get blorgv-header :subtitle)
	blorgv-encoding (plist-get blorgv-header :encoding)
	blorgv-language (plist-get blorgv-header :language)
	blorgv-homepage (plist-get blorgv-header :homepage)
	blorgv-xml-css (plist-get blorgv-header :xml-css)
	blorgv-done-string (or (plist-get blorgv-header :done-string) "DONE") 
;;	(car (reverse (split-string (plist-get blorgv-header :seq-todo)))))
	blorgv-template-d (plist-get blorgv-header :template-dir)
	blorgv-publish-d (plist-get blorgv-header :publish-dir)
	blorgv-upload-d (plist-get blorgv-header :upload-dir)
	blorgv-images-d (plist-get blorgv-header :images-dir)
	blorgv-keywords (plist-get blorgv-header :keywords)
	blorgv-feed-type (plist-get blorgv-header :feed-type)))

(defun blorg-set-time-formats nil
  "Set time formats."
  (if org-display-custom-times
      (setq blorgv-time-stamp-formats org-time-stamp-custom-formats)
    (setq blorgv-time-stamp-formats org-time-stamp-formats)))

(defun blorg-load-templates-dir (blorgv-template-d)
  (when blorgv-template-d
	;; read each of these templates
	(dolist (templ-name '(index
						  post-page
						  post
						  post-author
						  post-dates
						  post-tags))
	  (let ((templ-file (concat blorgv-template-d (format "%s.html" templ-name)))
			(templ-var  (format "blorg-%s-template" templ-name)))
		;; if the file exists, read it into buffer and put in variable
		(when (file-readable-p templ-file)
		  (with-temp-buffer
			(insert-file-contents templ-file nil nil nil t)
			(set (intern templ-var) (buffer-string))
			(message "Loaded %s from \"%s\"" templ-var templ-file)))))
	;; reuse the index page for tag page, monthly page and post-page
	(setq blorg-tag-page-template blorg-index-template)
	(setq blorg-month-page-template blorg-index-template)))

;;;###autoload
(defun blorg-publish ()
  "Publish an `org-mode' file as a blog."
  (interactive)
  (unless (eq major-mode 'org-mode) 
    (error "Not in an org buffer"))
  (blorg-set-time-formats)
  (blorg-set-header-vars)
  (run-hooks 'blorg-before-publish-hook)
  (let* ((blorgv-content (blorg-parse-content 
			 blorgv-done-string 
			 blorg-reverse-posts-order))
	 (tags (blorg-parse-tags))
	 (blorgv-tagstotal (blorg-count-tags-total tags))
	 (blorgv-tagsaverage (if tags (/ blorgv-tagstotal (length tags)) 1))
	 (blorgv-created-row (blorg-infer-date-of-creation blorgv-content))
	 (blorgv-modified-row (or (plist-get blorgv-header :created) (current-time)))
	 (months-list 
	  (blorg-make-arch-month-list blorgv-created-row blorgv-content)))
    (when (not blorgv-content)
      (error "No headline suitable for publication"))
	;; Load templates if directory specified
	(blorg-load-templates-dir blorgv-template-d)
    ;;; Load config file
    (unless (or (equal blorg-config-file "")
		(not (file-exists-p blorg-config-file)))
      (load-file blorg-config-file)
      (message "Blorg config file loaded"))
    (when (plist-get blorgv-header :config-file)
      (load-file (plist-get blorgv-header :config-file))
      (message "Blorg local config file loaded"))
    ;;; Create directories
    (blorg-maybe-create-directories
     blorgv-publish-d blorgv-images-d blorgv-upload-d)
	;; Copy stylesheets from template to publish directory
	(when blorgv-template-d
	  (dolist (which-ml '(:html-css :xml-css))
		(let ((css-name (plist-get blorgv-header which-ml)))
		  (when css-name
			(let ((src-f (concat blorgv-template-d css-name))
				  (dst-f (concat blorgv-publish-d css-name)))
			  (blorg-cp-if-newer src-f dst-f))))))
    ;; Maybe clean orphan files
;;    (blorg-maybe-clean-orphan-files blorgv-content)
    (save-window-excursion
      (save-excursion
		(let ((backup-inhibited t)
			  (auto-save-default nil))
	;; always publish index
	(blorg-render-index tags blorgv-content)
	(when (memq 'index blorg-publish-feed)
	  (blorg-render-feed blorgv-content))
	(when (memq 'tag blorg-publish-page-type)
	  (blorg-render-tags-pages
	   tags blorgv-content months-list))
	(when (memq 'month blorg-publish-page-type)
	  (blorg-render-month-pages
	   tags blorgv-content months-list))
	(when (memq 'month blorg-publish-page-type)
	  (blorg-render-posts-html 
	   tags blorgv-content))))))
  (run-hooks 'blorg-after-publish-hook)
  (when (get-buffer "*blorg feed output*")
    (kill-buffer "*blorg feed output*")))

;;; TO BE TESTED
;; (defun blorg-maybe-clean-orphan-files (blorgv-content)
;;   "Delete all html and xml files but those which won't be republished."
;;   (let ((existing-files 
;; 	 (directory-files blorgv-publish-d nil "\..+ml"))
;; 	(posts-files (mapcar 
;; 		      (lambda (post)
;; 			(blorg-make-post-url 
;; 			 (plist-get post :post-title)))
;; 		      blorgv-content)))
;;     (dolist (file (cddr existing-files))
;;       (when (not (member file posts-files))
;; 	(delete-file (concat blorgv-publish-d file))))))

(defun nil-< (a b)
  "less-than function whose arguments can be nil (lesser than anything)."
  (when b
    (if a (< a b) t)))

(defun tuple-< (a b)
  "Compare two tuples to see if A is strictly less than B."
  (if (equal (car a) (car b))
	  (unless (and (null (cdr a)) (null (cdr b)))
		(tuple-< (cdr a) (cdr b)))
	(nil-< (car a) (car b))))

(defun blorg-date-of-first-post (blorgv-content)
  "Earliest close date amongst all posts."
  (let (all-closed-dates)
	(dolist (post blorgv-content)
	  (let ((this-closed-date (plist-get post :post-closed)))
		(if this-closed-date
			(add-to-list 'all-closed-dates this-closed-date))))
	(setq all-closed-dates (sort all-closed-dates 'tuple-<))
	(car all-closed-dates)))

(defun blorg-infer-date-of-creation (blorgv-content)
  "Date of first post, or today if no posts have been marked as CLOSED."
  (let ((date-of-first-post (blorg-date-of-first-post blorgv-content)))
	(cond
	 (date-of-first-post)
	 ((current-time)))))

(defun blorg-parse-new-tags (blorgv-content)
   "Parse BLORGV-CONTENT and look for new tags."
   (let (tags-list)
     (dolist (post blorgv-content)
       (mapcar (lambda (tag) (add-to-list 'tags-list tag))
	       (delete "" (split-string (plist-get post :post-tags) ":"))))
     (mapcar (lambda (tag) (cons tag 1)) tags-list)))


(defun blorg-maybe-create-directories
  (pub-d img-d upl-d)
  "Maybe create PUB-D IMG-D and UPL-D directories."
    (unless (file-exists-p pub-d)
      (when (yes-or-no-p (format "Create this new directory : %s ? "
			      pub-d))
	(eshell/mkdir pub-d)
	(message "%s directory created" pub-d)))
    (unless (file-exists-p (concat pub-d img-d))
      (when (yes-or-no-p (format "Create this new directory : %s ? "
			    (concat pub-d img-d)))
	(eshell/mkdir (concat pub-d img-d))
	(message "%s%s directory created" pub-d img-d)))
    (unless (file-exists-p (concat pub-d upl-d))
      (when (yes-or-no-p (format "Create this new directory : %s ? "
			      (concat pub-d upl-d)))
	(eshell/mkdir (concat pub-d upl-d))
	(message "%s%s directory created" pub-d upl-d))))

;;; Parsing
(defun blorg-set-header-region nil
  "Return a cons defining the region of the blorgv-header."
  (save-excursion
    (goto-char (point-min))
    (let (start end)
      (while (re-search-forward "^#\\+.+$" nil t)
	(if (match-string 0)
	    (setq end (match-end 0))
	  (setq end (point-max))))
      (cons (point-min) end))))



(defun blorg-parse-tags ()
  "Make a sorted list of all tags from buffer.
Each element of the list is a cons: (\"tag-name\" . number)."
  (let (alltags)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward ":\\([0-9A-Za-z@_]+\\):" nil t)
		  (when (blorg-check-done)
	(unless (assoc (match-string-no-properties 1) alltags)
	  (let ((cnt 0))
	    (save-excursion
	      (goto-char (point-min))
	      (while (re-search-forward
			   (concat ":\\("
				   (regexp-quote
				    (match-string-no-properties 1))
				   "\\):") nil t)
			  (when (blorg-check-done)
		(setq cnt (1+ cnt)))))
	    (setq alltags
		  (add-to-list
		   'alltags
		   (cons (match-string-no-properties 1)
			 cnt))))))
	(backward-char 1)))
    (blorg-sort-tags alltags blorg-tags-sort)))


(defun blorg-parse-header nil
  "Create a plist containing blorgv-header options."
  (let* ((region (blorg-set-header-region))
	 (start (car region))
	 (end (cdr region))
	 (blorgv-header nil))
	(apply 'append
		   (mapcar (lambda (opt) (list (car opt)
									   (blorg-get-option start end opt)))
				   blorg-options-regexps-alist))))


(defun blorg-count-tags-total (taglist)
  "Count total number of tags in taglist."
  (let ((total 0))
    (dolist (tag taglist)
      (setq total (+ total (cdr tag)))) total))


(defun blorg-get-option (start end option)
  "Look from START to END for OPTION and return it."
  (save-excursion
    (goto-char start)
    (cond ((and (re-search-forward (cadr option) end t)
		(match-string-no-properties 1))
	    (if (or ; Add blorgv-homepage ?
		 (eq (car option) :blog-url)
		 (eq (car option) :template-dir)
		 (eq (car option) :publish-dir)
		 (eq (car option) :images-dir)
		 (eq (car option) :upload-dir))
		(file-name-as-directory
		 (blorg-strip-trailing-spaces
		  (match-string-no-properties 1)))
	      (blorg-strip-trailing-spaces
	       (match-string-no-properties 1))))
	  (t (plist-get blorg-default-options
			(car option))))))


(defun blorg-parse-content
  (blorgv-done-string reverse)
  "Parse blorgv-content of an `org-mode' buffer.
Check the presence of BLORGV-DONE-STRING in each post.
REVERSE posts order is necessary."
  (let (posts (cnt 0))
    (save-excursion
      (goto-char (point-min))
      ;; match DONE and [#A] DONE as well
      (while (re-search-forward
	      (concat "^\\* " blorgv-done-string
		      " \\([^:\r\n]+\\)[ \t]*\\(:[A-Za-z@_0-9:]+\\)?[ \t]*$")
	      nil t)
	(let* ((ttle (match-string-no-properties 1))
	       (tgs (or (match-string-no-properties 2) ""))
	       (dte (blorg-encode-time
		     (or (progn
			   (save-excursion
			     (re-search-forward
			      org-ts-regexp-both 
			      (save-excursion
				(re-search-forward "^\\* " nil t)) t))
			   (match-string-no-properties 1))
			 (format-time-string (cdr blorgv-time-stamp-formats)))
			 t))
	       (post-exists 
		(file-exists-p (concat blorgv-publish-d 
				       (blorg-make-post-url ttle)))))
	  (add-to-list 'posts
		       (blorg-parse-post
			cnt ttle tgs dte
			(if (save-excursion
			      (re-search-forward "^\\* " nil t))
			    (match-beginning 0)
			  (point-max))
			post-exists) t)
	  (setq cnt (1+ cnt)))))
    (if reverse (reverse posts) posts)))


(defun blorg-parse-post (number title tags dte end exists)
  "Parse post NUMBER with TITLE and TAGS from DATE ending at END."
  `(:post-number ,number
    :post-title ,(blorg-strip-trailing-spaces title)
    :post-tags ,tags
    :post-exists ,exists
    :post-closed ,dte
    :post-updated ,(current-time)
    :post-content ,(blorg-get-post-content end)))


(defun blorg-get-post-content (end)
  "Get the blorgv-content of the post before END."
  (save-excursion
    (beginning-of-line)
    (while (or (looking-at (concat "[ \t]*" org-closed-string " "))
	       (looking-at (concat "[ \t]*" org-scheduled-string " "))
	       (looking-at "\\* "))
      (forward-line 1))
    (buffer-substring (point) end)))


(defun blorg-check-done ()
  "Check if the line begins with the DONE string.
Also match \"* DONE [#A] ...\" and the likes."
  (save-excursion
    (save-match-data
      (beginning-of-line)
      (looking-at
       (concat 
	"^\\*.+"
	(or (plist-get blorgv-header :done-string) "DONE"))))))
;;	    (car (reverse (split-string (plist-get blorgv-header :seq-todo))))))))))


(defun blorg-limit-content-to-number (lst num &optional rest)
  "Make a sublist of LST with the first NUM elements.
If REST is non-nil, return the lst minus its first NUM elements."
  (if (< num (length lst))
      (if rest (nthcdr num lst)
	(reverse (nthcdr (- (length lst) num) (reverse lst))))
    (if (and rest (length lst)) nil lst)))


(defun blorg-sort-tags (tags order)
  "Return a sorted alist of TAGS depending on ORDER.
ORDER is either alphabetical-based or importance-based."
  (if (eq order 'alphabetical)
      (sort tags (lambda (fst scd)
		   (string< (car fst) (car scd))))
    (sort tags (lambda (fst scd) (> (cdr fst) (cdr scd))))))


;;; Rendering
(defun blorg-render-feed
  (blorgv-content &optional feed-name new-title)
  "Export a feed with BLORGV-HEADER and BLORGV-CONTENT.
FEED-NAME might be either atom.xml/rss.xml or tag.xml.
NEW-TITLE is needed to produce tag.xml depending on the tag itself."
  ;; First make sure everything is visible
  (widen)
  (show-all)
  (let* ((blorgv-feed-file-name
	  (concat blorgv-publish-d 
		  (or feed-name 
		      (concat blorgv-feed-type 
			      (plist-get blorg-strings :feed-extension)))))
 	 (content (blorg-limit-content-to-number 
		   blorgv-content 
		   (cdr (assoc 'feed blorg-post-number-per-page)))))
    (with-temp-buffer
      (switch-to-buffer (get-buffer-create "*blorg feed output*"))
      (erase-buffer)
      (blorg-render-header-feed blorgv-feed-file-name new-title)
      (mapcar (lambda (new-post)
		(blorg-render-content-feed new-post))
	      content)
      (if (equal blorgv-feed-type "rss")
	  (insert "  </channel>\n</rss>")
	(insert "</feed>"))
      (write-file blorgv-feed-file-name)
      (kill-buffer (buffer-name)))))


(defun blorg-render-header-feed
  (blorgv-feed-file-name &optional new-title)
  "Render the BLORGV-HEADER of buffer into atom blorgv-header.
BLORGV-FEED-FILE-NAME is the feed filename.
NEW-TITLE is the new title.  Er."
  (let ((title (or new-title blorgv-blog-title)))
    (switch-to-buffer (get-buffer-create "*blorg feed output*"))
    (erase-buffer)
    (if (equal blorgv-feed-type "atom")
	(blorg-render-header-atom title)
      (blorg-render-header-rss title))))


(defun blorg-render-header-atom (title)
  "Render blorgv-header in atom format for TITLE."
  (insert "<?xml version=\"1.0\" encoding=\"" blorgv-encoding "\"?>
<?xml-stylesheet href=\"" blorgv-xml-css "\" type=\"text/css\"?>
<feed xmlns=\"http://www.w3.org/2005/Atom\">

  <title type=\"text\">" title "</title>
  <subtitle type=\"text\">" blorgv-subtitle  "</subtitle>
  <updated>" (blorg-timestamp-to-rfc3339 blorgv-modified-row) "</updated>
  <id>" blorgv-blog-url "</id>
  <link rel=\"alternate\" type=\"text/html\" hreflang=\""
  blorgv-language "\" href=\"" blorgv-blog-url "\" />
  <link rel=\"self\" type=\"application/atom+xml\" href=\""
  (concat blorgv-blog-url (file-name-nondirectory blorgv-feed-file-name)) "\" />
  <rights>Copyright (c) " (format-time-string "%Y") " " blorgv-author "</rights>
  <generator uri=\"" blorg-generator-url "\" version=\""
  blorg-version "\">
    " blorg-generated-by-string "
  </generator>\n"))


(defun blorg-render-header-rss
  (title)
  "Render header in rss format for TITLE."
  (insert "<?xml version=\"1.0\" blorgv-encoding=\"" blorgv-encoding "\"?>
<rss version=\"2.0\">
  <channel>
    <title>" title "</title>
    <link>" blorgv-blog-url "</link>
    <language>" blorgv-language "</language>
    <description>" blorgv-subtitle "</description>
    <pubDate>" (blorg-timestamp-to-rfc822 blorgv-created-row) "</pubDate>
    <lastBuildDate>" (blorg-timestamp-to-rfc822 blorgv-modified-row) "</lastBuildDate>
    <copyright>(c) " (concat (format-time-string "%Y") " " blorgv-author) "</copyright>
    <docs>" blorgv-blog-url "</docs>
    <generator>blorg version " blorg-version "</generator>\n"))


(defun blorg-render-content-feed (post)
  "Render blorgv-content of feed with BLORGV-HEADER for POST."
  (let* ((blorgv-post-title (plist-get post :post-title))
	 (blorgv-published (if (equal blorgv-feed-type "atom")
			    (blorg-timestamp-to-rfc3339
			     (plist-get post :post-closed))
			  (blorg-timestamp-to-rfc822
			   (plist-get post :post-closed))))
	 (blorgv-updated (if (equal blorgv-feed-type "atom")
			      (blorg-timestamp-to-rfc3339
			       (plist-get post :post-updated))
			  (blorg-timestamp-to-rfc822
			   (plist-get post :post-updated))))
	 (blorgv-content (plist-get post :post-content))
	 (blorgv-post-rel-url (blorg-make-post-url blorgv-post-title))
	 (post-number (plist-get post :post-number)))
    (switch-to-buffer (get-buffer-create "*blorg feed output*"))
    (goto-char (point-max))
    (if (equal blorgv-feed-type "atom")
	(blorg-render-content-atom)
      (blorg-render-content-rss))))


(defun blorg-render-content-rss nil
  "Render content of feed in rss 2.0 format."
  (insert "
    <item>
      <title>" (blorg-escape blorgv-post-title 'entity) "</title>
      <link>" (concat blorgv-blog-url blorgv-post-rel-url) "</link>
      <description>\n" (if (eq blorg-rss-content-format 'html)
			   (blorg-render-post-content-html blorgv-content nil blorgv-post-title)
			 (blorg-render-post-content-txt blorgv-content))
      "      </description>
      <pubDate>" blorgv-published "</pubDate>
      <guid>" (concat blorgv-blog-url blorgv-post-rel-url) "</guid>
    </item>\n"))


(defun blorg-render-content-atom nil
  "Render content of feed in atom format."
    (insert "
<entry>
  <title>" (blorg-escape blorgv-post-title 'entity) "</title>
  <link rel=\"alternate\" type=\"text/html\" href=\""
  (concat blorgv-blog-url blorgv-post-rel-url) "\"/>
  <id>" (concat blorgv-blog-url blorgv-post-rel-url) "</id>
  <updated>" blorgv-updated "</updated>
  <published>" blorgv-published "</published>
  <author>
    <name>" blorgv-author "</name>
    <uri>" blorgv-homepage "</uri>
    <email>" blorgv-email "</email>
  </author>")
    (if (memq 'feed blorg-put-full-post)
	(insert "
  <content type=\"xhtml\" xml:lang=\""
    blorgv-language "\" xml:base=\"" blorgv-blog-url "\">
    <div xmlns=\"http://www.w3.org/1999/xhtml\">\n"
  (blorg-render-post-content-html
   blorgv-content t blorgv-post-title)
  "    </div>
  </content>")
      (insert "
  <summary type=\"xhtml\" xml:lang=\""
    blorgv-language "\" xml:base=\"" blorgv-blog-url "\">
    <div xmlns=\"http://www.w3.org/1999/xhtml\">\n"
  (blorg-render-post-content-html
   blorgv-content nil blorgv-post-title)
  "    </div>
  </summary>"))
    (insert "\n</entry>\n\n"))


(defun blorg-render-index
  (tags blorgv-content)
  "Render `org-mode' buffer.
BLORGV-HEADER TAGS BLORGV-CONTENT and MONTHS-LIST are required."
    (with-temp-buffer
      (switch-to-buffer (get-buffer-create "*blorg output*"))
      (erase-buffer)
      (blorg-render-header-html blorgv-header blorgv-blog-title
       (if (equal blorgv-feed-type "atom")
	   "atom.xml" "rss.xml"))
      (let* ((ctnt (blorg-limit-content-to-number 
		    blorgv-content 
		    (cdr (assoc 'index blorg-post-number-per-page))))
	     (previous-posts (blorg-limit-content-to-number 
			      blorgv-content 
			      (cdr (assoc 'index blorg-post-number-per-page)) t))
	     (ins-tags (memq 'index blorg-put-tags-in-post))
	     (ins-auth (memq 'index blorg-put-author-in-post))
	     (ins-echos (memq 'index blorg-put-echos-in-post))
	     (ins-dates (memq 'index blorg-put-dates-in-post))
	     (blorgv-ins-full 
	      (or blorgv-publish-index-only 
		  (memq 'index blorg-put-full-post))))
	(blorg-insert-body blorg-index-template)
	(insert "\n</html>")
	(write-file (concat blorgv-publish-d
			    (plist-get blorg-strings :index-page-name)
			    (plist-get blorg-strings :page-extension)))
	(kill-buffer (buffer-name)))))


(defun blorg-render-posts-html (tags blorgv-content)
  "Render posts with TAGS and BLORGV-CONTENT."
  (let* ((ins-tags (memq 'post blorg-put-tags-in-post))
	 (ins-auth (memq 'post blorg-put-author-in-post))
	 (ins-echos (memq 'post blorg-put-echos-in-post))
	 (ins-dates (memq 'post blorg-put-dates-in-post))
	 (blorgv-ins-full (memq 'post blorg-put-full-post))
	 (post-keywords blorgv-keywords))
    (dolist (ctnt0 blorgv-content)
      (let* ((ctnt (list ctnt0))
	     (blorgv-post-title (plist-get ctnt0 :post-title))
	     (blorgv-updated (blorg-timestamp-to-readable (plist-get ctnt0 :post-updated)))
	     (blorgv-published (blorg-timestamp-to-readable (plist-get ctnt0 :post-closed)))
	     (post-tags
	      (mapconcat 'eval (delete "" (split-string (plist-get ctnt0 :post-tags) ":")) " "))
	     (post-file-name
	      (concat blorgv-publish-d (blorg-make-post-url blorgv-post-title))))
	(with-temp-buffer
	  (switch-to-buffer (get-buffer-create "*blorg output*"))
	  (erase-buffer)
	  (plist-put blorgv-header :tp-title
		     (concat blorgv-blog-title (plist-get blorg-strings :title-separator)
			     blorgv-post-title))
	  (plist-put blorgv-header :tp-published blorgv-published)
	  (plist-put blorgv-header :tp-updated blorgv-updated)
	  (plist-put blorgv-header :tp-keywords (concat post-keywords " " post-tags))
	  ;; Render blorgv-header
	  (blorg-render-header-html 
	   blorgv-header (plist-get blorgv-header :tp-title))
	 ;; Render body
	  (blorg-insert-body blorg-post-page-template)
	  (insert "\n</html>")
	  (write-file post-file-name)
	  (kill-buffer (buffer-name)))))))


(defun blorg-render-tags-pages
  (tags blorgv-content months-list)
  "Render one page per tag.
BLORGV-HEADER TAGS BLORGV-CONTENT and MONTHS-LIST  are required."
    (dolist (tag tags)
      (let* ((tag-name (car tag))
	     (file-name (concat blorgv-publish-d tag-name 
				(plist-get blorg-strings :page-extension)))
	     (ins-tags (memq 'tag blorg-put-tags-in-post))
	     (ins-auth (memq 'tag blorg-put-author-in-post))
	     (ins-echos (memq 'tag blorg-put-echos-in-post))
	     (ins-dates (memq 'tag blorg-put-dates-in-post))
	     (blorgv-ins-full (memq 'tag blorg-put-full-post))
	     (ctnt-tag (blorg-limit-content-to-tag blorgv-content tag-name))
	     (tag-months-list (delq nil (blorg-check-arch-list 
					 months-list ctnt-tag)))
	     (ctnt (blorg-limit-content-to-number 
		    ctnt-tag 
		    (cdr (assoc 'tag blorg-post-number-per-page))))
	     (previous-posts (blorg-limit-content-to-number 
			      ctnt-tag (cdr (assoc 'tag blorg-post-number-per-page)) t)))
	(with-temp-buffer
	  (switch-to-buffer (get-buffer-create "*blorg output*"))
	  (erase-buffer)
	  (blorg-render-header-html
	   blorgv-header (concat blorgv-blog-title (plist-get blorg-strings 
						:title-separator)
			  tag-name)
	   (concat tag-name (plist-get blorg-strings :feed-extension)) tag)
	  (blorg-insert-body blorg-tag-page-template)
 	  (insert "\n</html>")
	  (write-file file-name)
	  (kill-buffer (buffer-name)))
	(when (memq 'tag blorg-publish-feed)
	  (blorg-render-tag-feed
	   tag-name ctnt
	   (concat tag-name (plist-get blorg-strings :feed-extension)))))))


(defun blorg-render-month-pages (tags blorgv-content months-list)
  "Render one page per month.
BLORGV-HEADER TAGS BLORGV-CONTENT and MONTHS-LIST are required."
    (dolist (month months-list)
      (let* ((month-name (car month))
	     (file-name (concat blorgv-publish-d (cadr month)))
	     (ins-tags (memq 'month blorg-put-tags-in-post))
	     (ins-auth (memq 'month blorg-put-author-in-post))
	     (ins-echos (memq 'month blorg-put-echos-in-post))
	     (ins-dates (memq 'month blorg-put-dates-in-post))
	     (blorgv-ins-full (memq 'month blorg-put-full-post))
	     (ctnt-month (blorg-limit-content-to-month blorgv-content month))
 	     (ctnt (blorg-limit-content-to-number 
		    ctnt-month (cdr (assoc 'month blorg-post-number-per-page))))
 	     (previous-posts (blorg-limit-content-to-number 
			      ctnt-month (cdr (assoc 'month blorg-post-number-per-page)) t)))
	(with-temp-buffer
	  (switch-to-buffer (get-buffer-create "*blorg output*"))
	  (erase-buffer)
	  (blorg-render-header-html
	   blorgv-header (concat blorgv-blog-title 
			  (plist-get blorg-strings :title-separator)
			  month-name))
	  (blorg-insert-body blorg-month-page-template)
 	  (insert "\n</html>")
	  (write-file file-name)
	  (kill-buffer (buffer-name))))))


(defun blorg-render-archives-list-html (months-list)
  "Render MONTHS-LIST into an html list with CLASS."
  (concat "<div id=\"archives\">\n  <ul>\n"
	  (mapconcat (lambda (mth)
		       (concat "    <li><a href=\"" (cadr mth) "\">"
			       (car mth) "</a></li>"))
		     months-list "\n")
	  "\n  </ul>\n</div>\n"))


(defun blorg-render-previous-posts-list (previous-posts)
  "Render a list containing PREVIOUS-POSTS."
  (with-temp-buffer
    (when previous-posts
      (insert "<div id=\"prev-posts\">\n<ul>\n"))
    (mapc (lambda (post)
	    (insert "  <li><a href=\""
		    (blorg-make-post-url
		     (plist-get post :post-title))
		    "\">" (plist-get post :post-title)
		    "</a></li>\n"))
	  (blorg-limit-content-to-number
	   previous-posts
	   blorg-previous-posts-number))
    (when previous-posts (insert "</ul>\n</div>\n"))
    (buffer-string)))


(defun blorg-render-tag-feed
  (tag-name blorgv-content feed-name)
  "Publish feed for tags.
TAG-NAME BLORGV-HEADER BLORGV-CONTENT and FEED-NAME are required."
  (with-temp-buffer
    (switch-to-buffer (get-buffer-create "*blorg feed output*"))
    (erase-buffer)
    (let ((new-con (blorg-sort-content-tag blorgv-content tag-name))
	  (new-tit (concat blorgv-blog-title 
			   (plist-get blorg-strings :title-separator)
			   tag-name)))
      (blorg-render-feed
       new-con feed-name new-tit))))


(defun blorg-render-tags-list-html (tags)
  "Render TAGS in a html list."
  (with-temp-buffer
    (insert "<div id=\"tags-list\">\n  <ul>\n")
    (mapc (lambda (tag)
	    (insert "    <li>[" (number-to-string (cdr tag))
		    "] <a href=\""
		    (concat (car tag) (plist-get blorg-strings 
						 :page-extension)) "\">"
		    (car tag)
		    "</a></li>\n"))
	  tags)
    (insert "  </ul>\n</div>\n\n")
    (buffer-string)))


(defun blorg-calc-tag-size (level)
  "Compute tag display size in percent depending on LEVEL."
  (let ((base 100) 
	(step (/ 100 blorgv-tagstotal)) 
	(average blorgv-tagsaverage)) 
    (number-to-string (+ 100 (* step (- level average))))))


(defun blorg-render-tags-cloud-html (tags)
  "Render TAGS as a cloud in html."
  (with-temp-buffer
    (insert "<div id=\"tags-cloud\">\n")
    (mapc (lambda (tag)
	    (insert "  <a style=\"font-size: " 
		    (blorg-calc-tag-size (cdr tag))
		    "%\" href=\"" (concat (car tag) 
					  (plist-get blorg-strings 
						     :page-extension)) "\">"
		    (car tag) "</a> "))
	  tags)
    (insert "  \n</div>\n\n")
    (buffer-string)))


(defun blorg-render-header-html
  (blorgv-header page-title &optional feed-url tag)
  "Render BLORGV-HEADER.
If PAGE-TITLE give a specific title to this page.
FEED-URL is the complete url for the feed page.
TAG is the set of tags."
  (let ((keywords
	 (concat
	  (cond ((stringp (car tag))
		 (concat (car tag) ", "))
		((and (not (null (car tag)))
		      (listp (car tag)))
		 (concat (mapconcat 'car tag ", ") ", "))
		(t ""))
	  (mapconcat
	   'eval
	   (split-string (or (plist-get blorgv-header :tp-keywords) 
			     blorgv-keywords)) ", ") ))
	(html-css (plist-get blorgv-header :html-css)))
    (insert "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\"
	  \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">
<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\""
blorgv-language "\" lang=\"" blorgv-language"\">
<head>
  <title>" page-title "</title>
  <meta http-equiv=\"Content-Type\" content=\"text/html; charset=" blorgv-encoding "\" />
  <meta name=\"generator\" content=\"blorg\" />
  <meta name=\"description\" content=\"" blorgv-subtitle "\" />
  <meta name=\"keywords\" content=\"" keywords "\" />
  <meta name=\"robots\" content=\"" 
  (plist-get blorg-strings :meta-robots)
  "\" />
  <meta name=\"author\" content=\"" blorgv-author "\" />
  <link href=\"" html-css
  "\" rel=\"stylesheet\" title=\"Default\" type=\"text/css\" media=\"screen\" />")
    (when feed-url (insert "
  <link rel=\"alternate\" type=\"application/" blorgv-feed-type
  "+xml\" title=\"" page-title "\" href=\""
  feed-url "\" />"))
    (insert "\n</head>\n")))


(defun blorg-render-content-html (post blorgv-blog-url)
  "Render POST in html with BLORGV-BLOG-URL."
  (let* ((blorgv-post-raw-title (plist-get post :post-title))
	 (blorgv-post-rel-url (blorg-make-post-url blorgv-post-raw-title))
	 (blorgv-post-title (blorg-escape blorgv-post-raw-title 'entity))
	 (post-abs-url (concat blorgv-blog-url blorgv-post-rel-url))
	 (tags (delete "" (split-string (plist-get post :post-tags) ":")))
	 (post-tags (mapconcat (lambda (tag) tag) tags " "))
	 (blorgv-tags-links (blorg-make-keywords-links tags))
	 (technorati-tags-links 
	  (blorg-make-keywords-links tags 'technorati))
	 (blorgv-content (plist-get post :post-content)))
    (plist-put blorgv-header :tp-published
	       (blorg-timestamp-to-readable (plist-get post :post-closed)))
    (plist-put blorgv-header :tp-updated
	       (blorg-timestamp-to-readable (plist-get post :post-updated)))
    (blorg-insert-body blorg-post-template)))


(defun blorg-make-post-url (blorgv-post-title)
  "Make a permanent url from BLORGV-POST-TITLE."
  (with-temp-buffer
    (insert blorgv-post-title)
    (goto-char (point-min))
    (while (< (point) (point-max))
      (cond ((member (char-after) '(233 232 224 244 239 249))
	     (progn (delete-char 1)))
	    ((member (char-after) '(?  ?\' ?/ ?% ?# ?= ?+))
	     (progn (delete-char 1) (insert "-")))
	    ((member (char-after)
		     '(?\" ?, ?\; ?: ?? ?! ?. ?$ ?\t ?< ?> ?&))
	     (progn (delete-char 1)))
	    ((not (eq (car (split-char (char-after))) 'ascii))
	     (delete-char 1))
	    (t (forward-char 1))))
    (concat (replace-regexp-in-string "-+$" "" (buffer-string))
	    (plist-get blorg-strings :page-extension))))


(defun blorg-limit-content-to-month (blorgv-content month)
  "Limit BLORGV-CONTENT to posts of the MONTH."
  (delq nil
	(mapcar (lambda (post)
		  (when (and (plist-get post :post-closed)
			     (string-match
			      (caddr month)
			      (format-time-string 
			       (car blorgv-time-stamp-formats)
			       (plist-get post :post-closed))))
		    post)) blorgv-content)))


(defun blorg-limit-content-to-tag (blorgv-content tag-name)
  "Limit BLORGV-CONTENT to posts with TAG-NAME."
  (delq nil
	(mapcar (lambda (post)
		  (when (string-match
			 (regexp-quote tag-name)
			 (plist-get post :post-tags))
		    post)) blorgv-content)))


(defun blorg-strip-trailing-spaces (string)
  "Remove trailing whitespace in STRING."
  (replace-regexp-in-string "[ \t]+$" "" string))


(defun blorg-split-template (tpl)
  "Split TPL into a list of functions."
  (let* ((lst (split-string tpl "[\(\)]"))
	 (cnt 0))
    (dotimes (cnt (length lst))
      (when (fboundp (intern-soft (nth cnt lst)))
	(setf (nth cnt lst)
	      (intern-soft (nth cnt lst))))) lst))


(defun blorg-insert-body (tpl)
  "Insert body of TPL."
  (mapc (lambda (func) (eval func))
	(mapcar (lambda (part)
		  (if (stringp part)
		      (list 'insert part)
		    (macroexpand `(,part))))
		(blorg-split-template tpl))))


(defun blorg-sort-content-tag (blorgv-content tag-name)
  "Remove posts from BLORGV-CONTENT if they don't match TAG-NAME."
  (delq nil
	(mapcar
	 '(lambda (post)
	    (when (string-match
		   (regexp-quote tag-name)
		   (plist-get post :post-tags))
	      post))
	 blorgv-content)))


(defun blorg-make-keywords-links (tags &optional site cloud)
  "Convert TAGS into links with SITE."
  (mapconcat
   (lambda (tag)
     (cond ((eq site 'technorati)
	    (concat "<a href=\"http://technorati.com/tag/" 
		    tag "\">" tag "</a>"))
	   (t (concat "<a href=\"" (blorg-make-post-url tag) 
		      "\">" tag "</a>")))) tags " "))

;; interleave the ASCII code for a character with some insignificant markup
(defun char-to-markup (ch)
  "Obfuscated HTML fragment for a character"
  (format "<span style=\"display:none\"/>&#x%x;<span style=\"display:none\"/>" (string-to-char ch)))

;; create script to insert a certain character in a string
(defun char-to-script (ch)
  "Obfuscated JavaScript fragment for a character"
  (format "'+String.fromCharCode(%2d)+'" (string-to-char ch)))

;; wrap a simple string into an expression to force evaluation
(defun string-to-expr (str)
  "JavaScript expression that always evaluate to string"
  (concat "'+(1?'" str "':0)+'"))

;; use a script to generate the mailto: link dynamically
(defun mailto-script (addr)
  "Obfuscated mailto: link"
  (let* ((dot-in-script (mapconcat 'string-to-expr
								   (split-string addr  "[.]")
								   (char-to-script ".")))
		 (email-script  (mapconcat 'string-to-expr
								   (split-string dot-in-script "[@]")
								   (char-to-script "@")))
		 (mailto-link   (concat "'mai'+'lto" (char-to-script ":") email-script "'")))
	(concat "javascript:window.location=" mailto-link ";void(0)")))

;;; Macros
(defmacro blorg-insert-index-url nil
  "Insert index url."
  `(insert (concat (plist-get blorg-strings :index-page-name)
		   (plist-get blorg-strings :page-extension))))

(defmacro blorg-insert-tag-name nil
  "Insert tag-name."
  `(insert tag-name))

(defmacro blorg-insert-month-name nil
  "Insert month-name."
  `(insert month-name))

(defmacro blorg-insert-email nil
  "Insert blorgv-email."
  `(insert blorgv-email))

;; replace all dots and at signs in the email address with markup
(defmacro blorg-insert-mailto-email nil
  "Insert email"
  `(insert (mailto-script blorgv-email)))

(defmacro blorg-insert-homepage nil
  "Insert blorgv-homepage."
  `(insert blorgv-homepage))

(defmacro blorg-insert-author nil
  "Insert blorgv-author."
  `(insert blorgv-author))

(defmacro blorg-insert-page-title nil
  "Insert page-title."
  `(insert blorgv-blog-title))

(defmacro blorg-insert-page-subtitle nil
  "Insert page-subtitle."
  `(insert blorgv-subtitle))

(defmacro blorg-insert-content nil
  "Insert main blorgv-content."
  `(mapc
    (lambda (new-post)
      (blorg-render-content-html
       new-post blorgv-blog-url))
    ctnt))

(defmacro blorg-insert-previous-posts nil
  "Insert previous posts list."
  `(when (not (or blorgv-publish-index-only
		  (null previous-posts)))
     (insert (blorg-render-previous-posts-list
	      previous-posts))))

(defmacro blorg-insert-tags-as-list nil
  "Insert tags list."
   `(when (not (or blorgv-publish-index-only
		   (null tags)))
      (insert (blorg-render-tags-list-html tags))))

(defmacro blorg-insert-tags-as-cloud nil
  "Insert tags list."
   `(when (not (or blorgv-publish-index-only
		   (null tags)))
      (insert (blorg-render-tags-cloud-html tags))))


(defmacro blorg-insert-archives nil
  "Insert archive list."
  `(when (not blorgv-publish-index-only)
     (insert (blorg-render-archives-list-html
		  months-list))))

(defmacro blorg-insert-post-title nil
  "Insert title of the post."
  `(insert blorgv-post-title))

(defmacro blorg-insert-post-url nil
  "Insert full url of the post."
  `(insert blorgv-post-rel-url))

(defmacro blorg-insert-post-publication-date nil
  "Insert publication date of the post."
  `(insert (plist-get blorgv-header :tp-published)))

(defmacro blorg-insert-post-modification-date nil
  "Insert modification date of the post."
  `(insert (plist-get blorgv-header :tp-updated)))

(defmacro blorg-insert-this-post-tags nil
  "Insert tags of the post."
  `(insert blorgv-tags-links))


;; Don't put this as a default in templates
(defmacro blorg-insert-this-post-tags-to-technorati nil
  "Insert technorati-tags links of the post."
  `(insert technorati-tags-links))


(defmacro blorg-insert-post-content nil
  "Insert post blorgv-content."
  (list 'insert `(blorg-render-post-content-html
		  blorgv-content ,(not (null blorgv-ins-full))
		  blorgv-post-title)))


(defmacro blorg-insert-post-echos nil
  "Insert \"echos\"links from `blorg-echos-alist'."
  `(when (not (null ins-echos))
     (insert "<div class=\"post-echos\">\n")
     (dolist (elt blorg-echos-alist)
       (insert " " (apply 'format elt)
	       "\n"))
     (insert " </div>\n")))


(defmacro blorg-insert-post-author nil
  "Insert blorgv-author in post."
    `(when (not (null ins-auth))
       (mapc (lambda (func) (eval func))
	     (mapcar (lambda (part)
		       (if (stringp part)
			   (list 'insert part)
			 (macroexpand `(,part))))
		     (blorg-split-template
		      blorg-post-author-template)))))


(defmacro blorg-insert-post-dates nil
  "Insert dates in post."
    `(when (not (null ins-dates))
       (mapc (lambda (func) (eval func))
	     (mapcar (lambda (part)
		       (if (stringp part)
			   (list 'insert part)
			 (macroexpand `(,part))))
		     (blorg-split-template
		      blorg-post-dates-template)))))


(defmacro blorg-insert-post-tags nil
  "Insert tags in post."
  `(when (and (not (null ins-tags))
	      (not (equal ,blorgv-tags-links "")))
       (mapc (lambda (func) (eval func))
	     (mapcar (lambda (part)
		       (if (stringp part)
			   (list 'insert part)
			 (macroexpand `(,part))))
		     (blorg-split-template
		      blorg-post-tags-template)))))

;;; Exporting to HTML
(defconst blorg-special-html-chars
  '(("&"  . (entity "&amp;"  esccode "%26"))
	("\"" . (entity "&quot;" esccode "%22"))
	("'"  . (entity "&apos;" esccode "%27"))
	("<"  . (entity "&lt;"   esccode "%3C"))
	(">"  . (entity "&gt;"   esccode "%3E"))
	))

(defun blorg-escape (text how)
  "Escape special XML/HTML characters -- <, >, &, etc."
  (when text
	(save-match-data
	  (mapcar (lambda (x)
				(setf text (replace-regexp-in-string (car x) (plist-get (cdr x) how) text)))
			  blorg-special-html-chars))
	text))

(defun blorg-truncate-org-post (blorgv-post-title)
  "Truncates the current buffer after the blorg-parg-in-headlines-th paragraph,
and adds a read-mode link."
  (goto-char (point-min))
  (forward-paragraph blorg-parg-in-headlines)
  (delete-blank-lines)
  (unless (eq (point) (point-max))
    (insert "\n[[./"
            (blorg-make-post-url blorgv-post-title)
            "]["
            (plist-get blorg-strings :read-more)
            "]]"))
  (delete-region (point) (point-max)))

(defun blorg-render-post-content-html
  (blorgv-content full blorgv-post-title)
  "Render BLORGV-CONTENT of a post.
When FULL render full blorgv-content, otherwise just insert some headlines."
  (with-temp-buffer
		(let ((out-buf (buffer-name)))
		  (unwind-protect
			  (with-temp-buffer
				(unless (eq major-mode 'org-mode)
							(org-mode))
				(insert blorgv-content)
				(blorg-trim-leading-and-trailing-lines)
				(blorg-rewrite-local-links)
				(unless full
				  (blorg-truncate-org-post blorgv-post-title))
				(save-excursion
				  (goto-char (point-min))
				  (insert "*\n")) ; dummy item for this post
				;; use externally defined stylesheet, not editor settings
				(let ((org-export-htmlize-output-type 'css)
					  (org-export-htmlize-css-font-prefix "code-"))
				  (org-export-as-html 3 nil nil out-buf t)))))
		(buffer-string)))

(defun blorg-rewrite-local-links ()
  ;; inspect each link
  (save-excursion
    (goto-char (point-min))
    (open-line 1)
    (while (next-single-property-change (point) 'face)
      (goto-char (next-single-property-change (point) 'face))
	  (when (equal 'org-link (get-text-property (point) 'face))
		(when (looking-at org-bracket-link-analytic-regexp)
		  ;; decompose link
		  (let ((url-type (match-string 2))
				(raw-link (match-string 3))
				(link-desc (match-string 5)))
			;; local files only
			(when (equal url-type "file")
			  ;; image file?
			  (let* ((raw-rel-link (file-name-nondirectory raw-link))
					 (raw-link-ext (file-name-extension raw-link))
					 (sub-d (if (and raw-link-ext
									 (save-match-data
									   (string-match (regexp-opt
													  image-file-name-extensions)
													 raw-link-ext)))
								blorgv-images-d
							  blorgv-upload-d)))
				;; copy to appropriate directory
				(let ((src-f (substring-no-properties raw-link))
					  (dst-f (substring-no-properties (concat blorgv-publish-d
															  sub-d
															  raw-rel-link))))
				  (blorg-cp-if-newer src-f dst-f))
				;; rewrite with link to new directory.
				(replace-match (concat "[[./" sub-d raw-rel-link
									   (if link-desc (concat "][" link-desc))
									   "]]"))))))))))

(defun blorg-cp-if-newer (src-f dst-f)
  "Copy SRC-F to DST-F if the latter does not exist or is older."
  (save-match-data
	(if (file-readable-p src-f)
		(if (or (not (file-exists-p dst-f))
				(file-newer-than-file-p src-f dst-f))
			(eshell/cp src-f dst-f)))))

(defun blorg-trim-leading-and-trailing-lines ()
  (save-excursion
	(goto-char (point-min))
	(delete-blank-lines)
	(goto-char (point-max))
	(delete-blank-lines)))

(defun blorg-render-post-content-txt (blorgv-content)
  "Render BLORGV-CONTENT of a post.
When FULL render full blorgv-content, otherwise just insert some headlines.
You can give a specific BLORGV-POST-TITLE to this post."
  (with-temp-buffer
    (insert blorgv-content)
	(blorg-trim-leading-and-trailing-lines)
    (buffer-string)))


(defun blorg-make-arch-month-list
  (blorgv-created blorgv-content)
    "Depending on BLORGV-CREATED date, make a list from BLORGV-CONTENT containing each archived month."
    (unless (not blorgv-content)
  (let* ((start-y (nth 5 (decode-time blorgv-created)))
	 (start-m (nth 4 (decode-time blorgv-created)))
	 (end-y (nth 5 (decode-time)))
	 (end-m (nth 4 (decode-time)))
	 (nb-of-m (calendar-interval start-m start-y end-m end-y))
	 arch-list)
    (while (<= 0 nb-of-m)
      (let ((month (mod end-m 12)))
	(when (eq month 0)
	  (progn (setq end-y (1- end-y))
		 (setq month 12)))
	(add-to-list
	 'arch-list
	 (list
	  ;; make labels for month-urls
	  (concat (calendar-month-name month)
		  " " (number-to-string end-y))
	  ;; make urls for months
	  (concat (number-to-string end-y)
		  (format "%02d" month)
		  (plist-get blorg-strings :page-extension))
	  ;; make "2006-05"-like string
	  (concat (number-to-string end-y)
		  "-" (format "%02d" month))) t)
	(setq end-m (1- end-m))
	(setq nb-of-m (1- nb-of-m))))
    (delq nil (blorg-check-arch-list arch-list blorgv-content)))))


(defun blorg-check-arch-list
  (months-list blorgv-content)
  "Check relevant entries in MONTHS-LIST depending on BLORGV-CONTENT."
  (mapcar
   (lambda (month)
     (let ((month-str (nth 2 month)))
       (when (memq
	      't
	      (mapcar (lambda (post)
			(not (null (string-match 
				    month-str 
				    (format-time-string 
				     (car blorgv-time-stamp-formats)
				     (plist-get post :post-closed))))))
		      blorgv-content))
	 month)))
   months-list))

;;; Time functions
(defun blorg-timestamp-to-rfc3339 (time)
  "Convert an `org-mode' TIMESTAMP to a RFC3339 time format.
Example: 1990-12-31T15:59:60-08:00"
  (let* ((system-time-locale "C")
	 (zone1 (substring (format-time-string "%z" time nil) 0 3))
	 (zone2 (substring (format-time-string "%z" time nil) 3)))
    (concat (format-time-string "%Y-%m-%dT%H:%M:%S" time nil)
	    zone1 ":" zone2)))


(defun blorg-timestamp-to-rfc822 (time)
  "Convert an `org-mode' TIMESTAMP to a RFC822 time format.
Example: Wed, 02 Oct 2002 15:00:00 +0200"
  (let* ((system-time-locale "C"))
    (concat (format-time-string "%a, %d %b %Y %H:%M:%S %z" time nil))))


(defun blorg-timestamp-to-readable (time)
  "Convert an `org-mode' TIMESTAMP to a readable format.
Example: Sunday, May 07 2006 @ 10:35 +0100"
  (let ((system-time-locale blorgv-language))
    (format-time-string 
     (plist-get blorg-strings :time-format) time nil)))

(defun blorg-timestamp-to-iso8601 (time)
  "Convert an `org-mode` TIMESTAMP to ISO-8601 format.
Example: 2011-12-31 13:59"
  (format-time-string "%Y-%m-%d %H:%M" time))

(defun blorg-encode-time (timestamp &optional incl-time)
  "Encode TIMESTAMP."
  (let ((format (concat "\\([0-9]+\\)-\\([0-9]+\\)-\\([0-9]+\\)"
						(if incl-time
							 " \\(.*?\\) \\([0-9]+\\):\\([0-9]+\\)"))))				  
  (when (string-match format timestamp)
    (let ((year (string-to-number (match-string 1 timestamp)))
	  (month (string-to-number (match-string 2 timestamp)))
	  (day (string-to-number (match-string 3 timestamp)))
	  (hour (if (match-string 5 timestamp)
		  (string-to-number (match-string 5 timestamp)) 0))
	  (min (if (match-string 6 timestamp)
		  (string-to-number (match-string 6 timestamp)) 0)))
      (encode-time 0 min hour day month year)))))



;;;;##########################################################################
;;;;  User Options, Variables
;;;;##########################################################################

;; Local Variables: ***
;; mode:outline-minor ***
;; End: ***

;;; blorg.el ends here
