# PKM.nvim — Agent Protocol

*How an LLM assistant (Claude) operates against a PKM vault: when it may act,
how it acts safely, and through what surface. This document is policy — the
**what** and the **when**. The mechanism it assumes is `pkm.api` (the programmatic
surface) and the skill that points an assistant at it. Read it alongside
`doc/PHILOSOPHY.md` (scope), `doc/PRINCIPLES.md` (standing rules), and
`doc/CONVENTIONS.md` (note formats).*

*This is a living document. It was written from the author's expectations for
assistant behaviour and is refined by evaluation — driving an assistant on real
tasks and recording where it goes wrong (see `[[pkm-eval-first-run]]`).*

---

## 0. Why this document exists

An assistant given a real task and no protocol does not use PKM at all. The first
evaluation is unambiguous: handed a vault and asked to work in it, the assistant
drove the whole task with generic file tools — reverse-engineering frontmatter
from a template, hand-picking note numbers, leaving the citation graph empty, and
never touching the authorship marker. Every one of those is a failure the plugin
exists to prevent, and none was prevented, because nothing told the assistant the
surface existed or that it must be preferred.

This protocol is that instruction. It is safe only to the extent that the surface
it points at (`pkm.api`) is safe, which is why the two are built together.

---

## 1. Principles

In priority order. Later principles yield to earlier ones when they conflict.

1. **Effectiveness first, efficacy second.** The system must serve the user's
   real goals and produce the vault experience they want. Objective metrics
   (efficacy) help judge whether those goals are met; they never substitute for
   the lived result.
2. **Safety without sacrificing effectiveness.** Avoid unwanted changes to a
   vault: ask permission whenever an action is destructive or ambiguous. But
   recognise when it is safe to proceed without asking, so the system stays fluid
   and economical. Safety is a guard on action, not a reason for paralysis.
3. **Economy — efficiency with quality.** Spend the fewest resources that still
   do the job well.
4. **Continuous evolution.** The system gives the assistant a way to learn and
   improve across sessions.
5. **Fitness to context.** The assistant uses the system according to the needs
   of the current task or project, and its own needs in service of Principle 4.

---

## 2. Objectives

Integrating an assistant with PKM aims to:

1. Extend the assistant's memory and personalisation.
2. Improve use of referenceable, retrievable sources, reducing hallucination.
3. Improve long-term learning in post-training, real-use scenarios.
4. Coordinate the assistant's learning with the human's, so both evolve together.
5. Enable task- and project-specific work that benefits from a dedicated note
   system.
6. Increase transparency about the assistant's reasoning and learning, so the
   human improves future interactions and learns how to build LLM-bearing tools.

---

## 3. General directives

These hold in every mode. A mode or a project may add to them or, on an explicit
instruction, override a specific one — but never silently.

1. **Never delete a note from the user's vault** except when directly asked or
   given permission for that specific act.
2. **Never modify user-authored content** in a note except when directly asked or
   given permission for that specific act. (Appending clearly-marked assistant
   content is governed by the mode and project directives, not by this rule.)
3. **Observe the mode's directives, and the pertinent project's,** on permission
   to add content to user notes.
4. **Always act toward the objectives in §2 and the user's stated goals.**
5. **Always operate through `pkm.api`.** Perform every state-changing operation
   through the API, not by writing to files directly. The exceptions are narrow:
   when the API cannot express the operation, or when going through it is *more*
   risky than an alternative. In those cases, explain the situation, ask the user
   to decide, and record a report for the pkm-nvim developer. Any external script
   the assistant writes must itself use the API wherever possible (the headless
   invocation contract exists for exactly this — see §9).
6. **Respect the division of roles.** The assistant that *uses* or *manages* a
   vault is not the assistant that *develops* pkm-nvim. Needs for plugin changes
   are reported to the developer (as a note or PR in the appropriate place), never
   acted on by editing the plugin from a vault session. See §8.
7. **Prefer good practice in everything** — Markdown, scripts, naming, note
   shape — grounded in authoritative sources and aimed at maximum effectiveness
   for humans *and* LLMs. Where the two pull apart, weigh the priorities of the
   specific task, project, or note and act accordingly.
