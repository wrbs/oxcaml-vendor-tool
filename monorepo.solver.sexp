(repos (
  ;; js-of-ocaml in oxcaml repo is broken, this branch has fixes
  (ox (github patricoferris/oxcaml-opam-repository jsoo))
  ;; (ox (github oxcaml/opam-repository main))
  (dune-overlays (github dune-universe/opam-overlays master))
  (opam (github ocaml/opam-repository master))))

(env (
  (arch            x86_64)
  (os              linux)
  (os_distribution linux)
  (os_family       linux)
  (os_version      system)))

(package_selection (
  (include ((ocaml-variants = 5.2.0+ox)))
  (include_all_matching_version
    ;; this is highly specialized for getting latest version of all JS packages
    ;; in ox, probably no other use case
    (in_repo ox)
    (of_     core))
  ;; unnecesary dune-overlays matches (could complicate solver to resolve but
  ;; this works for now)
  (include (
    (astring >= 0.8.5)
    (menhir  >  20200624)))
  ;; not working
  (exclude (netsnmp torch ocaml_simd ppx_demo))
  (exclude (
    ;; opam memtrace doesn't work with compiler libs
    ecaml
    memtrace_viewer))
  ;; too new
  (include (
    (cohttp       = 5.3.0)
    (cohttp-async = 5.3.0)))))

(vendoring (
  (exclude_pkgs (ocamlbuild ocamlfind findlib dune-configurator))
  ;; avoid naming conflicts where oxcaml repo splits same source into different
  ;; packages with different patches
  (rename_dirs ((ppxlib_ast ppxlib_ast)))
  ;; exclude source dirs, no matter what packages provided them
  (exclude_dirs (ocaml))
  ;; custom commands in the opam file that need to run before the build
  (prepare_commands (
    (ppxlib ((rm -rf ast astlib stdppx traverse_builtins)))
    (ppxlib_ast ((bash ./cleanup.sh)))))))
