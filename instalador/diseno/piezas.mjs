// Dibuja cada pantalla y cada pieza del instalador a las escalas de Windows usando Edge,
// y escribe sus posiciones en posiciones.iss para que el instalador las lea.
// Uso: node piezas.mjs <msedge.exe> <carpeta de salida>
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const [edge, salida] = process.argv.slice(2);
const aqui = dirname(fileURLToPath(import.meta.url));
mkdirSync(salida, { recursive: true });
const url = "file:///" + join(aqui, "index.html").replaceAll("\\", "/");
const puerto = 9341;
const navegador = spawn(edge, ["--headless=new", "--disable-gpu", "--hide-scrollbars", `--remote-debugging-port=${puerto}`,
    `--user-data-dir=${join(aqui, "perfil-edge")}`, "about:blank"], { stdio: "ignore" });

const espera = ms => new Promise(r => setTimeout(r, ms));
let objetivos;
for (let i = 0; i < 40 && !objetivos; i++) {
    await espera(250);
    try { objetivos = await (await fetch(`http://127.0.0.1:${puerto}/json`)).json(); } catch { }
}
const ws = new WebSocket(objetivos.find(t => t.type === "page").webSocketDebuggerUrl);
await new Promise(r => (ws.onopen = r));
let id = 0;
const pendientes = new Map();
ws.onmessage = e => {
    const m = JSON.parse(e.data);
    if (pendientes.has(m.id)) { pendientes.get(m.id)(m.result); pendientes.delete(m.id); }
};
const cdp = (method, params = {}) => new Promise(r => { const n = ++id; pendientes.set(n, r); ws.send(JSON.stringify({ id: n, method, params })); });
const js = async expression => (await cdp("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })).result.value;
const captura = async (nombre, r) => {
    const res = await cdp("Page.captureScreenshot", { format: "png", clip: { x: r.x, y: r.y, width: r.w, height: r.h, scale: 1 }, captureBeyondViewport: true });
    writeFileSync(join(salida, nombre + ".png"), Buffer.from(res.data, "base64"));
};
// Captura un elemento en reposo y con el raton encima
const conHover = async (nombre, selector, r, escala) => {
    await captura(`${nombre}-${escala}`, r);
    await js(`document.querySelector('${selector}').classList.add('hover')`);
    await espera(60);
    await captura(`${nombre}-hover-${escala}`, r);
    await js(`document.querySelector('${selector}').classList.remove('hover')`);
};

await cdp("Page.enable");
let posiciones;
for (const escala of [100, 125, 150, 200]) {
    await cdp("Emulation.setDeviceMetricsOverride", { width: 840, height: 1520, deviceScaleFactor: escala / 100, mobile: false });
    await cdp("Page.navigate", { url });
    await espera(900);
    await js("document.fonts.ready.then(() => true)");

    const datos = await js(`(() => {
        const caja = e => { const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height } };
        const ventanas = Object.fromEntries([...document.querySelectorAll('.ventana')].map(v => [v.id, caja(v)]));
        const piezas = {};
        for (const e of document.querySelectorAll('[data-pieza], #bienvenida .cerrar')) {
            const v = e.closest('.ventana').getBoundingClientRect();
            const r = caja(e);
            piezas[e.dataset.pieza || 'cerrar'] = { ...r, rx: r.x - v.x, ry: r.y - v.y };
        }
        return { ventanas, piezas };
    })()`);
    const p = datos.piezas;
    posiciones ??= p;

    await conHover("instalar", "[data-pieza=instalar]", p.instalar, escala);
    await conHover("cancelar", "[data-pieza=cancelar]", p.cancelar, escala);
    await conHover("terminar", "[data-pieza=terminar]", p.terminar, escala);
    await conHover("cerrar", "#bienvenida .cerrar", p.cerrar, escala);

    await captura(`casilla-si-${escala}`, p.casilla);
    await js("document.querySelector('.casilla').classList.add('no')");
    await espera(60);
    await captura(`casilla-no-${escala}`, p.casilla);

    // La linea de tiempo entera; el instalador muestra solo la parte que lleve
    await js("document.querySelector('.avance').style.width = '100%'");
    await espera(60);
    await captura(`avance-${escala}`, p.pista);

    await js("document.body.classList.add('fondo')");
    await espera(80);
    for (const [nombre, v] of Object.entries(datos.ventanas)) await captura(`fondo-${nombre}-${escala}`, v);
}

const lineas = ["; Generado por diseno/piezas.mjs: posiciones de las piezas en pixeles a escala 100 %"];
for (const [nombre, r] of Object.entries(posiciones)) {
    const n = nombre.replace(/-(\w)/g, (_, l) => l.toUpperCase()).replace(/^\w/, l => l.toUpperCase());
    lineas.push(`#define ${n}X ${Math.round(r.rx)}`, `#define ${n}Y ${Math.round(r.ry)}`, `#define ${n}W ${Math.round(r.w)}`, `#define ${n}H ${Math.round(r.h)}`);
}
writeFileSync(join(salida, "posiciones.iss"), lineas.join("\r\n") + "\r\n");
ws.close();
navegador.kill();
console.log("piezas:", Object.keys(posiciones).join(", "));
