/*
 * Minimal Keep-a-Changelog parser. Reads the repo's CHANGELOG.md (imported as
 * raw text) and extracts releases → change sections → bullet items, so the
 * /changelog page stays in sync with the file automatically.
 *
 * Only the meaningful change sections are kept; boilerplate subsections
 * (Requirements / Install / Known limitations) and code blocks are skipped.
 */

export interface ChangeItem {
  lead?: string;
  text: string;
}

export interface ChangeSection {
  name: string; // Added | Fixed | Changed | Removed | Security | Deprecated
  items: ChangeItem[];
}

export interface Release {
  version: string;
  date: string;
  intro?: string;
  sections: ChangeSection[];
}

const KEEP = new Set(["Added", "Fixed", "Changed", "Removed", "Security", "Deprecated"]);

function parseBullet(raw: string): ChangeItem {
  // "- **Title** — rest"  or  "- plain text"
  const bold = raw.match(/^\*\*(.+?)\*\*\s*[—–-]?\s*(.*)$/);
  if (bold) {
    return { lead: bold[1].trim(), text: bold[2].trim() };
  }
  return { text: raw.replace(/\*\*/g, "").trim() };
}

export function parseChangelog(md: string): Release[] {
  const lines = md.split("\n");
  const releases: Release[] = [];
  let cur: Release | null = null;
  let section: ChangeSection | null = null;
  let inCode = false;

  for (const line of lines) {
    if (line.trim().startsWith("```")) {
      inCode = !inCode;
      continue;
    }
    if (inCode) continue;

    // ## [0.1.0] — 2026-06-17
    const ver = line.match(/^##\s+\[([^\]]+)\]\s*[—–-]?\s*(.*)$/);
    if (ver) {
      cur = { version: ver[1].trim(), date: ver[2].trim(), sections: [] };
      releases.push(cur);
      section = null;
      continue;
    }
    if (!cur) continue;

    // ### Added
    const sec = line.match(/^###\s+(.+?)\s*$/);
    if (sec) {
      const name = sec[1].trim();
      if (KEEP.has(name)) {
        section = { name, items: [] };
        cur.sections.push(section);
      } else {
        section = null; // skip Requirements / Install / Known limitations
      }
      continue;
    }

    // - bullet
    const bullet = line.match(/^\s*-\s+(.*)$/);
    if (bullet && section) {
      section.items.push(parseBullet(bullet[1]));
      continue;
    }

    // loose intro paragraph right under the version header
    const text = line.trim();
    if (text && !section && !cur.intro && !text.startsWith("[") && !text.startsWith("#")) {
      cur.intro = text;
    }
  }

  return releases.filter((r) => r.sections.length > 0 || r.intro);
}
