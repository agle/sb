(lang dune 3.19)

(name sb)

(version 0.0.1)

(generate_opam_files true)

(source
 (github agle/sb))

(authors "Alicia Michael <a.michael1@uq.edu.au>")

(maintainers "Alicia Michael <a.michael1@uq.edu.au>")

(license BSD-2-Clause)

(documentation https://github.com/agle/sb)

(package
 (name sb)
 (synopsis "A short synopsis")
 (description "A longer description")
 (depends 
   ocaml
   cow
   calendar
   cmarkit
   hilite
   rss
   containers
   inotify
   tiny_httpd
   ocaml-lua
   ocaml-katex

  (ocaml-lsp-server :with-dev-setup)
  (ocamlformat :with-dev-setup)
  (odig :with-dev-setup)
   )
 (tags
  ("web" "markdown")))

