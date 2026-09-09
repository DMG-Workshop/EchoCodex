const MODULE_ID = "echo-codex-notes";

Hooks.once("init", () => {
  console.info(`${MODULE_ID} | Echo Codex Notes initialized`);
});

Hooks.once("ready", () => {
  // Kept for anyone scripting an import (macros, other modules) — the button below is
  // now the primary path, but a world setting with an onChange hook is a stable API a
  // macro can drive without touching the DOM.
  game.settings.register(MODULE_ID, "importNote", {
    name: "Import Echo Codex note (advanced)",
    hint: "Paste JSON here to import without opening the dialog — used by macros.",
    scope: "world",
    config: true,
    type: String,
    default: "",
    onChange: (value) => {
      if (value) importEchoCodexNote(value);
    }
  });
});

// Journal Directory gets the button because every import lands there — a session's
// consolidated note is a Journal Entry, and that is where a GM already looks for one.
Hooks.on("renderJournalDirectory", (app, html) => {
  const root = html instanceof HTMLElement ? html : html[0];
  if (!root || root.querySelector(`.${MODULE_ID}-import`)) return;

  const button = document.createElement("button");
  button.type = "button";
  button.className = `${MODULE_ID}-import`;
  button.innerHTML = `<i class="fas fa-file-import"></i> Import Echo Codex`;
  button.addEventListener("click", () => new EchoCodexImportDialog().render(true));

  const header = root.querySelector(".directory-header .header-actions") ??
    root.querySelector(".directory-header");
  header?.appendChild(button);
});

/**
 * Reads an Echo Codex JSON export either from a local file (via the browser's native
 * file input — the export never needs to already live in Foundry's Data directory) or
 * pasted text, then hands it to the same import routine the world setting used.
 */
class EchoCodexImportDialog extends Dialog {
  constructor() {
    super({
      title: "Import Echo Codex note",
      content: `
        <form class="${MODULE_ID}-import-form">
          <p>Choose a JSON file exported from Echo Codex, or paste its contents below.</p>
          <div class="form-group">
            <label>File</label>
            <input type="file" name="file" accept="application/json,.json" />
          </div>
          <div class="form-group">
            <label>Or paste JSON</label>
            <textarea name="json" rows="8" placeholder="{ ... }"></textarea>
          </div>
        </form>
      `,
      buttons: {
        import: {
          icon: '<i class="fas fa-file-import"></i>',
          label: "Import",
          callback: (html) => this._import(html)
        },
        cancel: { icon: '<i class="fas fa-times"></i>', label: "Cancel" }
      },
      default: "import"
    });
  }

  async _import(html) {
    const root = html instanceof HTMLElement ? html : html[0];
    const fileInput = root.querySelector('input[name="file"]');
    const textArea = root.querySelector('textarea[name="json"]');

    const file = fileInput?.files?.[0];
    const raw = file ? await file.text() : textArea?.value ?? "";
    if (!raw.trim()) {
      ui.notifications.warn("Choose a file or paste JSON first.");
      return;
    }
    await importEchoCodexNote(raw);
  }
}

async function importEchoCodexNote(raw) {
  try {
    const document = typeof raw === "string" ? JSON.parse(raw) : raw;
    const title = document.meta?.title ?? "Echo Codex session";
    const pages = [];

    pages.push({
      name: "Summary",
      type: "text",
      text: { format: 1, content: `<h1>${escapeHtml(title)}</h1><p>${escapeHtml(document.meta?.summary ?? "")}</p>` }
    });

    if (document.sections?.length) {
      pages.push({
        name: "Notes",
        type: "text",
        text: { format: 1, content: document.sections.map(section =>
          `<h2>${escapeHtml(section.heading)}</h2><ul>${(section.bullets ?? []).map(b => `<li>${escapeHtml(b)}</li>`).join("")}</ul>`
        ).join("") }
      });
    }

    if (document.decisions?.length || document.tasks?.length || document.openQuestions?.length) {
      pages.push({
        name: "Campaign actions",
        type: "text",
        text: { format: 1, content: [
          document.decisions?.length ? `<h2>Decisions</h2><ul>${document.decisions.map(d => `<li>${escapeHtml(d.statement)}</li>`).join("")}</ul>` : "",
          document.tasks?.length ? `<h2>Action items</h2><ul>${document.tasks.map(t => `<li>${escapeHtml(t.title)}${t.dueDate ? ` — due ${escapeHtml(t.dueDate)}` : ""}</li>`).join("")}</ul>` : "",
          document.openQuestions?.length ? `<h2>Open questions</h2><ul>${document.openQuestions.map(q => `<li>${escapeHtml(q.question)}</li>`).join("")}</ul>` : ""
        ].join("") }
      });
    }

    if (document.transcript) {
      pages.push({
        name: "Transcript",
        type: "text",
        text: { format: 1, content: `<pre>${escapeHtml(document.transcript)}</pre>` }
      });
    }

    await JournalEntry.create({ name: title, pages, flags: { [MODULE_ID]: { source: "Echo Codex" } } });

    for (const participant of document.participants ?? []) {
      const name = participant.displayName ?? participant.id;
      if (!name) continue;
      const existing = game.actors?.find(actor => actor.getFlag(MODULE_ID, "participantId") === participant.id);
      if (!existing) {
        await Actor.create({
          name,
          type: "npc",
          flags: { [MODULE_ID]: { participantId: participant.id, source: "Echo Codex" } }
        });
      }
    }

    // Direct document creation, beyond the single consolidated Journal Entry above: each
    // task, decision and open question becomes its own Journal Entry, so a GM can drag
    // one onto a scene, link it with @JournalEntry[...], or mark it done by renaming it —
    // rather than being stuck inside one bullet list.
    const created = await importAsDocuments(title, document);

    ui.notifications.info(
      `Imported ${title}: 1 session note, ${created.tasks} task(s), ${created.decisions} decision(s), ${created.openQuestions} open question(s).`
    );
  } catch (error) {
    console.error(`${MODULE_ID} | Import failed`, error);
    ui.notifications.error("Echo Codex import failed. Check the JSON export format.");
  }
}

