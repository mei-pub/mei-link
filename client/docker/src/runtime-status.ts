import type { Tunnel } from "./store.ts";

type FrpcStatus = { name: string; status?: string; remote_addr?: string; err?: string };

export function mergeRuntimeStatus(tunnels: Tunnel[], response: Record<string, FrpcStatus[]>): Tunnel[] {
  const byName = new Map<string, FrpcStatus>();
  for (const entries of Object.values(response)) for (const entry of entries || []) byName.set(entry.name, entry);
  return tunnels.map(tunnel => {
    const runtime = byName.get(tunnel.name);
    return {
      ...tunnel,
      runtimeStatus: tunnel.enabled ? runtime?.status || "new" : "closed",
      remoteAddr: runtime?.remote_addr || "",
      errorMessage: runtime?.err || "",
    };
  });
}
