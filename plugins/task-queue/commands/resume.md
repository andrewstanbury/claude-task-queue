---
description: Bring my task-queue back after quitting — reload this repo's open tasks
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-restore.sh"

The readout above is this repo's "put me back where I was": it listed any open tasks
that carry over from an earlier session. Act on it now — if tasks carried over,
REINSTATE them with TaskCreate (reading their full descriptions off disk first) so
the live queue reflects the earlier session before you do anything else. Then relay
in one plain sentence what came back. Note honestly: this cannot reload the previous
conversation itself — that needs relaunching with `claude --resume`.
