# oxcaml-vendor-tool

This is a set of tools and patches to combine together a whole bunch of
packages, code and patches to build a large 'oxcaml monorepo' where nearly all
dependencies are vendored into the dune workspace and build as part of its
build.

This means that things like go to definition works within the implementation of
dependencies, not just the first step from your project. You can also experiment
with tweaks to local libraries.

### Comparisons

It's like opam-monorepo but

- works with patches (needed for lots of things in the oxcaml repo)
- less general/will potentially do some things wrong outside of the tested use
  case
- doesn't care as much about compatibility with opam/producing opam lock files
- has some tooling to manage custom patches on top of what upstream gives
- exposes internal phases to allow tweaking

Tested against most open source Jane Street packages and their dependencies (see
`_example/dune` for what builds).

## Using

Don't have detailed instructions yet as it's not quite ready for being released
as a general tool on opam (and may never if I don't get around to it): you'll
have to build it yourself (see below).

If you can get the example working, you can copy the vendor directory it
produces into your own monorepo and commit it for now.

### Building

The tool doesn't rely on anything oxcaml, and uses dune's own package management
for its dependencies. Use an existing switch, or create one and link it for this
directory:

    opam switch create dune-pm 5.3.0
    opam install dune ocamlformat ocaml-lsp-server
    opam switch link dune-pm  # ensure you use in this dir

Build:

    dune build @default @runtest --watch

### Testing

Fetch the locked sources + apply patches

    _build/default/bin/main.exe pull

Set up a switch and install the dev tools

    opam switch create oxcaml-monorepo 5.2.0+ox --repos ox=git+https://github.com/oxcaml/opam-repository.git,default
    opam install -y ocamlformat merlin ocaml-lsp-server utop sexp dune
    cd _example && opam switch link oxcaml-monorepo

The vendored dirs has the source for some packages/tests in it that won't build
without other deps; the only packages that are likely to work are those defined
in the `@vendored-pkgs` alias.

You can test those build with:

    dune build @vendored-pkgs

### Tweaking for now

Tweak `monorepo.solver.sexp`. Then run `rebuild-example.sh` (which locks, pulls and copies in the alias definition for testing)

Test with above instructions/the oxcaml switch.

Debug with the files in `_monorepo-solver.lock` / see the repos at
`_cache/monorepo/repos`.

To add/update a patch to `patches`, make the vendor directory look like you want
it to stay, get it building then run

    _build/default/bin/main.exe update-patch DIR_NAME

Otherwise subsequent pulls will wipe out local modifications

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

This is where the lock file + any local patches (in `patches` get applied).

Fetched files are cached to `_cache/monorepo/opam-dl`

Local patches are relative to the 'upstream source' which may have its own
upstream patches applied.

Additionally, a `dune` file is created in the output directory

- marking subdirectories as vendored
- defining an alias `@vendored-pkgs` that can be used to build every vendored
package