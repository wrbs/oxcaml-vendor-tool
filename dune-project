(lang dune 3.17)

(name oxcaml-vendor-tool)

(package
 (name oxcaml-vendor-tool)
 (allow_empty)
 (depends
  (ocaml
   (>= 5.3.0))
  core
  core_unix
  async
  ppx_jane))
