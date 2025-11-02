((dune 3.20.2+ox)
 ((ocaml boot/bootstrap.ml -j (jobs))
  (./_boot/dune.exe
   build
   dune.install
   --release
   --profile
   dune-bootstrap
   -j
   (jobs))))

((lwt 5.9.2+ox)
 (((dune subst) :if dev)
  (dune exec -p
    (name)
    src/unix/config/discover.exe
    --
    --save
    --use-libev
    %{conf-libev:installed}%)
  (dune build -p
    (name)
    -j
    (jobs)
    @install
    (@runtest :if with-test)
    (@doc     :if with-doc))))

((ppxlib 0.33.0+ox)
 ((rm -rf ast astlib stdppx traverse_builtins)
  ((dune subst) :if dev)
  (dune build -p
    (name)
    -j
    (jobs)
    @install
    (@runtest :if with-test)
    (@doc     :if with-doc))))

((ppxlib_ast 0.33.0+ox)
 ((bash ./cleanup.sh)
  ((dune subst) :if dev)
  (dune build -p
    (name)
    -j
    (jobs)
    @install
    (@runtest :if with-test)
    (@doc     :if with-doc))))

((topkg 1.0.8+ox)
 ((ocaml pkg/pkg.ml build --pkg-name (name) --dev-pkg %{dev}%)))

((uutf 1.0.3+ox)
 ((
   ocaml
   pkg/pkg.ml
   build
   --dev-pkg
   %{dev}%
   --with-cmdliner
   %{cmdliner:installed}%)))

((zarith 1.12+ox)
 (((./configure)
   :if
   "os != \"openbsd\" & os != \"freebsd\" & os != \"macos\"")
  ((sh
    -exc
    "LDFLAGS=\"$LDFLAGS -L/usr/local/lib\" CFLAGS=\"$CFLAGS -I/usr/local/include\" ./configure")
   :if
   "os = \"openbsd\" | os = \"freebsd\"")
  ((sh
    -exc
    "LDFLAGS=\"$LDFLAGS -L/opt/local/lib -L/usr/local/lib\" CFLAGS=\"$CFLAGS -I/opt/local/include -I/usr/local/include\" ./configure")
   :if
   "os = \"macos\" & os-distribution != \"homebrew\"")
  ((sh
    -exc
    "LDFLAGS=\"$LDFLAGS -L/opt/local/lib -L/usr/local/lib\" CFLAGS=\"$CFLAGS -I/opt/local/include -I/usr/local/include\" ./configure")
   :if
   "os = \"macos\" & os-distribution = \"homebrew\" & arch = \"x86_64\"")
  ((sh
    -exc
    "LDFLAGS=\"$LDFLAGS -L/opt/homebrew/lib\" CFLAGS=\"$CFLAGS -I/opt/homebrew/include\" ./configure")
   :if
   "os = \"macos\" & os-distribution = \"homebrew\" & arch = \"arm64\"")
  ((make))))

((cmdliner 1.3.0) (((make) all PREFIX=%{prefix}%)))
