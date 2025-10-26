(repos (
  (ox (github oxcaml/opam-repository main))
  (dune-overlays (github dune-universe/opam-overlays master))
  (opam (github ocaml/opam-repository master))))

(env (
  (arch            x86_64)
  (os              linux)
  (os_distribution linux)
  (os_family       linux)
  (os_version      system)))

(package_selection (
  ;; this is highly specialized for getting all JS packages in ox, probably no
  ;; other use case
  (include_all_matching_version
    (in_repo ox)
    (of_     core))
  ;; extra packages
  (include (
    grace
    ;; (grace "=1.2.3")
  ))
  ;; todo: exclude if we need it
))

(vendoring (
  (exclude (dune ocamlbuild))
  ;; avoid naming conflicts if JS splits things into 2 packages
  (rename_dirs (
    (ojs        ojs)
    (ppxlib_ast ppxlib_ast)))
  ;; custom commands in the opam file that need to run before the build
  (prepare_commands (
    (ppxlib ((rm -rf ast astlib stdppx traverse_builtins)))
    (ppxlib_ast ((bash ./cleanup.sh)))))))
