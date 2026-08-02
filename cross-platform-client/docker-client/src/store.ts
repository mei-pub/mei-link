import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { ServerConfig } from "./config.ts";
export type Tunnel = { id:string; name:string; type:"http"|"https"|"tcp"|"udp"; localIP:string; localPort:number; subdomain?:string; remotePort?:number; enabled:boolean; status?:string; runtimeStatus?:string; remoteAddr?:string; errorMessage?:string };
export class DataStore { readonly dir:string; constructor(dir:string) { this.dir=dir } private p(n:string){return join(this.dir,n)}
 async init(){await mkdir(this.dir,{recursive:true})} async read<T>(name:string,fallback:T):Promise<T>{try{return JSON.parse(await readFile(this.p(name),"utf8"))}catch{return fallback}}
 async write(name:string,value:unknown){const tmp=this.p(`.${name}.tmp`);await writeFile(tmp,JSON.stringify(value,null,2),{mode:0o600});await rename(tmp,this.p(name))}
 config(){return this.read<ServerConfig|null>("config.json",null)} saveConfig(v:ServerConfig){return this.write("config.json",v)} tunnels(){return this.read<Tunnel[]>("tunnels.json",[])} saveTunnels(v:Tunnel[]){return this.write("tunnels.json",v)}
}
