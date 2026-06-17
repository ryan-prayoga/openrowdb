import { useState } from "react";
import { links } from "../../data/platforms";

/** Glass terminal box with the install one-liner + copy button. */
export function InstallCommand({ label }: { label?: string }) {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(links.install);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      /* clipboard blocked — no-op */
    }
  };

  return (
    <div className="w-full">
      {label && <div className="mb-2 text-xs text-faint">{label}</div>}
      <div className="glass flex items-stretch gap-2 rounded-xl p-2">
        <code className="no-scrollbar flex flex-1 items-center gap-2 overflow-x-auto rounded-lg bg-black/40 px-3 py-2.5 font-mono text-[12.5px] text-fg">
          <span className="select-none text-emerald">$</span>
          <span className="whitespace-nowrap">
            <span className="text-cyan">curl</span> -fsSL{" "}
            <span className="text-accent">https://openrowdb.ryanprayoga.dev/install.sh</span> |{" "}
            <span className="text-cyan">bash</span>
          </span>
        </code>
        <button
          type="button"
          onClick={copy}
          aria-label="Copy install command"
          className="shrink-0 rounded-lg border border-hair bg-glass px-3.5 font-mono text-xs text-fg transition-colors hover:border-accent"
        >
          {copied ? "✓ Copied" : "Copy"}
        </button>
      </div>
    </div>
  );
}
