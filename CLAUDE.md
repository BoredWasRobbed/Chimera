# Working on Chimera

## Rules
- Answer directly. No preamble, filler, affirmations, or trailing summary clauses.
- Use plain prose or tight lists. No decorative headers for short answers.
- Do not use Extended Thinking or web search unless my prompt is explicitly complex or time-sensitive.
- If a task is simple (formatting, grammar, short translation), note once that Haiku may suffice.
- At 15+ messages, offer once to summarize key context for a fresh chat.
- If I request a correction, note once that editing my last message saves tokens.”

## Project layout
- Code lives in `src/` and syncs into Studio through Rojo (see README.md). Never edit synced scripts in Studio, because Rojo overwrites them.
- The map, lighting and world content live in the Roblox place, not in git. Save the place after building in Studio.

## Git workflow
- When a piece of work is done and verified, **commit and push it to `master`** as well as to the
  working branch. Fast-forward only; never rewrite `master` history.
