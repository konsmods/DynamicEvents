---
name: sync-dev
description: After EVERY file edit in this project, commit + push the repo, then git pull in ~/Zomboid/mods/ to deploy to PZ. Use this for ANY edit — never skip the deploy step.
---

# Deploy via git

Project Zomboid loads mods from `~/Zomboid/mods/`, which is a git clone of this
repo. The Workshop staging folders symlink to it.

After EVERY edit:

```bash
git push
git -C ~/Zomboid/mods pull
```

This updates both mods for testing (and the Workshop via symlinks).

Do not ask the user for permission or remind them — just run it after every edit batch.
