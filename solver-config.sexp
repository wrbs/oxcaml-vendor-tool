(repos (
  ;; (ox (github oxcaml/opam-repository main))
  (ox (github patricoferris/oxcaml-opam-repository jsoo))
  (dune-overlays (github dune-universe/opam-overlays master))
  (opam (github ocaml/opam-repository master))))

(env (
  (arch            x86_64)
  (os              linux)
  (os_distribution linux)
  (os_family       linux)
  (os_version      system)))

(package_selection (
  (include_all_matching_version
    ;; this is highly specialized for getting latest version of all JS packages
    ;; in ox, probably no other use case
    (in_repo ox)
    (of_     core))
  (include (grace))
  ;; (include (package (package (= version)) (package (< version)))) ...
  ;; (exclude (package1 package2 ...))
))

(vendoring (
  (exclude (dune ocamlbuild))
  ;; avoid naming conflicts where oxcaml repo splits same source into different
  ;; packages with different patches
  (rename_dirs (
    (ojs        ojs)
    (ppxlib_ast ppxlib_ast)))
  ;; custom commands in the opam file that need to run before the build
  (prepare_commands (
    (ppxlib ((rm -rf ast astlib stdppx traverse_builtins)))
    (ppxlib_ast ((bash ./cleanup.sh)))))))
