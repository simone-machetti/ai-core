# AI-Core

Next-generation AI-Core architecture (clean redesign). _Empty skeleton — to be populated._

This project plugs into the repository-level EDA flow. See the [root README](../../README.md) for the `make` targets, their generic parameters, and the typical pipeline. This document covers the parts specific to `ai-core`.

The previous architecture is preserved as [`ai-core-legacy`](../ai-core-legacy/README.md).

## Quick start

```bash
source ../../sourceme.sh   # or: source sourceme.sh from the repository root

make sim PROJECT=ai-core TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<out_dir>
```

`ai-core` is selected with `PROJECT=ai-core` on every `make` command.

## Top-level modules

_None yet. Add RTL to `rtl/` and a testbench `tb/tb_<top_level>.sv` per top-level._

## RTL elaboration parameters

_None yet._

## Testbenches

_None yet._

## Experiments (automation scripts)

_None yet. Add experiment subfolders under `scripts/flow/`._
