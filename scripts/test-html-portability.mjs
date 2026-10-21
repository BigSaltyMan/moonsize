// Real CLI generation in unrelated cwd; optional fresh offline Chromium + A4 PDF.
// Test dependencies only: npm ci; npx playwright install chromium.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import os from 'node:os';
import {htmlDataFixture} from './html-data-fixture.mjs';
const dataOnly = process.argv.includes('--data-only');
const root = fileURLToPath(new URL('../', import.meta.url));
const cli = path.resolve(process.argv[2] || '_build/native/release/build/cmd/main/main.exe');
const out = path.join(root, '_build/html-delivery-verification');
fs.mkdirSync(out, {recursive:true});
const work = fs.mkdtempSync(path.join(out, 'run-'));
const cwd = path.join(work, 'source cwd 中文');
fs.mkdirSync(cwd);
const hash = b => crypto.createHash('sha256').update(b).digest('hex');
// PDF fonts can split a single word into items (Linux: "Whole-", "fi", "le
// gzip"). Joining items inserts spaces that were never painted. Compare all
// non-whitespace characters, retaining spelling, punctuation, numbers and units.
const pdfTextKey = text => text.replace(/\s/g,'');
assert.equal(pdfTextKey(['Whole-','fi','le gzip'].join(' ')),pdfTextKey('Whole-file gzip'));
assert.notEqual(pdfTextKey('Whole-file zip'),pdfTextKey('Whole-file gzip'));
assert.notEqual(pdfTextKey('5,270 B'),pdfTextKey('5,207 B'));
const input = path.join(root, 'examples/fib.wasm');
const expectedInput = '0e6f10e56434b67adb162cdb56a46553ef38b8de1abd0d0deb1fe56d7173d10c';
assert.equal(hash(fs.readFileSync(input)), expectedInput);
let cases = 0;
const generate = (file, name, workingDirectory=cwd, withData=false) => {
  const target = path.join(work, name+'.html');
  const result = spawnSync(cli, [file, '--html', target, ...(withData?['--data-segments']:[])], {cwd:workingDirectory,encoding:'utf8',timeout:15000});
  assert.ifError(result.error);assert.equal(result.status,0,result.stdout+result.stderr);cases++;
  assert(!result.stdout.includes('CDN'));
  const html = fs.readFileSync(target,'utf8');
  const staticDocument=html.replace(/<script>[\s\S]*?<\/script>/g,'');
  assert(!/<script\s+src=|<link\b|<img\s+src=|@import\b/i.test(staticDocument));
  const library = [...html.matchAll(/<script>\n([\s\S]*?)\n<\/script>/g)][0][1];
  assert.equal(hash(Buffer.from(library.replaceAll('<\\/script','</script').replaceAll('<\\/SCRIPT','</SCRIPT'))),
    'bf4a223524e40b77c304bec67e1222cf551f14880cf42c69dc046558e11c07b1');
  const data = JSON.parse(html.match(/const DATA = (.*);\r?\n/)[1]);
  assert.equal(data.fileSize,fs.statSync(file).size);assert(html.includes('Licensed to the Apache Software Foundation'));
  return {target,html,data,sha256:hash(Buffer.from(html))};
};
let example,stress,copy;
if (!dataOnly) {
example = generate(input,'example');
assert.deepEqual([example.data.fileSize,example.data.codeSize,example.data.gzipSize,example.data.deadSize],[10675,5166,5207,0]);
// Neither local nor parent "assets" may supply executable code to a report.
for (const parent of [cwd,work]) {fs.mkdirSync(path.join(parent,'assets'));fs.writeFileSync(path.join(parent,'assets/echarts.min.js'),'throw Error("cwd resource used");');}
const contaminated = generate(input,'contaminated');
assert.equal(contaminated.html,example.html);
const cat = (...xs) => Buffer.concat(xs.map(x=>Buffer.from(x)));
const leb = n => {const a=[];do{a.push((n&127)|(n>127?128:0));n>>>=7;}while(n);return Buffer.from(a);};
const str = s => cat(leb(Buffer.byteLength(s)),Buffer.from(s));
const section = (id,p) => cat([id],leb(p.length),p);
const longName = 'namespace/'+ 'very_long_function_name_'.repeat(14) + '<&"\n</script>';
const names = [longName,'same','same'];
const bodies = [Buffer.from([0,65,0,17,0,0,11]),cat([0],Buffer.alloc(25,1),[11]),Buffer.from([0,11])];
const fixture = cat(Buffer.from('0061736d01000000','hex'),section(1,[1,96,0,0]),section(3,[3,0,0,0]),
  section(4,[1,112,0,1]),section(7,cat([1],str('run'),[0,0])),
  section(10,cat([3],...bodies.map(b=>cat(leb(b.length),b)))),
  section(0,cat(str('name'),section(1,cat([3],...names.map((n,i)=>cat(leb(i),str(n))))))));
assert(WebAssembly.validate(fixture));
const stressInput = path.join(cwd,'long name & warning.wasm');fs.writeFileSync(stressInput,fixture);
stress = generate(stressInput,'long-name-warning');assert.equal(stress.data.graph_complete,false);
const copied = path.join(work,'moved report 中文 with spaces');fs.mkdirSync(copied);
copy = path.join(copied,'report.html');fs.copyFileSync(example.target,copy);
assert.equal(hash(fs.readFileSync(copy)),example.sha256);assert.deepEqual(fs.readdirSync(copied),['report.html']);
}
const dataBytes=htmlDataFixture();assert(WebAssembly.validate(dataBytes));
const dataInput=path.join(cwd,'data entries.wasm');fs.writeFileSync(dataInput,dataBytes);
const dataArtifact=generate(dataInput,'data-entries',cwd,true);
assert.equal(dataArtifact.data.dataSegments.entries.length,45);
const dataCopyFolder=path.join(work,'data report copy 中文');fs.mkdirSync(dataCopyFolder);
const dataCopy=path.join(dataCopyFolder,'report.html');fs.copyFileSync(dataArtifact.target,dataCopy);
assert.equal(hash(fs.readFileSync(dataCopy)),dataArtifact.sha256);
assert.deepEqual(fs.readdirSync(dataCopyFolder),['report.html']);
const primary=example??dataArtifact;
const evidence = {platform:process.platform,os_release:os.release(),arch:process.arch,node:process.version,
  git_head:spawnSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).stdout.trim(),
  source_dirty:spawnSync('git',['diff','--quiet'],{cwd:root}).status!==0,
  cli:{sha256:hash(fs.readFileSync(cli)),bytes:fs.statSync(cli).size},input:{path:dataOnly?dataInput:input,sha256:dataOnly?hash(dataBytes):expectedInput},
  command:[cli,dataOnly?dataInput:input,'--html',primary.target,...(dataOnly?['--data-segments']:[])],cwd,report:{original:primary.target,copy:dataOnly?dataCopy:copy,sha256:primary.sha256},
  data_only:dataOnly,data_input:{path:dataInput,sha256:hash(dataBytes)},
  cli_cases:cases,cwd_generation:'passed',cwd_asset_override:dataOnly?'not tested in targeted data run':'ignored',copy_identical:true,
  browser:'not-run (pass --browser)',verification_directory:work};
fs.writeFileSync(path.join(work,'evidence.json'),JSON.stringify(evidence,null,2)+'\n');

if (process.argv.includes('--browser')) {
  const {chromium} = await import('playwright');
  const {getDocument,OPS} = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const pdfRenderer = process.env.MOONSIZE_PDFTOPPM || 'pdftoppm';
  const rendererVersion=spawnSync(pdfRenderer,['-v'],{encoding:'utf8'});
  assert.ifError(rendererVersion.error);assert.equal(rendererVersion.status,0);
  evidence.pdf_renderer=(rendererVersion.stdout+rendererVersion.stderr).trim();
  // AGENTS.md: use the development HTTP surface, never file://.
  const origin = 'http://127.0.0.1:5173';
  const check = await fetch(origin);assert.equal(check.status,200,'Start npm run dev before browser acceptance.');
  const browser = await chromium.launch({headless:true,executablePath:process.env.MOONSIZE_BROWSER_EXECUTABLE || undefined});
  evidence.browser = browser.version();evidence.playwright = JSON.parse(fs.readFileSync(path.join(root,'node_modules/playwright/package.json'))).version;
  evidence.browser_cases = [];
  try {
    // Load the original in a separate context, then CLOSE it before offline copy.
    const originalContext = await browser.newContext({serviceWorkers:'block'});
    const originalPage = await originalContext.newPage();
    // Open the required development entry before browser delivery assertions.
    await originalPage.goto(origin+'/');
    await originalPage.waitForFunction(()=>document.querySelectorAll('canvas').length===4);
    const originalUrl = origin+'/delivery-original.html';
    await originalContext.route(originalUrl,r=>r.fulfill({contentType:'text/html; charset=utf-8',body:fs.readFileSync(primary.target)}));
    await originalPage.goto(originalUrl);await originalPage.waitForFunction(()=>document.querySelectorAll('canvas').length===4);
    await originalPage.close();await originalContext.close();
    for (const [name,artifact,file] of [...(dataOnly?[]:[['example',example,copy],['long-name-warning',stress,stress.target]]),['data-entries',dataArtifact,dataCopy]]) {
      // A NEW context, offline from birth, with no service worker or warmed cache.
      // Only its main HTML response is fulfilled from the copied local bytes.
      // Every subresource and explicit control probe stays subject to offline mode.
      const context = await browser.newContext({offline:true,serviceWorkers:'block',viewport:{width:1440,height:1000}});
      const url = name==='data-entries'?origin+'/':origin+'/moved%20report%20%E4%B8%AD%E6%96%87/'+name+'.html';
      const requests=[],errors=[],failed=[];
      await context.route(url,r=>r.fulfill({contentType:'text/html; charset=utf-8',body:fs.readFileSync(file)}));
      const page = await context.newPage();
      page.on('request',r=>requests.push({url:r.url(),type:r.resourceType()}));
      page.on('requestfailed',r=>failed.push(r.url()));page.on('pageerror',e=>errors.push(e.message));
      const consoleErrors=[];page.on('console',m=>{if(m.type()==='error')consoleErrors.push(m.text());});
      await page.goto(url);await page.waitForFunction(()=>document.querySelectorAll('canvas').length===4);
      assert.equal(await page.evaluate(()=>navigator.onLine),false);
      assert.deepEqual(requests.map(r=>r.url),[url]);assert.deepEqual(errors,[]);assert.deepEqual(consoleErrors,[]);
      assert.deepEqual(await page.locator('script[src],link[href],img[src],iframe[src]').count(),0);
      assert.equal(await page.locator('tbody tr[data-function-index]').count(),Math.min(20,artifact.data.functions.length));
      const metrics = await page.locator('.cards .value').allTextContents();
      assert.deepEqual(metrics,[artifact.data.fileSize,artifact.data.codeSize,artifact.data.gzipSize,artifact.data.deadSize].map(n=>n.toLocaleString('en-US')+' B'));
      const chartState = await page.evaluate(()=>['sections','functions','modules','treemap'].map(id=>{
        const el=document.getElementById(id),chart=echarts.getInstanceByDom(el),canvas=el.querySelector('canvas');
        const pixels=canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data;let colored=0;
        for(let i=0;i<pixels.length;i+=4)if(pixels[i+3]>0&&Math.max(pixels[i],pixels[i+1],pixels[i+2])-Math.min(pixels[i],pixels[i+1],pixels[i+2])>15)colored++;
        return {id,width:chart.getWidth(),height:chart.getHeight(),colored};
      }));
      for(const chart of chartState)assert(chart.colored>100,chart.id+' was blank/black');
      await page.locator('#sections canvas').hover({position:{x:300,y:55}});
      await page.waitForFunction(()=>document.querySelector('#sections').textContent.includes('independent gzip'));
      await page.screenshot({path:path.join(work,name+'-screen.png'),fullPage:true});
      if(name==='data-entries') {
        assert.equal(await page.locator('tr[data-segment-index]').count(),20);
        const s=artifact.data.dataSegments.summary;
        assert.deepEqual(await page.locator('.data-summary dd').allTextContents(),[s.total_size,s.payload_size,s.entry_metadata_size,s.section_overhead_size,s.entry_count].map(n=>n.toLocaleString('en-US')));
        assert.equal(await page.locator('#data-shown').textContent(),'Showing 20 of 45 entries. Printing includes only the displayed subset.');
        await page.locator('#data-segments').screenshot({path:path.join(work,'data-desktop.png')});
        await page.locator('#data-more').focus();await page.keyboard.press('Enter');
        assert.equal(await page.locator('tr[data-segment-index]').count(),40);
        const expected=artifact.data.dataSegments.entries.slice().sort((a,b)=>b.payload.size-a.payload.size||a.index-b.index).slice(0,40);
        assert.deepEqual(await page.locator('tr[data-segment-index]').evaluateAll(rows=>rows.map(r=>Number(r.dataset.segmentIndex))),expected.map(e=>e.index));
        await page.locator('.data-entry-details > summary').first().focus();await page.keyboard.press('Enter');
        assert.equal(await page.locator('.data-entry-details').first().evaluate(el=>el.open),true);
        await page.setViewportSize({width:390,height:900});
        assert((await page.evaluate(()=>document.documentElement.scrollWidth))<=390);
        const scroll=await page.locator('#data-segments .table-scroll').evaluate(el=>({client:el.clientWidth,scroll:el.scrollWidth}));
        assert(scroll.scroll>scroll.client,'Narrow table must scroll internally');
        await page.locator('#data-segments').screenshot({path:path.join(work,'data-mobile.png')});
        await page.setViewportSize({width:1440,height:1000});
        await page.waitForFunction(()=>['sections','functions','modules','treemap'].every(id=>{const e=document.getElementById(id);return echarts.getInstanceByDom(e).getWidth()===e.clientWidth;}));
        // Same browser, small targeted fallback checks, no new DOM adapters.
        for(const js of [false,true]) {
          const fallback=await browser.newContext({offline:true,serviceWorkers:'block',javaScriptEnabled:js});
          const body=js?artifact.html.replace(/<script>\n[\s\S]*?\n<\/script>/,''):artifact.html;
          await fallback.route(origin+'/',r=>r.fulfill({contentType:'text/html; charset=utf-8',body}));
          const p=await fallback.newPage();await p.goto(origin+'/');
          assert.equal(await p.locator('tr[data-segment-index]').count(),20);
          assert(await p.locator('#data-ledger').isVisible());
          if(!js)assert(await p.locator('#data-more').isHidden());
          else { assert(await p.locator('#chart-status').isVisible());await p.locator('#data-more').click();assert.equal(await p.locator('tr[data-segment-index]').count(),40); }
          await fallback.close();
        }
      }
      // Actual print invokes beforeprint/afterprint. Record state on both sides.
      const state = () => page.evaluate(()=>[...['function-details','method-details'].map(id=>document.getElementById(id)),...document.querySelectorAll('#data-segments details')].map(el=>el.open));
      if(name==='example')await page.locator('#function-details > summary').click();
      const before=await state();
      const originalLabels=await page.evaluate(()=>echarts.getInstanceByDom(document.getElementById('modules')).getOption().series[0].data.map(r=>r.label.show));
      await page.evaluate(()=>{
        window.__deliveryPrint=[];
        for(const type of ['beforeprint','afterprint'])addEventListener(type,()=>window.__deliveryPrint.push({type,
          open:['function-details','method-details'].map(id=>document.getElementById(id).open),
          data_open:[...document.querySelectorAll('#data-segments details')].map(el=>el.open),data_rows:document.querySelectorAll('tr[data-segment-index]').length,
          charts:['sections','functions','modules','treemap'].map(id=>{const e=document.getElementById(id),c=echarts.getInstanceByDom(e);return {id,container:e.clientWidth,chart:c.getWidth()};})}));
      });
      const pdf = path.join(work,name+'.pdf');
      await page.pdf({path:pdf,format:'A4',printBackground:true,margin:{top:'12mm',right:'12mm',bottom:'12mm',left:'12mm'}});
      assert.deepEqual(await state(),before,'Disclosure state was not restored after real PDF printing');
      assert.deepEqual(await page.evaluate(()=>echarts.getInstanceByDom(document.getElementById('modules')).getOption().series[0].data.map(r=>r.label.show)),originalLabels,'Screen pie labels were not restored');
      const events = await page.evaluate(()=>window.__deliveryPrint);
      assert.deepEqual(events.map(e=>e.type),['beforeprint','afterprint']);assert.deepEqual(events[0].open,[true,true]);
      for(const c of events[0].charts)assert.equal(c.chart,c.container,'Print chart width stale: '+c.id);
      assert.deepEqual(events[1].charts.map(c=>c.chart),chartState.map(c=>c.width),'Screen chart widths not restored');
      const doc = await getDocument({data:new Uint8Array(fs.readFileSync(pdf)),useSystemFonts:true}).promise;
      // Poppler is independent of the browser. PDF.js is used for structured
      // text/geometry only; rendering through native-canvas can lose font glyphs.
      const render=spawnSync(pdfRenderer,['-r','110','-png',pdf,path.join(work,name+'-page')],{encoding:'utf8',timeout:60000});
      assert.ifError(render.error);assert.equal(render.status,0,render.stderr);
      const pages=[];let text='',pdfImages=0,pdfPaths=0;
      for(let i=1;i<=doc.numPages;i++) {
        const p=await doc.getPage(i);
        const content=await p.getTextContent();const pageText=content.items.map(t=>t.str).join(' ');text+=pageText+'\n';
        assert(pageText.trim().length>30,'Unexpected blank PDF page');
        const png=path.join(work,name+'-page-'+String(i).padStart(String(doc.numPages).length,'0')+'.png');
        assert(fs.statSync(png).size>0);
        for(const item of content.items)if(item.str.trim()) {
          assert(item.transform[4]>=-1,'PDF text exceeds left edge');
          assert(item.transform[4]+item.width<=p.view[2]+1,'PDF text exceeds right edge: '+item.str);
        }
        const operators=await p.getOperatorList();
        // Canvas may be preserved as vectors or images. For images, check
        // transformed bounds, not merely that a chart container exists.
        let matrix=[1,0,0,1,0,0];const stack=[];
        const multiply=(a,b)=>[a[0]*b[0]+a[2]*b[1],a[1]*b[0]+a[3]*b[1],a[0]*b[2]+a[2]*b[3],a[1]*b[2]+a[3]*b[3],a[0]*b[4]+a[2]*b[5]+a[4],a[1]*b[4]+a[3]*b[5]+a[5]];
        for(let j=0;j<operators.fnArray.length;j++) {
          const op=operators.fnArray[j],args=operators.argsArray[j];
          if(op===OPS.constructPath)pdfPaths++;
          if(op===OPS.save)stack.push(matrix.slice());else if(op===OPS.restore)matrix=stack.pop();
          else if(op===OPS.transform)matrix=multiply(matrix,args);
          else if(op===OPS.paintImageXObject||op===OPS.paintInlineImageXObject) {
            pdfImages++;
            const xs=[matrix[4],matrix[4]+matrix[0],matrix[4]+matrix[2],matrix[4]+matrix[0]+matrix[2]];
            assert(Math.min(...xs)>=-1&&Math.max(...xs)<=p.view[2]+1,'PDF chart exceeds page bounds');
          }
        }
        pages.push({page:i,png,text:pageText});
      }
      const flattened=pdfTextKey(text);
      if(name==='data-entries') {
        for(const needle of ['Data segment encodings','Current input','Showing 40 of 45 entries','Printing includes only the displayed subset','not_evaluated','not_applicable','File offsets are not memory addresses'])assert(flattened.includes(pdfTextKey(needle)),needle+' missing in data PDF');
        assert.equal(events[0].data_rows,40);assert.equal(events[1].data_rows,40);
        assert(events[0].data_open.every(Boolean));
        assert.equal(await page.locator('tr[data-segment-index]').count(),40);
        // Last batch is appended only on demand, after printing the subset.
        await page.locator('#data-more').click();assert.equal(await page.locator('tr[data-segment-index]').count(),45);
        assert(await page.locator('#data-more').isHidden());
      }
      for(const needle of ['File size','Whole-file gzip','Methods, measurement ranges','not guaranteed deletion savings','independent'])assert(flattened.includes(pdfTextKey(needle)),needle+' missing in PDF');
      for(const value of metrics)assert(flattened.includes(pdfTextKey(value)),value+' missing in PDF');
      // Chromium may preserve Canvas 2D as PDF vectors rather than images.
      assert(pdfImages>=4||pdfPaths>=100,'PDF did not retain chart graphics');
      for(const slice of artifact.data.pie)assert(flattened.includes(pdfTextKey(slice.name)),'Module missing in printed legend');
      for(const f of artifact.data.functions.slice(0,20))assert(flattened.includes(pdfTextKey(f.name)),'Function name missing in PDF: '+f.index);
      if(name==='long-name-warning')assert(flattened.includes(pdfTextKey('no static table targets')));
      const responsive=[];
      for(const width of [1440,1024,768,390]) {
        await page.setViewportSize({width,height:900});
        await page.waitForFunction(()=>['sections','functions','modules','treemap'].every(id=>{const e=document.getElementById(id);return echarts.getInstanceByDom(e).getWidth()===e.clientWidth;}));
        const sizes=await page.evaluate(()=>({viewport:innerWidth,document:document.documentElement.scrollWidth}));
        assert(sizes.document<=sizes.viewport);responsive.push(sizes);
      }
      await page.screenshot({path:path.join(work,name+'-mobile-after-print.png'),fullPage:true});
      assert.deepEqual(errors,[]);assert.deepEqual(consoleErrors,[]);
      const renderConsoleErrors=consoleErrors.slice();
      // Prove the context's network control, not merely absence of URL strings.
      const probe=await page.evaluate(async()=>{try{await fetch('/offline-control-'+Date.now());return 'unexpected-success';}catch{return 'blocked';}});
      assert.equal(probe,'blocked');assert.equal(failed.length,1);assert.equal(requests.length,2);
      evidence.browser_cases.push({name,url,loaded_from:file,html_sha256:hash(fs.readFileSync(file)),offline:true,
        html_response:'local copied bytes via main-document-only HTTP route; subresources not fulfilled',
        original_context_closed:true,external_requests:requests.filter(r=>!r.url.startsWith(origin)),render_errors:errors,console_errors:renderConsoleErrors,
        chartState,metrics,responsive,pdf,pdf_sha256:hash(fs.readFileSync(pdf)),pdf_images:pdfImages,pdf_paths:pdfPaths,pages,print_events:events,state_restored:true,network_control:probe});
      await doc.destroy();await context.close();
    }
    evidence.offline_rendering='passed: fresh contexts, offline before navigation';
    evidence.pdf_validation='printed and rendered; see individual PNGs and human review record';
  } finally {await browser.close();fs.writeFileSync(path.join(work,'evidence.json'),JSON.stringify(evidence,null,2)+'\n');}
}
fs.writeFileSync(path.join(out,'latest.json'),JSON.stringify({directory:work,evidence:path.join(work,'evidence.json')},null,2)+'\n');
console.log(`HTML portability: ${cases} CLI cases passed${process.argv.includes('--browser')?'; fresh offline contexts and A4 PDFs rendered':''}. Evidence: ${work}`);
