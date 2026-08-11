---
name: sync-dev
description: After EVERY file edit in this project, run rsync to deploy the changed files to the PZ mods directory. Use this for ANY edit — never skip the sync step.
---

# Auto-sync changed files to PZ mods directory

Project Zomboid loads mods from `~/Zomboid/mods/DynamicEvents/`, NOT from the git repository.

After EVERY edit to any file under `42/`, immediately run:

```bash
rsync -av --delete /home/top/Projects/Games/ProjectZomboid/DynamicEvents/42/ ~/Zomboid/mods/DynamicEvents/42/
```

This is mandatory. Do not ask the user for permission or remind them — just run it after every edit batch.
