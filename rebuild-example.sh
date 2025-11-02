#!/bin/bash

set -euo pipefail
_build/default/bin/main.exe lock -no-update-repos
# _build/default/bin/main.exe lock
_build/default/bin/main.exe pull