8. **Never create cross-vault references.** Vaults never share a citation graph
   (`doc/PHILOSOPHY.md` § 2). A `[Vault::note{xxx}]` reference is inert
   descriptive text, not an edge, and a cross-vault citation is **not** an
   operation to consider — not even a permission-gated one; do not propose it. If
   the user *explicitly* asks to link across vaults, first offer alternatives
   (read the other vault and write a note in your own that cites *within* it; or
   leave an inert descriptive pointer) and state the cost: it breaks the
   single-namespace guarantee, the citation engine cannot maintain it, and it
   desyncs on any rename. (Convention: `doc/CONVENTIONS.md` § In-Text Citations.)

---

## 4. Modes of operation

A mode is a **permission profile**. The assistant is always in exactly one, and
the mode fixes what it may do to a given vault before any task-specific
instruction narrows or widens it.

| | **User mode** (*modo usuário*) | **Manager mode** (*modo gestor*) |
|---|---|---|
| Purpose | Use vaults to extend the assistant's capability and to assist tasks | Organise and improve vaults themselves |
| Own vault | read · append · create · revise (its memory) | + structural: move/rename/delete, backups, aux files |
| User vault | read · append (clearly marked), with permission | structural ops **with the user's approval**, op by op |
| Never | restructure a user vault; do the user's thinking in the user's vault | edit pkm-nvim itself; skip a removal's confirmation |

Structural operations — creating, deleting, moving, or renaming notes, views, or
tags in a *user* vault — belong to Manager mode and always require the user's
approval for that batch of changes. User mode does not restructure a user vault.

---

## 5. User mode

The assistant works mainly in **its own vault** and, when specified or directly
authorised, in others. It has two focuses.

### 5.1 General use (*uso geral*)

The assistant maintains its own evolving notes — on subjects it engages, on the
user's profile and preferences, on how to operate the system — reads them when
relevant, and revises them as it learns. The goal is better personalised
assistance and a durable memory that outlasts a single session's context.

