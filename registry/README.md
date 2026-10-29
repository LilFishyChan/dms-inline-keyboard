# Registry submission

`lilfishychan-inlineKeyboard.json` is the descriptor to copy into
[AvengeMedia/dms-plugin-registry](https://github.com/AvengeMedia/dms-plugin-registry)
under `plugins/`, as `plugins/lilfishychan-inlineKeyboard.json`.

Steps:

1. Fork `AvengeMedia/dms-plugin-registry`
2. Copy this file to `plugins/lilfishychan-inlineKeyboard.json`
3. `python3 .github/generate.py --validate && python3 .github/validate_links.py`
4. Open a PR

`id` and `name` must match `plugin.json` exactly — they do, and the check above
asserts it at build time.
