# ForexEA — project notes

- Remote: https://github.com/RJA9291/ForexEA.git (branch `main`).
- A Claude Code `Stop` hook (`.claude/hooks/auto-push.ps1`) commits and pushes all changes at the end of every turn. Anything in the working tree that is not in `.gitignore` gets published.
- Never write broker account numbers, passwords, or API keys into tracked files; put them in `.env` (ignored).
- Target platform: MetaTrader 5 / MQL5.
