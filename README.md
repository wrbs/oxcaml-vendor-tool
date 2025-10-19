# oxcaml-vendor-tool

This is a set of tools and patches to combine together a whole bunch of
packages, code and patches to build a large 'oxcaml monorepo' with 

- every jane street publically released package (latest versions on oxcaml repo)
- their dependencies
- other compatible open source things (especially those that follow base/core'y
  conventions)

Actually building this monorepo doesn't rely on opam at all (except to install
the compiler and tools needed for building).

This monorepo is built in ocaml, but not oxcaml -- it uses dune's own package
management for reproducible builds and the stable version of jane street things.

## Goals

- Reproducibility
- Document patches needed to things
- Ultimately publish the result to its own place

## Patches

The starting point for things is whatever oxcaml-repository releases (using its
patches if relevant).

Then on top of that we have patches for if we need to

- make things build with dune
- fix anything not yet fixed in the oxcaml public release

## Getting started

This is the instructions for running this tooling

    opam switch create dune-pm 5.3.0
    opam install dune ocamlformat ocaml-lsp-server

Install packages

    dune build @pkg-install

Normal dev

    dune build @default @runtest --watch