/**
 * Creates one Folder per session under "Echo Codex", with Tasks/Decisions/Open Questions
 * sub-folders holding one Journal Entry each. Every created entry is flagged with the
 * source item's stable id, so re-importing the same export updates in place instead of
 * duplicating — the same idempotency the participant-actor import already relied on.
 */
async function importAsDocuments(title, document) {
  const root = await findOrCreateFolder("Echo Codex", "JournalEntry", null);
  const session = await findOrCreateFolder(title, "JournalEntry", root.id);

  const counts = { tasks: 0, decisions: 0, openQuestions: 0 };

  if (document.tasks?.length) {
    const folder = await findOrCreateFolder("Tasks", "JournalEntry", session.id);
    for (const task of document.tasks) {
      await upsertItemEntry(folder.id, task.id, task.title, [
        task.detail ? `<p>${escapeHtml(task.detail)}</p>` : "",
        `<p><strong>Status:</strong> ${escapeHtml(task.status ?? "todo")} · <strong>Priority:</strong> ${escapeHtml(task.priority ?? "medium")}</p>`,
        task.dueDate ? `<p><strong>Due:</strong> ${escapeHtml(task.dueDate)}</p>` : "",
        (task.assigneeRaw || task.assigneeId) ? `<p><strong>Owner:</strong> ${escapeHtml(task.assigneeRaw ?? task.assigneeId)}</p>` : ""
      ].join(""), "task");
      counts.tasks++;
    }
  }

  if (document.decisions?.length) {
    const folder = await findOrCreateFolder("Decisions", "JournalEntry", session.id);
    for (const decision of document.decisions) {
      await upsertItemEntry(folder.id, decision.id, decision.statement, [
        decision.rationale ? `<p>${escapeHtml(decision.rationale)}</p>` : "",
        decision.decidedBy ? `<p><strong>Decided by:</strong> ${escapeHtml(decision.decidedBy)}</p>` : ""
      ].join(""), "decision");
      counts.decisions++;
    }
  }

  if (document.openQuestions?.length) {
    const folder = await findOrCreateFolder("Open Questions", "JournalEntry", session.id);
    for (const question of document.openQuestions) {
      await upsertItemEntry(folder.id, question.id, question.question, [
        question.raisedBy ? `<p><strong>Raised by:</strong> ${escapeHtml(question.raisedBy)}</p>` : ""
      ].join(""), "openQuestion");
      counts.openQuestions++;
    }
  }

  return counts;
}

async function findOrCreateFolder(name, type, parentId) {
  const existing = game.folders?.find(folder =>
    folder.type === type && folder.name === name && (folder.folder?.id ?? null) === parentId
  );
  if (existing) return existing;
  return Folder.create({ name, type, folder: parentId });
}

async function upsertItemEntry(folderId, itemId, name, htmlContent, kind) {
  const label = name?.trim() || `Untitled ${kind}`;
  const existing = itemId
    ? game.journal?.find(entry => entry.getFlag(MODULE_ID, "itemId") === itemId && entry.getFlag(MODULE_ID, "kind") === kind)
    : null;

  const pageData = {
    name: label,
    type: "text",
    text: { format: 1, content: htmlContent || `<p>${escapeHtml(label)}</p>` }
  };

  if (existing) {
    const firstPageId = existing.pages.contents[0]?.id;
    if (firstPageId) {
      await existing.updateEmbeddedDocuments("JournalEntryPage", [{ _id: firstPageId, ...pageData }]);
    }
    if (existing.name !== label) await existing.update({ name: label });
    return existing;
  }

  return JournalEntry.create({
    name: label,
    folder: folderId,
    pages: [pageData],
    flags: { [MODULE_ID]: { source: "Echo Codex", itemId, kind } }
  });
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
