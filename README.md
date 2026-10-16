# hearth

Small, honest tools for running a fleet of Claude Code agents: several long-lived sessions, one per role, working side by side in tmux on one machine.

hearth has two tools so far, and will grow as the fleet does:

- **hearth**, a launcher that gives each project its own tmux session and a menu to move between them.
- **embers**, a Stop hook that keeps an idle session's prompt cache warm.

There's also a CloudFormation template for a cloud server that runs them, if you'd rather not keep a machine on at home.

## hearth: one tmux session per project

<img src="docs/menu.png" alt="The hearth menu: projects grouped by category, with the running ones marked by agent" width="760">

Pick a project and hearth attaches to its session, starting it first if it isn't running. A new session resumes the agent's last conversation in that directory, or starts a fresh one, and leaves you at a shell when the agent exits. Run inside tmux, hearth switches to the session instead of nesting.

```bash
hearth                         # the menu
hearth start api               # start or attach, from a script or another pane
hearth start api codex         # the same project with Codex, as session "api-codex"
hearth list                    # every project and what's running
hearth add api ~/src/api work  # add a project, optionally under a category
hearth kill api                # end the project's sessions
```

### Install

```bash
mkdir -p ~/.local/bin
cp bin/hearth ~/.local/bin/hearth
chmod +x ~/.local/bin/hearth
```

Make sure `~/.local/bin` is on your `PATH`.

### The registry

Projects live in `~/.config/hearth/projects.conf`, one per line, with fields separated by colons:

```
name:directory:prompt:category:agent:options
```

Only the name and directory are required, and `hearth add` writes those for you. Edit the file by hand for the rest:

| Field | Meaning |
| --- | --- |
| `prompt` | sent to the agent when the session starts |
| `category` | groups projects in the menu and the list, in the order they first appear |
| `agent` | `claude` or `codex` pins the entry to one agent; empty follows the menu's toggle |
| `options` | for Claude, a comma list: `agent=<name>` loads `.claude/agents/<name>.md`, `session=<uuid>` pins the conversation |

Several roles can share one directory. `claude --continue` resumes whichever conversation in a directory ran last, so an entry with `agent=` gets its own conversation instead: hearth derives a stable session id from the entry's name, or uses the `session=` you give it.

```
# a reviewer and a writer working in the same repo
reviewer:~/src/api:Review the open branches.:work::agent=reviewer
writer:~/src/api::work::agent=writer
```

Lines starting with `#` are comments. Because fields are colon-separated, a directory can't contain `:`.

### Settings

| Variable | Default | Meaning |
| --- | --- | --- |
| `HEARTH_PROJECTS` | `~/.config/hearth/projects.conf` | the registry file |
| `HEARTH_AGENT` | `claude` | the agent the menu starts with |
| `HEARTH_CLAUDE_ARGS` | empty | extra arguments for every Claude session |
| `HEARTH_CODEX_ARGS` | empty | extra arguments for every Codex session |

For example, `HEARTH_CLAUDE_ARGS="--model opus"`. hearth never adds permission flags on its own, so sessions ask for permission the way Claude Code normally does unless you pass one here.

### Requirements

python3 (3.9 or later, standard library only), tmux, and `claude` or `codex` on your `PATH`.

## embers: keep an idle session's prompt cache warm

Claude Code caches a session's prompt for a limited time, an hour on many plans. A role session that sits idle for longer pays to rebuild that cache the next time someone wakes it. **embers** is a Stop hook that keeps the cache warm while a session waits:

1. When a turn ends, embers starts one detached timer for that session.
2. If the session's tmux pane stays quiet for 58 minutes, the timer types a one-line ping into the pane ("reply with just ok").
3. Answering the ping reads the cache inside its lifetime, so it stays warm.
4. A turn the ping started counts toward a cap (8 by default). Any real turn resets the count, so a session left idle overnight goes cold after about 8 hours instead of being pinged forever.

It only acts on sessions running in **tmux**. Elsewhere it does nothing.

### Is it worth it?

