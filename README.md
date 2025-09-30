## Overview

`qmazon` bootstraps a tmux session for `q` (or any command you pass) while managing logs under `~/.local/share/qmazon/sessions`. It keeps the main pane focused, records every run into timestamped files, and tails the latest log from a helper pane to auto-confirm prompts by pressing `t` when the configured pattern appears.

## Installation

Install the qmazon helper with a single command on macOS (requires `curl`, `tmux`, and `bash`):

```
curl -fsSL https://raw.githubusercontent.com/taituo/qmazon/master/qmazon.sh | bash
```

After installation, launch the default session with `qmazon` or pass a suffix, e.g. `qmazon foo`.
