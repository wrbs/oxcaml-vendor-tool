#!/bin/bash

set -euo pipefail
_build/default/bin/main.exe lock
_build/default/bin/main.exe pull

dune format-dune-file _monorepo-solver.lock/dune-snippet >_example/dune
