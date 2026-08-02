export type RouteTunnel = { type: string; subdomain?: string; remoteAddr?: string; remotePort?: number };
export type RouteConfig = { subDomainHost?: string; serverAddr?: string };

export function routeText(tunnel: RouteTunnel, config: RouteConfig): string {
  if (tunnel.type === "http" || tunnel.type === "https") {
    const host = tunnel.remoteAddr || fullHost(tunnel.subdomain, config.subDomainHost);
    if (!host) return "";
    return /^https?:\/\//i.test(host) ? host : `${tunnel.type}://${host}`;
  }
  return tunnel.remoteAddr || (tunnel.remotePort ? `${config.serverAddr || ""}:${tunnel.remotePort}` : "");
}

function fullHost(subdomain = "", baseHost = ""): string {
  const value = subdomain.trim();
  if (!value) return "";
  const base = baseHost.trim();
  if (!base || value.endsWith(`.${base}`)) return value;
  return `${value}.${base}`;
}
