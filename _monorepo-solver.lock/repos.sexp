(ox (
  (full_repo
   git+https://github.com/oxcaml/opam-repository.git#a1ea0d33dd5662b89183f751c3fec566d7860b75)
  (single_file_http
   https://raw.githubusercontent.com/oxcaml/opam-repository/a1ea0d33dd5662b89183f751c3fec566d7860b75/)
  (filter (
    Exclude (
      js_of_ocaml
      js_of_ocaml-compiler
      js_of_ocaml-ppx
      js_of_ocaml-toplevel
      wasm_of_ocaml-compiler)))))

(ox-jsoo-fix (
  (full_repo
   git+https://github.com/patricoferris/oxcaml-opam-repository.git#78bb9a342435a78a5737f2d96d8feabc7a19a8fb)
  (single_file_http
   https://raw.githubusercontent.com/patricoferris/oxcaml-opam-repository/78bb9a342435a78a5737f2d96d8feabc7a19a8fb/)
  (filter (
    Include (
      js_of_ocaml
      js_of_ocaml-compiler
      js_of_ocaml-ppx
      js_of_ocaml-toplevel
      wasm_of_ocaml-compiler)))))

(dune-overlays (
  (full_repo
   git+https://github.com/dune-universe/opam-overlays.git#e439455c8cff141dfa65b29be6eb385fb756b37e)
  (single_file_http
   https://raw.githubusercontent.com/dune-universe/opam-overlays/e439455c8cff141dfa65b29be6eb385fb756b37e/)
  (filter (
    Include (
      astring findlib fmt fpath jsonm logs num ocamlfind uchar uucp xmlm)))))

(opam (
  (full_repo
   git+https://github.com/ocaml/opam-repository.git#8a528d6bb48e4be260fb670a1754df39a1192147)
  (single_file_http
   https://raw.githubusercontent.com/ocaml/opam-repository/8a528d6bb48e4be260fb670a1754df39a1192147/)))
