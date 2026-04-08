
sb: site build

a hacky opinionated script for converting a folder of markdown
to a website.

generally we just wrap ocaml libraries with a basic 2-phase
directory traversal; first pass collects and renders inner content,
second pass injects the content into templates

features

  - commonmark with extensions (cmarkit)
  - lua-based templating (ocaml-lua)
  - rss feed generation (rss)
  - server-side code highlighting for languages supported by hilite:
      ocaml, dune, opam, sh, shell, diff, bash
  - server-side latex rendering using KaTeX
  - local live preview

install: download from releases tab

help:

  sb [ optional args ]
    -i set input directory, default: src
    -o set output directory, default: build
    --templates set templates directory, default: templates
    --url set site public url, default: http://localhost:8000/
    --prelude prelude file for lua-based templater, default: nil
    --preview port, live preview bind to port, default: nil
    --title set site name title, default: site title
    -help  Display this list of options
    --help  Display this list of options




