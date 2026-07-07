import { useEffect, useState } from "react";

function currentReducedMotion(): boolean {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/** Tracks the user's prefers-reduced-motion setting, reactively. */
export function useReducedMotion(): boolean {
  const [reduced, setReduced] = useState(currentReducedMotion);

  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const handler = () => setReduced(mq.matches);
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  }, []);

  return reduced;
}
