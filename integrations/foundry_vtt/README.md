# Echo Codex Notes for Foundry VTT

Standalone repository: https://github.com/DMG-Workshop/EchoCodex-Foundry

This module imports an Echo Codex JSON export into Foundry. A button in the Journal
Directory header ("Import Echo Codex") opens a dialog where you either choose the
exported `.json` file directly from your computer or paste its contents — the file
never needs to already be inside Foundry's Data directory.

Each import creates:

- One consolidated Journal Entry with pages for the summary, notes, campaign actions,
  and transcript, when those fields are present.
- One Journal Entry per task, decision, and open question, organized under an
  `Echo Codex / <session title> / Tasks|Decisions|Open Questions` folder structure —
  so each item can be dragged onto a scene, linked with `@JournalEntry[...]`, or found
  on its own, instead of being stuck inside one bullet list.
- Lightweight NPC actors for participants, tagged with their Echo Codex participant id.

Re-importing the same export updates existing task/decision/question entries in place
(matched by their Echo Codex id) rather than duplicating them.

For scripting, the world setting **Import Echo Codex note (advanced)** still accepts
pasted JSON and triggers the same import — useful from a macro.

## Install during development

1. Copy this module into your Foundry `Data/modules/echo-codex-notes` directory.
2. Enable **Echo Codex Notes** in the world.
3. Open the Journal Directory and click **Import Echo Codex**.

The module is intentionally file-based and has no hosted backend or network dependency.
