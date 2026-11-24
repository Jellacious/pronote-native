import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const distDir = path.join(__dirname, "node_modules", "pawnote", "dist");

const target =
  'Se=(e,s,t)=>{const i=n.util.createBuffer(e.information.aesIV);try{const e=n.util.decodeUtf8(se.decrypt(s.challenge,t,i)),a=new Array(e.length);for(let s=0;s<e.length;s+=1)s%2==0&&a.push(e.charAt(s));const r=n.util.encodeUtf8(a.join(""));return se.encrypt(r,t,i)}catch{throw new c}}';

const replacement =
  'Se=(e,s,t)=>{const i=n.util.createBuffer(e.information.aesIV);try{if(e.instance?.version?.[0]>=2026){return se.encrypt(n.util.encodeUtf8(s.challenge),t,i)}const o=n.util.decodeUtf8(se.decrypt(s.challenge,t,i)),a=new Array(o.length);for(let s=0;s<o.length;s+=1)s%2==0&&a.push(o.charAt(s));const r=n.util.encodeUtf8(a.join(""));return se.encrypt(r,t,i)}catch{throw new c}}';

const mjsPath = path.join(distDir, "index.mjs");
const content = fs.readFileSync(mjsPath, "utf8");

if (content.includes("e.instance?.version?.[0]>=2026")) {
  console.log("pawnote/dist/index.mjs déjà patché pour PRONOTE 2026.");
  process.exit(0);
}

if (!content.includes(target)) {
  console.error("Erreur: motif Se= introuvable dans pawnote/dist/index.mjs");
  process.exit(1);
}

fs.writeFileSync(mjsPath, content.replace(target, replacement), "utf8");
console.log("Patch PRONOTE 2026 appliqué sur pawnote/dist/index.mjs.");
