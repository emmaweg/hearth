# hearth

Small, honest tools for running a fleet of Claude Code agents: several long-lived sessions, one per role, working side by side in tmux on one machine.

hearth starts with one tool and will grow as the fleet does.

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

## Coming next

- A small launcher and menu for starting, attaching and naming role sessions in tmux.

## License

MIT. See [LICENSE](LICENSE).
