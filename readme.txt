
sb: site build

a hacky opinionated script for converting a folder of markdown
to a website.

generally we just wrap ocaml libraries with a basic 2-phase
directory traversal; first pass collects and renders inner content,
second pass injects the content into templates

features

  - commonmark with extensions
  - lua-based templating
  - rss feed generation
  - server-side code highlighting for languages supported by hilite:
      ocaml, dune, opam, sh, shell, diff, bash
  - server-side latex rendering using KaTeX
  - local live preview


install:




