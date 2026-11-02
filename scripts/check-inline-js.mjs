import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const files = ['index.html', 'multibuilding.html'];
let checked = 0;

for (const file of files) {
  const html = readFileSync(file, 'utf8');
  const blocks = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)];
  for (let i = 0; i < blocks.length; i++) {
    const attrs = blocks[i][1] || '';
    const code = (blocks[i][2] || '').trim();
    if (/\bsrc\s*=/.test(attrs) || !code) continue;
    const type = (attrs.match(/\btype\s*=\s*["']([^"']+)["']/i) || [])[1];
    if (type && !/^(text|application)\/(javascript|ecmascript)$/i.test(type) && type !== 'module') continue;
    new vm.Script(code, { filename: file + ':inline-' + (i + 1) });
    checked++;
  }
}

console.log('Inline JavaScript syntax OK:', checked, 'script block(s)');
