---
name: sync-dev
description: After EVERY file edit in this project, run rsync to deploy the changed files to the PZ mods directory. Use this for ANY edit — never skip the sync step.
---

# Auto-sync changed files to PZ mods directory

Project Zomboid loads mods from `~/Zomboid/mods/`, NOT from the git repository.

After EVERY edit, rsync the affected mod folder(s) — there are two mods:

```bash
rsync -av --delete /home/top/Projects/Games/ProjectZomboid/DynamicEvents/DynamicEventsFramework/ ~/Zomboid/mods/DynamicEventsFramework/
rsync -av --delete /home/top/Projects/Games/ProjectZomboid/DynamicEvents/DynamicEventsContent/ ~/Zomboid/mods/DynamicEventsContent/
```

This is mandatory. Do not ask the user for permission or remind them — just run it after every edit batch.
