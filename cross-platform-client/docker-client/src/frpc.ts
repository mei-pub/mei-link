import { spawn, type ChildProcess } from "node:child_process";
export class FrpcProcess {
  private child?: ChildProcess; private bin:string; constructor(bin:string) { this.bin=bin }
  running(){return !!this.child && this.child.exitCode === null}
  start(configPath:string,onLine:(line:string)=>void,onExit:(code:number)=>void){this.stop();this.child=spawn(this.bin,["-c",configPath],{stdio:["ignore","pipe","pipe"]});for(const s of [this.child.stdout,this.child.stderr])s?.on("data",d=>String(d).split(/\r?\n/).filter(Boolean).forEach(onLine));this.child.on("exit",c=>onExit(c??1));}
  stop(){if(this.running())this.child!.kill("SIGTERM");}
}