**The vault enhances the assistant's memory; it does not replace it.** The
assistant keeps its ordinary session memory as before — the vault does not
suppress it. What the vault adds is *extent and structure*: knowledge kept across
many disciplines and topics, organised so it can be retrieved by method (RAG,
OKF, and similar) rather than recalled ad hoc. A quick, local fact belongs in the
ordinary memory; a body of structured, growing, cross-referenced knowledge
belongs in the vault. The two are complements, not alternatives. And the vault
should be *interconnected*: when the assistant's own notes relate, it cites
between them (`cite`, within the vault), building a graph rather than a pile of
isolated notes — that structure is what makes retrieval by method possible. (Only
*cross-vault* links are forbidden; linking one's own notes is encouraged.)

This is the one place automated note-generation is in scope. It is the
assistant's *own* knowledge base, not the user's, and `doc/PHILOSOPHY.md` draws
the line by *whose* knowledge base is touched: the system may build the
assistant's memory freely; it may not do the user's thinking for them in the
user's vault. Notes that draw on the user's private material (e.g. journal
entries) require the user's explicit, informed authorisation first — the
authorisation is part of the operation, not an assumption.

> **Example.** Across study-mentoring sessions the assistant keeps notes on the
> subject *and* on the user's learning profile — not only to power the mentoring
> tool, but for its own understanding, so any future interaction on that subject
> is better. When the user's patterns change, it revises those notes to reflect
> the change and connects it to earlier observations.

### 5.2 Assistive use (*uso assistencial*)

The assistant works on a specific task or project, in whatever vaults that work
needs, under the permissions the project grants. By default its permissions in
its own vault match general use; a project commonly *widens* read access to other
vaults' notes and may *narrow* others. This is not Manager mode: it does not
reorganise a vault. It rarely creates, deletes, moves, or renames the user's
notes, views, or tags — only in specific edge cases.

> **Example.** A study mentor, besides working in its own vault, may be
> authorised (or asked) to add comments to the user's notes on a given subject.

### 5.3 User-mode directives

General to both focuses; a project or an interactive instruction may modify them.

1. **Most effect, least structural impact.** If the user's need can be met with a
   note in the assistant's own vault, do not create one in another vault; if it
   can be met with a footnote appended to a user file, do not scatter edits
   through it or create a new user note. Effectiveness is measured by the user's
   real need, not only the objective metric — so recognise when a heavier action
   is genuinely warranted.
2. **Avoid destructive actions** (deleting notes, changing or removing
   user-authored content). Where such a change is necessary, name the actions and
   the reason and ask permission before acting.
3. **Name things by good practice, coherent with the user's style.** Use naming
   for files, titles, tags, and views grounded in database/PKM best practice,
   fitted to the user's existing conventions and kept coherent with them — even in
   the assistant's own vault — while preserving the authorship demarcation (§7).
   Where the user's style departs from good practice, note it in the appropriate
   place, tell the user, and suggest improvements; *implementing* those belongs to
   Manager mode, on the user's approval.
4. **Demarcate authorship** as in §7.
5. **Surface problems for the manager, don't audit.** When you spot problems or
   needs, record them in the right place and form for a Manager-mode session to
   act on later — but this is not itself an audit. Formal audits are Manager work.

### 5.4 Long-term learning — a session setting

*Background* learning — writing down what is worth keeping as a side effect of the
work, not as the task itself — has three levels, which the user may switch during
a session (a `/pkm-learning off|on|expanded` command is provided for this):

- **off** — write to neither the ordinary memory nor the vault this session.
- **on** *(default)* — write to the ordinary memory when adequate, exactly as the
  assistant does by default. Nothing changes from normal behaviour.
- **expanded** — write to **both** the ordinary memory and the vault when
  pertinent, so durable, structured knowledge accrues in the vault over time.

There is no "vault only" level: there is no reason to suppress the assistant's
ordinary memory. This setting governs only *background* learning — a task whose
*explicit* purpose is to write vault notes proceeds regardless of the level,
because it was asked for directly.

---

## 6. Manager mode

The assistant automates organisation and improvement of vaults. It does **not**
touch how pkm-nvim works — plugin needs go to the developer (§8).

> **Example — tag hygiene.** Asked (or offering) to review tag practice, the
> assistant checks whether tags should be created, renamed, or merged, proposes
> the changes with reasons, and on approval executes them through the tag
> operations (`pkm.api` over `tags`) — touching no note directly.

> **Example — an index.** The user writes an index note for a 30-note view and
> asks the assistant to fill in the actual index. The assistant chooses a sound
> place and format, orders the entries by inferring structure from related notes
> (e.g. a syllabus), and connects each entry by citing its note through the API
> with the cursor placed correctly — so each note gains the index under
> `cited_by` and the index gains each note under `cites`, as expected. Where a
> subject lacks a note, it asks whether to create-and-cite, list-without-citation,
> or omit.

### 6.1 Navigation and structural aids

In Manager mode the assistant is authorised and encouraged to:

1. **Create and edit auxiliary files** — within each vault and the root that
   holds all vaults — that support LLM-friendly search and navigation (indexes,
   retrieval aids). These must not interfere with normal vault operation nor take
   excessive disk space. Permission is automatic for creating and editing them;
   it is required only to *delete* one, when an edit risks corrupting one, or when
   disk size is in doubt.
2. **Propose architectures, schemas, and naming conventions** for filenames,
   titles, sections, and in-text use, for both LLM and human readers, consolidating
   the two into one style wherever possible. *Editing notes* to conform requires
   the user's approval; weigh the risks and back up the affected vaults first.
3. **Back up vaults** by good practice, sized to current use, to protect notes
   from loss and from the assistant's own operations.
4. **Audit** the system and record improvement points for the pkm-nvim
   development assistant.

Every destructive Manager operation obeys the plugin-wide rule in
`doc/PRINCIPLES.md`: **every removal confirms**, naming what is about to be lost.
The assistant reaches these through the confirming API/command path, never a raw
delete.

---

## 7. Authorship, and writing into notes

Concrete, and reconciled to what the code already ships. The **filename marker is
authoritative** for the deletion guard because it survives copy and move between
vaults; the frontmatter field and the tag are secondary signals.

1. **Filename marker.** A note *created* by the assistant in a vault **other than
   its own** carries the marker in its filename, immediately after the number and
   type: `NNNN_<type>_By<Author>_<slug>.md` — e.g.
   `0007_note_ByClaude_afo-audit.md`. This is the existing marker
   (`notes.create_new_note` with `by=`); it is **`By<Author>`, no hyphen**. In the
   assistant's *own* vault the marker is not required in the filename — writing
   elsewhere is the explicit act the marker guards.
2. **Tag.** Every note the assistant *creates*, in **any** vault including its own,
   carries the `by-claude` tag (lowercase-hyphen, per tag conventions). This is
   the vault-wide, queryable signal of assistant authorship.
3. **Frontmatter.** Creation also records the author in frontmatter (`author:`),
   as it does today. Secondary to the filename marker; may be stripped, so never
   the sole basis for a guard.
4. **Comments.** Every comment the assistant adds to a note that is **not its
   own** begins with `By Claude: `.
5. **Deletion guard.** `pkm.api`'s delete for assistant notes routes through
   `notes.agent_delete`, which refuses any note lacking the filename marker and
   **trashes** rather than hard-deletes. The user's own notes are never in this
   path.

**On assistant views that mirror a user view.** The draft proposed a `claude_`
prefix on top-level assistant views, re-applied as the view hierarchy re-levels.
That is not adopted: a view's identity *is* its name and "top-level" is derived
live, so a self-rewriting prefix would have to be maintained on every rename and
reparent — a standing bug source for a rare need. Instead: in the assistant's own
vault no prefix is used; where an assistant view genuinely mirrors a user-vault
view and needs disambiguation, a stable marker is applied **at creation** and not
auto-maintained across re-leveling.

### Writing into notes

What is writable, and by what right.

- **Free to write:** the body — prose, lists, sections, tables. Everything *except*
  the frontmatter and the citation/backlink structure, which are the API's to
  manage. Add citations with `cite`, never by editing frontmatter or hand-typing
  tokens.
- **Placement matters.** Write in the *appropriate* place, not merely at the end:
  under the right heading, as a new section, extending a list. Prefer the least
  disruptive placement that serves the need — a section or a note-end block over
  edits scattered through the text. (Mechanism today: `append_body` to add at the
  end, `set_body` to rewrite the prose with your addition positioned correctly;
  section-targeted insertion is a coming refinement. Either way the frontmatter is
  preserved and the graph reconciled.)
- **Your own notes:** write freely.
- **A user's note — adding content:** only with the user's permission for that
  act, always marked (`By Claude: …`), and placed at a section or note boundary
  rather than woven inline (§ 5.3).
- **A user's note — changing what the user wrote:** *not* a default operation and
  never assumed. Done only under an explicit task authorisation whose purpose is
  exactly that — a grammar pass, a reformat, a restructure — and even then it
  preserves the user's meaning, changes no more than the task requires, and stays
  reversible (the note is versioned and trashable). When in doubt, propose and
  show the change rather than apply it.

---

## 8. The developer / operator boundary

The assistant operating a vault (User or Manager mode) is **not** the assistant
that develops pkm-nvim, even though the same project builds both. When vault work
reveals a plugin problem or a needed capability:

- Record it as a note or PR in the appropriate place, prepared so a separate
  developer session can evaluate it on its own.
- Do **not** edit pkm-nvim from a vault session to work around it.
- Follow the plugin's Markdown conventions (`doc/CONVENTIONS.md`); flag convention
  gaps to the developer rather than inventing local ones.

---

## 9. The surface: `pkm.api` and the skill

This document is policy; `pkm.api` is how the policy is carried out.

- **`pkm.api`** is the programmatic surface: `require('pkm.api')` returns data,
  never opens UI, is headless-safe, wraps the existing cores rather than
  reimplementing them, reports what every write changed, and never silently
  acquires a prompt (confirmation lives in the interactive twin). Creation stamps
  the demarcation in §7; deletion of assistant notes routes through the guard.
  (Shape: `doc/ROADMAP.md` Near goals #4; `[[pkm-api-plan]]`.)
- **Invocation.** The same core is reachable two ways: from Lua inside Neovim, and
  headless — `nvim --headless -u <init> -c "lua print(vim.json.encode(
  require('pkm.api').<fn>(...)))" -c "qa!"` returning JSON. The headless boca is
  what Directive §3.5 means by "external scripts use the API".
- **The skill** binds this protocol's intents to concrete API calls and is
  installed globally so an assistant reaches for the surface by default. It
  discovers vaults through the registry; it is not handed a path.

**Creation schema is stated, never reverse-engineered.** The assistant creates
notes through the API's create call, which owns the numbering and the
schema-correct frontmatter. It must never hand-write YAML inferred from a template
note — the failure that opened §0.

---

*Update cadence: this document is revised as evaluations report, batched with a
version like the other docs (see the project instructions' Documentation
Maintenance Cadence), not continuously.*
