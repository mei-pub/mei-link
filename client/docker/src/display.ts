export type RouteTunnel = { type: string; subdomain?: string; customDomains?: string[]; remoteAddr?: string; remotePort?: number };
export type RouteConfig = { subDomainHost?: string; serverAddr?: string; vhostHTTPPort?: number; vhostHTTPSPort?: number };

export function routeText(tunnel: RouteTunnel, config: RouteConfig): string {
  if (tunnel.type === "http" || tunnel.type === "https") {
    const host = tunnel.remoteAddr || fullHost(tunnel.subdomain, config.subDomainHost) || tunnel.customDomains?.[0]?.trim();
    if (!host) return "";
    return routeURL(tunnel.type, host, tunnel.type === "http" ? config.vhostHTTPPort ?? 8080 : config.vhostHTTPSPort ?? 8443);
  }
  return tunnel.remoteAddr || (tunnel.remotePort ? `${config.serverAddr || ""}:${tunnel.remotePort}` : "");
}

function routeURL(type: "http" | "https", host: string, port: number): string {
  if (/^https?:\/\//i.test(host)) return host;
  const value = new URL(`${type}://${host}`);
  const standardPort = type === "http" ? 80 : 443;
  if (!value.port && port !== standardPort) value.port = String(port);
  return `${type}://${value.host}`;
}

function fullHost(subdomain = "", baseHost = ""): string {
  const value = subdomain.trim();
  if (!value) return "";
  const base = baseHost.trim();
  if (!base || value.endsWith(`.${base}`)) return value;
  return `${value}.${base}`;
}
