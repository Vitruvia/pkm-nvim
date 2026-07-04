# PKM.nvim — Design Philosophy

*This document defines the principles that govern PKM.nvim's design. Read it
before proposing new features, architectural changes, or integrations. These
principles are not preferences — they are constraints. A feature that
contradicts them is out of scope, regardless of how useful it might seem in
isolation.*

---

## 1. Personal

PKM.nvim manages knowledge in a personal manner. There is no plan to add
collaboration, sharing, or multi-user features of any kind. The system is
designed for a single owner, and its design assumptions reflect that: one note
namespace, one citation graph, one author.

**Corollary:** Features that assume multiple users are out of scope. Shared
access or networked state should be only considered if shown to benefit
individual users. Backup and sync features should be unobstrusive to this rule
(e.g. local backup, private github repository, etc.).

---

## 2. Knowledge, Not Tasks

PKM.nvim manages knowledge, not tasks or projects. While it has strong support
for project notes, it does so on the assumption that project notes intersect
with or connect to the owner's knowledge. A project note is a knowledge note
that happens to be relevant to a project — it is not a task, a ticket, or a
checklist item.

This is why notes are not physically separated by project. The note graph is a
knowledge graph, and projects are lenses onto it, not partitions of it. The
flat global namespace and the project-view system are direct architectural
consequences of this principle.

**Corollary:** Task tracking, kanban-style workflows, and physical project
isolation (multi-wiki) are out of scope. Views are the correct answer to
project organisation.

---

## 3. More Than Management

The creation, review, deletion, and updating of notes should help the user
acquire, maintain, and consolidate knowledge. The system is not a passive
archive; it is an active tool for learning. Knowledge gained should be
actionable, when the user desires it — this is why project-note support exists.

Review workflows, note conversion, citation tracking, tag management, and
future review-queue support all serve this goal. When evaluating a proposed
feature, ask: does this help the user work with knowledge, or does it merely
store it?

**Corollary:** Features that actively support knowledge consolidation are
higher priority. The design should consider support for retrieval, connection,
review and other active learning methods. Of course, passive storage is part
of the process, and should be adequately supported, but always with the main
purpose in mind.

---

## 4. An Aid, Not a Replacement

The term "second brain" creates the wrong idea. PKM.nvim is meant to reinforce,
not replace, the brain's learning mechanisms. It is also meant to complement
the brain's capabilities — performing activities the human mind is poorly
suited for, such as maintaining consistent cross-references, enforcing link
integrity, and searching across hundreds of notes — without depriving the user
of the opportunity to develop their own weaknesses.

There is a productive tension between this principle and Principle 3: the
system should surface notes for review, but not perform the reading or synthesis
for the user. The human does the cognitive work; the system handles the
mechanical work.

**Corollary:** Auto-summarization, automated note generation, and features that
replace rather than support the user's thinking are out of scope, or must be
explicitly opt-in with the user fully aware of the trade-off.

---

## 5. AI Facilitation, Not Dependence

The system is a helper for the human mind, and it should integrate and
incorporate other help — including AI. However, reliance on AI would contradict
Principle 4.

This is why the system contains tools for exporting notes and uses note formats
that are easily understandable by AI. Future updates should always preserve and
improve this interoperability, as long as it does not impair human-facing
features, which are primary.

Future AI additions may be considered, as long as they do not contradict
Principles 1–4. Acceptable AI integration augments retrieval and connection
without replacing cognitive work: surfacing related notes, suggesting
citations, or checking link integrity are examples consistent with this
principle, as are AI and automation that reduces work-load in "mindless" tasks.
Automatic summarization or automatic note generation are not.

**Corollary:** No feature may introduce a hard dependency on an AI service. AI
features must be optional enhancements, never required for core functionality.

---

## 6. Format-Independent

Notes are plain Markdown files with YAML frontmatter. There is no proprietary
format, no cloud dependency, and no required external service. The system is
one tool in a portable workflow, not a walled garden.

The plain-text format is itself a design decision in service of Principle 5:
notes remain legible, portable, and processable by any tool — including AI —
regardless of what software is available. The export utility is a first-class
feature because portability is not an afterthought.

**Corollary:** Formats requiring special rendering to be legible, cloud storage
or sync, and external services required for basic operation are out of scope.

---

## 7. User-Oriented Design

Creating, fixing, and maintaining this project should always be done having
user experience in mind, including, but not limited to, the following concerns
(always consider this list incomplete and non-exhaustive):
-   note readability;
-   UI intuitivity;
-   system performance when editing, browsing, and searching notes;
-   system performance on startup;
-   simple setup, with robust defaults that cover most use cases and allow for
    any user to quickly start using the program.
-   diverse customization options, but organized in a way that makes it easy
    for the user to determine what they want to customize or not. The
    customization itself should also be easy to implement (customization should
    be desgined after defaults are defined and have been shown to be stable);

---

## How to Use This Document

When a proposed feature, change, or integration is under discussion:

1. Identify which principle(s) it touches.
2. Ask whether it serves or undermines them.
3. If it contradicts a principle, it is out of scope. Propose a version that
   does not, or record it in `ROADMAP.md` under *Postponed or Out of
   Consideration* with an explicit reference to the principle it violates.

These principles apply to all contributors: human and AI alike.
