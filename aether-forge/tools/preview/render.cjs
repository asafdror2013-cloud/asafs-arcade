// Renders baked preview sheets to PNGs with headless Chromium.
// usage: node render.cjs <frames.json> <outDir> <three.min.js> [view=front] [cols=4]
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

const [framesPath, outDir, threePath, view = 'front', cols = '4'] = process.argv.slice(2);
const here = __dirname;
const sheets = JSON.parse(fs.readFileSync(framesPath, 'utf8'));
fs.mkdirSync(outDir, { recursive: true });

(async () => {
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1400, height: 1000 }, deviceScaleFactor: 1 });
page.on('console', (m) => { if (m.type() === 'error') console.log('console:', m.text()); });
await page.route('http://preview.local/**', (route) => {
  const u = new URL(route.request().url());
  const name = u.pathname.slice(1);
  const file = name === 'frames.json' ? framesPath : name === 'three.min.js' ? threePath : path.join(here, name);
  route.fulfill({ path: file });
});
for (let i = 0; i < sheets.length; i++) {
  const v = sheets[i].title === 'Arena' ? (view === 'front' ? 'arena' : view) : view;
  await page.goto(`http://preview.local/render.html?sheet=${i}&view=${v}&cols=${cols}`);
  await page.waitForFunction(() => window.__done === true, null, { timeout: 60000 });
  const file = path.join(outDir, `${String(i).padStart(2, '0')}-${sheets[i].title.replace(/[^A-Za-z0-9]+/g, '_')}-${v}.png`);
  const canvas = await page.$('canvas');
  const box = await canvas.boundingBox();
  await page.screenshot({ path: file, clip: box, fullPage: true });
  console.log(file);
}
await browser.close();
})();
