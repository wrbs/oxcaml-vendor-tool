# oxcaml-vendor-tool

This is a set of tools and patches to combine together a whole bunch of
packages, code and patches to build a large 'oxcaml monorepo'.

Main advantage of using this model over using opam is dependencies build locally
in the workspace with dune if needed by a package in the workspace: this means
go to definition/merlin/... works even within dependencies.

It's like opam-monorepo but

- works with patches (needed for lots of things in the oxcaml repo)
- less general/will potentially do some things wrong outside of the tested use
  case
- maybe a bit less tied to compatibility with opam
- exposes internal phases to allow tweaking
- has some tooling to manage custom patches on top of what upstream gives

~~Tested against every open source jane street package and their dependencies.~~
(TODO update once true)

## Using

TODO document

## Phases

There are 2 main phases:

1. Solving, which takes `monorepo.solver.sexp` as config and produces
   `monorepo.lock.sexp` with a plan for each vendor dir. This is the stage that
   cares about opam repos/packages/versions
2. Fetching, upstream patching + custom patching: takes the `monorepo.lock.sexp`
   and local patches and produces a vendored directory in the context of a
   larger dune project.

## Solving

This phase produces `monorepo.lock.sexp` from `monorepo.solver.sexp` + opam
repositories.

Run everything with `oxcaml-vendor-tool lock`, or to debug breakages you can
split into phases and potentially tweak the outputs between them.

To rerun all the phases of locking but keeping the upstream repos at the
previously used revision, use

    oxcaml-vendor-tool lock -no-update-repos 

### Phase 1: repo sync

    oxcaml-vendor-tool lock-phases repo-lock-and-sync
    oxcaml-vendor-tool lock-phases repo-sync-only  # doesn't update locks.

Turns refs in `repos` in the solver config sexp into actual commits, then
fetches the sources to `_cache/monorepo/repos`. Locks repo commit hashes in 
`_monorepo-solver.lock/repos.sexp`

### Phase 2: desired package selection

    oxcaml-vendor-tool lock-phases resolve-desired-packages

Applies the operations in `package_selection` in the solver config to determine
the desired packages/version constraints. Output locked in
`_monorepo-solver.lock/desired-packages.sexp` 


### Phase 3: solving

    oxcaml-vendor-tool lock-phases run-solver

Uses [opam-0install-solver](https://github.com/ocaml-opam/opam-0install-solver) to 
determine the versions of packages and dependencies that satisfies the desired
package selection. Stores outputs in `_monorepo-solver.lock/packages.sexp` and
caches opams of selected packages in `_monorepo-solver.lock/opams/`.


### Phase 4: planning vendoring + writing main lock

    oxcaml-vendor-tool lock-phases vendor-planner

Turns the packages the solver selected into the main `monorepo.lock.sexp`.
Configured by `vendoring` in the solver config.

Involves:

- determining if packages actually should be vendored or not
- working out which vendor directory to put packages in (some directories have
multiple packages)
- working out when to not put things in the same directory (some oxcaml
packages should go in different directories despite using the same upstream repo
because patches/custom prepare commands remove different parts)

This is the most heuristicy part -- may need tool changes in the future.

Take a look at `_monorepo-solver.lock/nonstandard-build-packages.sexp` for
packages that may need either

- patches to build with dune
- custom `prepare_commands` to prepare the directory.

## Fetch and patch

TODO document

## Developing tooling

The tool doesn't rely on anything oxcaml, and uses dune's own package management for its dependencies.

    opam switch create dune-pm 5.3.0
    opam install dune ocamlformat ocaml-lsp-server
    opam switch link dune-pm  # ensure you use in this dir

Install packages (optional, but test it's all working)

    dune build @pkg-install

Normal dev

    dune build @default @runtest --watch
