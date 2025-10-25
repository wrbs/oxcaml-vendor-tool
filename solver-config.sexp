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

(vendoring ((exclude (dune ocamlbuild))))
