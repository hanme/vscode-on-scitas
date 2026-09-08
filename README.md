# VS Code on SCITAS compute nodes

Run VS Code (terminals, Jupyter, coding agents) on a **compute node** of SCITAS
(jed/kuma/helvetios/izar) instead of the login node, as an ordinary host in VS
Code's Remote-SSH list.

**Why?** Login nodes are shared by everyone on the cluster. In August 2026 they
got swamped by VS Code servers running many parallel Claude sessions and had to
be rebooted, so VS Code, notebooks and coding agents now belong on compute
nodes ([SCITAS docs](https://scitas-doc.epfl.ch/advanced-guide/using-vscode/)).
[`bin/editor-node`](bin/editor-node) makes that painless: it submits (or reuses)
a small Slurm job and tunnels VS Code to it.

> **Please note:** every compute-node session is a Slurm job billed to the lab.
> Close VS Code windows you are not using; check for forgotten ones with
> `editor-node status` on the login node.

## Setup

You need VS Code with the *Remote - SSH* extension and a laptop terminal
(macOS, Linux or WSL; plain Windows: see [Manual setup](#manual-setup)).

**Which cluster do you have?** Check the welcome mail from SCITAS, or just try
`ssh <gaspar>@jed.hpc.epfl.ch`.

| You are a ... | Clusters | Below, `<cluster>` is |
|---|---|---|
| PhD, postdoc, staff | Jed (CPU) and Kuma (GPU), lab account | `jed` or `kuma` |
| Master/semester student, course account | Izar (GPU) and/or Helvetios, sometimes Jed's `academic` partition | `izar` or `helvetios` |

Everything below works the same on all four; the setup script writes hosts for
all of them, ignore the ones you cannot log into. `izar-node` and
`helvetios-node` have not been tested by us yet: if they work (or not) for you,
open an issue.

Where to type things: **laptop** means a terminal on your own machine, not a
VS Code window that is already connected to a cluster. **Cluster** means a login
node, reached with `ssh <cluster>` from the laptop.

**1. On the laptop.** Writes the SSH hosts, creates a key if you have none, and
offers to copy it to the clusters (compute nodes only accept key logins):

```bash
git clone https://github.com/epflneuroailab/vscode-on-scitas.git
cd vscode-on-scitas && ./laptop/setup-laptop.sh -u <gaspar>
```

**2. On each cluster.** Install the helper; typed on the laptop, the quoted part
runs on the login node (Jed and Kuma share `/home`, so once covers both; Izar
and Helvetios each have their own):

```bash
ssh <cluster> 'mkdir -p ~/.local/bin && curl -fsSL https://raw.githubusercontent.com/epflneuroailab/vscode-on-scitas/main/bin/editor-node -o ~/.local/bin/editor-node && chmod +x ~/.local/bin/editor-node'
```

**3. In VS Code on the laptop.** Command Palette → *Preferences: Open User
Settings (JSON)*, add
(with a lab account, `<labdir>` is `upschrimpf1`; `mkdir -p` the path on the cluster
first. Course accounts: skip `serverInstallPath` unless you have a `/work` or
`/scratch` directory, then use that):

```jsonc
"remote.SSH.serverInstallPath": {          // keeps the ~1 GB server off /home
  "jed":       "/work/<labdir>/<gaspar>",  // same path for jed and jed-node:
  "jed-node":  "/work/<labdir>/<gaspar>",  // they share the filesystem
  "kuma":      "/work/<labdir>/<gaspar>",
  "kuma-node": "/work/<labdir>/<gaspar>"
},
"remote.SSH.localServerDownload": "always", // compute nodes have no internet
"remote.SSH.connectTimeout": 300            // Slurm may need > 15 s
```

Then *Remote-SSH: Connect to Host...* → **`<cluster>-node`**, e.g. `jed-node`. The first
connection takes 20-60 s while Slurm allocates. `hostname` in a VS Code terminal
should print something like `jst372`, not `jed`. Optionally delete the now
unused `~/.vscode-server` on the cluster; it frees about 1 GB on `/home`.

## Hosts

| Host | Lands on | Use for |
|---|---|---|
| `jed-node`, `kuma-node`, `izar-node`, `helvetios-node` | compute node (Slurm job) | **all real work** |
| `jed`, `kuma`, `izar`, `helvetios` | login node | `git`, `squeue`, quick edits; nothing long-running |

Defaults: 4 CPUs, 16 GB, 12 h on the cluster's default partition with no GPU;
on Kuma `mig24gb` with `gpu:1`, because Kuma rejects jobs without a GPU. When the 12 h end, VS Code drops; reconnecting submits a new job
(files are fine, terminal state is gone).

**Pick the lightest option that does the job.** Quick edits, `git`, `squeue`,
small scripts: the login node (`jed`, `kuma`) is fine. CPU work and heavy agent
use: `jed-node`. Reserve `kuma-node` / `izar-node` for when you need the GPU and
a lot of agent involvement at the same time; otherwise the GPU is idling and is
billed.

**Other resources.** `editor-node` reads `EN_PART`, `EN_GRES`, `EN_TIME`, `EN_CPUS`,
`EN_MEM` when it submits (`editor-node help` lists them, `editor-node probe` shows
what you may use). Either start the job by hand (typed on the laptop, runs on
the login node), then connect as usual:

```bash
ssh kuma 'EN_PART=h100 EN_TIME=04:00:00 editor-node start'
```

or add a permanent host with its own job name to `~/.ssh/config` **on the laptop**:

```
Host kuma-h100
  HostName editor-h100
  User <gaspar>
  ProxyCommand ssh kuma "EN_NAME=editor-h100 EN_PART=h100 EN_TIME=04:00:00 ~/.local/bin/editor-node proxy"
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
```

Change a running session's resources with `editor-node stop` on the login node
(or `ssh <cluster> editor-node stop` from the laptop), then reconnect.

## Manual setup

1. On the laptop: copy [`laptop/ssh_config.template`](laptop/ssh_config.template)
   into `~/.ssh/config`, replacing `__GASPAR__`; `chmod 600` it.
2. On the laptop: `ssh-copy-id <cluster>` (Windows: paste your `.pub` into
   `~/.ssh/authorized_keys` on the cluster).
3. Steps 2 and 3 above.

The `ControlMaster` lines share one login (password + 2FA once) between VS Code,
your terminal and the `-node` tunnel. The `ServerAlive*` lines make a dead master
die in ~90 s after a login-node reboot instead of hanging every `ssh jed` for
10+ minutes.

## Troubleshooting

Log: Command Palette → *Remote-SSH: Show Log*.

| Symptom | Fix |
|---|---|
| Hangs for minutes; log has `mux_client_request_session: read from master failed` | stale socket: on the laptop `ssh -O exit jed` or `rm -f ~/.ssh/cm-*` |
| `-node`: `Permission denied (publickey)` after the job started | your key is not on the cluster: `ssh-copy-id <cluster>` from the laptop |
| `-node`: `job ... still PENDING after 90s` | queue full: `editor-node start` on the login node and wait, or another `EN_PART` |
| `~/.local/bin/editor-node: No such file or directory` | redo setup step 2 on that cluster |
| Kuma job rejected | Kuma needs a GPU: keep `gpu:1` and a GPU partition (`mig24gb`, `l40s`, `h100`) |
| terminal `hostname` says `jed` | you connected to `jed`; use `jed-node` |

**Rollback.** Cluster: `editor-node stop; rm ~/.local/bin/editor-node`. Laptop: delete
the block between the `vscode-on-scitas` markers in `~/.ssh/config` and the three
`remote.SSH.*` settings.

Written by Hannes Mehrer, September 2026.
