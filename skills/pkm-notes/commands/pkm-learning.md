---
description: Set the long-term learning mode for this session (pkm-nvim)
argument-hint: off | on | expanded
---
Set your **long-term learning mode** to: **$ARGUMENTS**

This governs *background* learning — what you record as a side effect of the work,
not tasks whose explicit purpose is to write notes (those proceed regardless of
the mode, because they were asked for directly).

- **off** — do not write to your ordinary memory or the PKM vault this session.
- **on** (the default) — write to your ordinary memory when adequate, exactly as
  you do by default. Nothing changes from normal behaviour.
- **expanded** — write to **both** your ordinary memory and the PKM vault (through
  `pkm.api`, per the pkm-notes skill) when pertinent, so durable, structured
  knowledge accrues in the vault over time.

There is no "vault only" mode — there is no reason to suppress your ordinary
memory. Acknowledge the mode you are now in, and apply it for the rest of the
session unless it is changed again.
