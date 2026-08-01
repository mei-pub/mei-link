import { writeFile } from "node:fs/promises"; import { join } from "node:path";
import { DataStore, type Tunnel } from "./store.ts"; import { generateFrpcToml, type ServerConfig } from "./config.ts"; import { FrpcProcess } from "./frpc.ts";
export class TunnelManager { private frpc:FrpcProcess; private events:any[]=[]; private config:ServerConfig|null=null; private current:Tunnel[]=[]; private store:DataStore;
 constructor(store:DataStore,frpcBin:string){this.store=store;this.frpc=new FrpcProcess(frpcBin)} async load(){await this.store.init();this.config=await this.store.config();this.current=await this.store.tunnels()} status(){return {configured:!!this.config,running:this.frpc.running(),connected:this.frpc.running(),pid:0}} logs(){return this.events} tunnels(){return this.current}
 private log(message:string,level="info"){this.events.unshift({timestamp:new Date().toISOString(),message,level});this.events=this.events.slice(0,100)}
 async saveConfig(c:ServerConfig){this.config=c;await this.store.saveConfig(c);await writeFile(join(this.store.dir,"frpc.toml"),generateFrpcToml(c,this.store.dir),{mode:0o600});this.log("服务器配置已保存")}
 async start(){if(!this.config)throw new Error("未配置服务器");const file=join(this.store.dir,"frpc.toml");this.log("正在启动隧道管理器...");this.frpc.start(file,l=>this.log(`frpc: ${l}`,"info"),c=>this.log(`frpc 进程已退出，状态码: ${c}`,"error"))} stop(){this.frpc.stop();this.log("隧道管理器已停止")} async saveTunnels(t:Tunnel[]){this.current=t;await this.store.saveTunnels(t)}
}
