import type { Tunnel } from "./store.ts";

type ProxyDefinition = Record<string, unknown>;

export function toProxyDefinition(tunnel: Tunnel, baseHost = ""): ProxyDefinition {
  const subdomain = normalizedSubdomain(tunnel.subdomain, baseHost);
  if (tunnel.type === "tcp" || tunnel.type === "udp") {
    return {
      name: tunnel.name,
      type: tunnel.type,
      [tunnel.type]: {
        localIP: tunnel.localIP,
        localPort: tunnel.localPort,
        remotePort: tunnel.remotePort,
      },
    };
  }
  const http = {
    localIP: tunnel.localIP,
    localPort: tunnel.localPort,
    ...(subdomain ? { subdomain } : {}),
    ...(tunnel.customDomains?.length ? { customDomains: tunnel.customDomains } : {}),
  };
  return {
    name: tunnel.name,
    type: tunnel.type,
    [tunnel.type]: tunnel.type === "http" ? {
      ...http, locations: ["/"],
      ...(tunnel.httpUser ? { httpUser: tunnel.httpUser } : {}),
      ...(tunnel.httpPassword ? { httpPassword: tunnel.httpPassword } : {}),
      ...(tunnel.hostHeaderRewrite ? { hostHeaderRewrite: tunnel.hostHeaderRewrite } : {}),
    } : http,
  };
}

function normalizedSubdomain(value = "", baseHost: string): string {
  const suffix = baseHost.trim() ? `.${baseHost.trim()}` : "";
  return value.trim().endsWith(suffix) ? value.trim().slice(0, -suffix.length) : value.trim();
}
