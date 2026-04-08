
sg: site generator

a hacky opinionated script for converting a folder of markdown
to a website.

generally we just wrap ocaml libraries with a basic 2-phase
directory traversal; first pass collects and renders inner content,
second pass injects the content into templates

features

  - commonmark with extensions
  - lua-based templating
  - server-side code highlighting for languages supported by hilite
  - server-side latex rendering using KaTeX
  - local live preview




