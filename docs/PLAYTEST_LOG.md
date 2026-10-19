# Playtest log

Every bug, confusion or wish found while playing, in the order it was found. Each entry stays here after it's fixed, so nothing reported gets lost. Unfixed items are the to-do list; the designer's notes for prompt 2 (UI/UX) can be pulled from here.

Status: **open**, **fixed** (with the commit), or **noted for prompt N** (a design change, not a bug).

| # | Date | Found | What happened | Cause | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | 2026-10-19 | Start screen, first launch | The new-run panel sat low on the screen with the bottom (including Start) cut off, so a game couldn't be started. | The panel centred itself using its size before its contents were laid out, then grew downward. | fixed: start, end and pause/load panels now anchor to the screen centre and grow both ways |