On API pricing, reading a cached prompt costs about a tenth of the base input price, and writing a one-hour cache costs about twice it. One cold restart therefore costs roughly as much as twenty pings. Keeping a session warm pays off when you'll use it again within a few hours, which is why the cap exists. Your plan's limits may weigh cache reads differently, so watch your usage after you install it, and lower `EMBERS_CAP` if it costs more than it saves.

### Install

```bash
mkdir -p ~/.claude/hooks
cp hooks/embers.sh ~/.claude/hooks/embers.sh
chmod +x ~/.claude/hooks/embers.sh
```

Then add the Stop hook from `examples/settings.json` to the settings of the project or projects whose sessions you want kept warm (for example `.claude/settings.local.json`). Sessions already running may need a restart to pick up a new hook.

### Settings

| Variable | Default | Meaning |
| --- | --- | --- |
| `EMBERS_DELAY` | `3480` | seconds of quiet before a ping |
| `EMBERS_CAP` | `8` | pings in a row before giving up |
| `EMBERS_PING` | `keep-warm ping …` | the text typed into the pane |
| `EMBERS_STATE` | `~/.claude/state/embers` | where per-session state lives |

### How it decides a session is idle

tmux records when a window last changed. A busy session redraws its pane, so embers only pings a pane that has been quiet for the whole delay. A newer turn replaces the pending timer, so each session has at most one ping waiting.

### Requirements

bash, tmux, python3 (only to read the hook's JSON input), and Claude Code with hooks enabled.

## A server in the cloud

`cloud/agent-server.yaml` is a CloudFormation template for an always-on machine to run the fleet on, as an alternative to keeping a spare computer at home. It isn't minimal, but it's everything an agent server needs:

- one EC2 instance (Amazon Linux 2023, `t4g.small` by default) in its own VPC, with an encrypted disk
- an `agent` user with tmux, git, Claude Code, hearth and embers installed and the embers hook turned on, plus the Codex CLI if you set `InstallCodex=true`
- access through SSM Session Manager, with an SSH port only if you give it an address range
- a GitHub SSH key, either from Secrets Manager or generated on first boot and printed in the setup log
- optionally: a Route 53 DNS name, a CloudWatch dashboard for CPU, memory, disk and network, and daily disk snapshots kept for a week

The instance role can use Session Manager and send metrics, and nothing else. If your agents need to work with AWS, attach a policy you've scoped to what they do.

### Deploy

```bash
aws cloudformation create-stack --stack-name agents \
  --template-body file://cloud/agent-server.yaml \
  --capabilities CAPABILITY_IAM \
  --parameters ParameterKey=SSHCidr,ParameterValue=203.0.113.7/32 \
               ParameterKey=KeyName,ParameterValue=my-key
aws cloudformation wait stack-create-complete --stack-name agents
aws cloudformation describe-stacks --stack-name agents --query 'Stacks[0].Outputs'
```

Leave out `SSHCidr` and `KeyName` to connect only with `aws ssm start-session` (this needs the Session Manager plugin for the AWS CLI). Setup takes about five minutes, and the stack fails right away if it goes wrong. Its log is at `/var/log/hearth-setup.log`.

Once you're on the server as the agent user, sign in to Claude Code once by running `claude`, then add projects with `hearth add` as usual. Sessions keep running when you disconnect.

### What it costs

These are rough on-demand prices in a US region for a server that runs all month. Check current AWS pricing for yours.

| | per month |
| --- | --- |
| `t4g.small` instance (2 vCPU, 2 GB) | about $12 |
| 20 GB disk | about $1.60 |
| public IPv4 address | about $3.60 |
| snapshots, dashboard and memory/disk metrics | about $1 to $4 |
| **total** | **about $18 to $22** |

At that rate a small server costs about as much as a new desktop Mac mini after two to three years, and needs no hardware, power or home network. Each Claude Code session uses a few hundred MB of memory, so for more than three or four agents at once, use `t4g.medium` (4 GB, about $25 a month for the instance). Stopping the instance stops the instance charge, but the public IP changes on the next start. Model usage is billed separately by your Claude plan or API key either way.

## License

MIT. See [LICENSE](LICENSE).
