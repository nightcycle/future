#!/bin/sh
set -e
lune run tests/await.lune.luau
lune run tests/cancel.lune.luau
lune run tests/timeout.lune.luau
