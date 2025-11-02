(lang dune 3.17)

(name oxcaml-vendor-tool)

(generate_opam_files)

(package
 (name oxcaml-vendor-tool)
 (depends
  (ocaml
   (>= 5.3.0))
  core
  core_unix
  async_ssl
  async
  ppx_jane
  cohttp-async
  jsonaf
  of_json
  opam-core
  opam-0install
  opam-repository
  sexp_pretty))
