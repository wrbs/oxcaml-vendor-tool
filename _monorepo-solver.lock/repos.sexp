(ox (
  (full_repo
   git+https://github.com/oxcaml/opam-repository.git#a1ea0d33dd5662b89183f751c3fec566d7860b75)
  (single_file_http
   https://raw.githubusercontent.com/oxcaml/opam-repository/a1ea0d33dd5662b89183f751c3fec566d7860b75/)))

(dune-overlays (
  (full_repo
   git+https://github.com/dune-universe/opam-overlays.git#d5c12f6d5c7909e6119a82bc4aba682ac3110b2d)
  (single_file_http
   https://raw.githubusercontent.com/dune-universe/opam-overlays/d5c12f6d5c7909e6119a82bc4aba682ac3110b2d/)
  (filter (
    Include (
      astring findlib fmt fpath jsonm logs num ocamlfind uchar uucp xmlm)))))

(opam (
  (full_repo
   git+https://github.com/ocaml/opam-repository.git#ee3428377a13c3c9716b6f791c33441cfb542498)
  (single_file_http
   https://raw.githubusercontent.com/ocaml/opam-repository/ee3428377a13c3c9716b6f791c33441cfb542498/)))
