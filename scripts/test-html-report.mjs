// Rendering contracts, not browser layout or screenshot acceptance.
// Execute the generated report's own JavaScript with observable chart/DOM adapters.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
const parent=path.resolve(os.tmpdir()),work=fs.mkdtempSync(path.join(parent,'moonsize-html-'));
let cases=0,fixtures=0;
const cat=(...parts)=>Buffer.concat(parts.map(p=>Buffer.from(p)));
const leb=n=>{const a=[];do{const b=n&127;n>>>=7;a.push(b|(n?128:0));}while(n);return Buffer.from(a);};
const str=s=>cat(leb(Buffer.byteLength(s)),Buffer.from(s));
const section=(id,p)=>cat([id],leb(p.length),p);
function fixture(label,names,{imports=0,dynamic=false,empty=false,customs=false}={}) {
  const bodies=names.map((_,i)=>dynamic?Buffer.from([0,65,0,17,0,0,11]):cat([0],Buffer.alloc(i===0&&names.length>25?2000:i*6,1),[11]));
  const chunks=[Buffer.from('0061736d01000000','hex')];
  if(!empty)chunks.push(section(1,Buffer.from([1,96,0,0])));
  if(imports)chunks.push(section(2,cat(leb(imports),...Array.from({length:imports},()=>cat(str('host'),str('f'),[0,0])))));
  if(!empty)chunks.push(section(3,cat(leb(names.length),Buffer.alloc(names.length))));
  if(dynamic)chunks.push(section(4,Buffer.from([1,112,0,1])));
  if(names.length)chunks.push(section(7,cat([1],str('run'),[0],leb(imports))));
  const code=empty?null:section(10,cat(leb(bodies.length),...bodies.map(b=>cat(leb(b.length),b))));
  if(code)chunks.push(code);
  const nameRows=names.flatMap((name,i)=>name===null?[]:[cat(leb(i+imports),str(name))]);
  if(nameRows.length)chunks.push(section(0,cat(str('name'),section(1,cat(leb(nameRows.length),...nameRows)))));
  if(customs)for(const name of ['中文','中文'])chunks.push(section(0,str(name)));
  const bytes=cat(...chunks);assert(WebAssembly.validate(bytes),label+' was not valid Wasm');fixtures++;
  const file=path.join(work,label+'.wasm');fs.writeFileSync(file,bytes);
  return {file,bytes,names,bodies,imports,codeSize:code?.length||0};
}
function run(args,cwd=process.cwd()) {
  const r=spawnSync(cli,args,{cwd,encoding:'utf8',timeout:5000,maxBuffer:8*1024*1024});cases++;
  assert(!r.error&&!r.signal);assert.equal(r.status,0,r.stdout+r.stderr);return r.stdout;
}
const unescape=s=>s.replace(/&(amp|lt|gt|quot|#39);/g,(_,e)=>({'amp':'&','lt':'<','gt':'>','quot':'"','#39':"'"}[e]));
const plain=s=>unescape(s.replace(/<[^>]*>/g,''));
function read(html) {
  const script=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]).find(s=>s.includes('const DATA = '));
  assert(script);const literal=script.match(/const DATA = (.*);\r?\n/)[1];return {script,literal,data:JSON.parse(literal)};
}
function execute(script,{width=1440,library=true,throwInit=false}={}) {
  const options={},elements={},actions=[],callbacks={},patches=[],chartEvents={},windows={};
  function element(id) {return elements[id]??={id,style:{},clientWidth:id==='sections'?Math.floor(width*.5):width-56,open:id==='function-details',
    addEventListener(type,callback){callbacks[id+':'+type]=callback;},setAttribute(key,value){this[key]=value;}};}
  const context={document:{getElementById:element},window:{innerWidth:width,addEventListener(type,callback){windows[type]=callback;}}};
  if(library)context.echarts={init(el){if(throwInit)throw Error('adapter failure');return {
    setOption(option){if(option.series)options[el.id]=option;else patches.push({id:el.id,option});},
    dispatchAction(action){actions.push(action);},on(type,callback){chartEvents[el.id+':'+type]=callback;},resize(){}};}};
  vm.createContext(context);vm.runInContext(script+'\nglobalThis.bytesFormatter=BYTES;',context,{timeout:1000});
  return {options,elements,actions,callbacks,patches,chartEvents,windows,context};
}
function checkTable(html,data) {
  const table=html.match(/<table>[\s\S]*?<\/table>/)[0];
  const rows=[...table.matchAll(/<tr data-function-index="(\d+)">([\s\S]*?)<\/tr>/g)];
  assert.equal(rows.length,Math.min(20,data.functions.length));
  for(const [rank,row] of rows.entries()) {
    const f=data.functions[rank],cells=[...row[2].matchAll(/<(?:th|td)[^>]*>([\s\S]*?)<\/(?:th|td)>/g)].map(m=>plain(m[1]));
    assert.equal(cells.length,7);assert.equal(Number(row[1]),f.index);assert.equal(Number(cells[0]),rank+1);assert.equal(Number(cells[1]),f.index);
    assert.equal(plain(row[2].match(/<span class="function-name">([\s\S]*?)<\/span>/)[1]),f.name);
    assert.equal(plain(row[2].match(/<span class="module-name">([\s\S]*?)<\/span>/)[1]),f.module);
    assert.equal(Number(cells[3].replaceAll(',','')),f.bodySize);assert.equal(Number(cells[4].replaceAll(',','')),f.size);
    assert.equal(Number(cells[5].replaceAll(',','')),f.gzip);
    assert.equal(cells[6],f.dead?'Unreachable in model':'Reachable in model');
  }
  if(!data.functions.length)assert(table.includes('No local functions in this module.'));
}
try {
  const long='包.'+'很长module_'.repeat(90)+'<&"\n</script>';
  const configs=[fixture('empty',[],{empty:true}),fixture('single',['pkg.one']),
    fixture('ranked',Array.from({length:25},(_,i)=>i===23?long:i===24?null:i%3===0?'same':`pkg.f${i}`),{imports:2}),
    fixture('many-modules',Array.from({length:50},(_,i)=>`module${i}/f`)),
    fixture('dynamic',['entry'],{dynamic:true}),fixture('customs',[],{customs:true})];
  for(const f of configs) {
    const target=path.join(work,path.basename(f.file)+'.html');run([f.file,'--html',target]);const html=fs.readFileSync(target,'utf8');
    const {script,data,literal}=read(html);assert.equal(data.schema_version,1);assert.equal(data.fileSize,f.bytes.length);
    assert.equal(data.codeSize,f.codeSize);
    const staticBody=html.slice(html.indexOf('<body>'),html.indexOf('<script'));
    const ids=[...staticBody.matchAll(/\bid="([^"]+)"/g)].map(m=>m[1]);assert.equal(new Set(ids).size,ids.length);
    for(const [,anchor] of staticBody.matchAll(/href="#([^"]+)"/g))assert(ids.includes(anchor));
    assert(!html.includes('<script src='));assert(!html.includes('<link '));assert(!html.includes('src="http'));
    assert(html.includes('Model results identify investigation candidates, not guaranteed deletion savings.'));
    assert(html.includes('Shares are based on attributed function bytes; code-section overhead is excluded.'));
    assert(html.includes(`${data.functions.length} local functions`));
    for(const [label,value] of [['File size',data.fileSize],['Code section',data.codeSize],['Whole-file gzip',data.gzipSize],['Unreachable in model',data.deadSize]]) {
      assert(html.includes(`<span class="label">${label}</span>\n        <span class="value">${value.toLocaleString('en-US')} B</span>`));
    }
    assert.equal(data.functions.length,f.names.length);
    const expected=f.bodies.map((body,i)=>({index:i+f.imports,bodySize:body.length,size:body.length+leb(body.length).length})).sort((a,b)=>b.bodySize-a.bodySize||a.index-b.index);
    assert.deepEqual(data.functions.map(r=>({index:r.index,bodySize:r.bodySize,size:r.size})),expected);
    checkTable(html,data);
    if(!data.graph_complete) {assert(html.includes('<h2>Detected graph gaps</h2>'));assert(html.indexOf('<p class="warn">WARNING:')<html.indexOf('<details'));}
    else assert(html.includes('<h2>No detected graph gaps</h2>'));
    for(const width of [1440,1024,768,390]) {
      const runtime=execute(script,{width}),o=runtime.options;
      assert.equal(runtime.context.bytesFormatter(null),'failed');
      if(data.sections.length) {
        assert.equal(o.sections.xAxis.max>=Math.max(...data.sections.flatMap(s=>[s.total,s.gzip??0])),true);
        assert.equal(o.sections.yAxis.axisLabel.width<=230,true);
        assert.equal(runtime.elements.sections.style.height,Math.max(170,data.sections.length*36+66)+'px');
        runtime.callbacks['section-compare:click']();assert.equal(runtime.actions.at(-1).type,'legendSelect');assert.equal(runtime.elements['section-compare']['aria-pressed'],'true');
        runtime.callbacks['section-compare:click']();assert.equal(runtime.actions.at(-1).type,'legendUnSelect');
        runtime.chartEvents['sections:legendselectchanged']({selected:{'independent gzip':true}});assert.equal(runtime.elements['section-compare']['aria-pressed'],'true');
      }
      if(data.functions.length) {
        assert.deepEqual(Array.from(o.functions.series[0].data),data.functions.slice(0,20).map(f=>f.bodySize));
        assert.equal(runtime.elements.functions.style.height,Math.max(150,Math.min(20,data.functions.length)*31+48)+'px');
        const leaf=o.treemap.series[0].data.flatMap(m=>m.children).find(c=>c.index===data.functions[0].index);
        assert.equal(leaf.value,data.functions[0].size);
        if(leaf.dead)assert(o.treemap.tooltip.formatter({name:leaf.name,value:leaf.value,data:leaf}).includes('Unreachable in the current model'));
        for(const m of o.treemap.series[0].data) {
          const slice=o.modules.series[0].data.find(s=>s.name===m.name);
          if(slice)assert.equal(slice.itemStyle.color,m.itemStyle.color);
          for(const child of m.children)assert.equal(child.itemStyle.color,m.itemStyle.color);
        }
        const total=data.pie.reduce((n,p)=>n+p.size,0),slice=data.pie[0];
        const tip=o.modules.tooltip.formatter({name:slice.name,value:slice.size,dataIndex:0,percent:99});
        assert(tip.includes((slice.size/total*100).toFixed(1)+'% of attributed function bytes'));
        assert(tip.includes((slice.size/data.codeSize*100).toFixed(1)+'% of complete code section'));
        runtime.elements.functions.clientWidth=250;runtime.windows.resize();
        assert.equal(runtime.patches.find(p=>p.id==='functions').option.yAxis.axisLabel.width,76);
      }
      runtime.windows.beforeprint();assert.equal(runtime.elements['method-details'].open,true);
      runtime.windows.afterprint();assert.equal(runtime.elements['method-details'].open,false);
    }
    for(const settings of [{library:false},{throwInit:true}]) {
      // An empty report never initializes a chart, so an init fault is irrelevant.
      if(settings.throwInit&&!data.sections.length&&!data.functions.length)continue;
      const runtime=execute(script,settings);assert.equal(runtime.elements['chart-status'].hidden,false);
      assert(runtime.elements['chart-status'].textContent.includes('remain'));assert.equal(runtime.elements['function-details'].open,true);
      assert.equal(runtime.elements['section-compare'].disabled,true);
      if(settings.library===false)assert.equal(Object.keys(runtime.options).length,0);
      runtime.windows.beforeprint();assert.equal(runtime.elements['method-details'].open,true);runtime.windows.afterprint();
    }
    // Rank changes do not change a module's identity color.
    if(data.modules.length>1) {
      const reversed=structuredClone(data);reversed.modules.reverse();reversed.pie.reverse();
      const a=execute(script).options.treemap.series[0].data,b=execute(script.replace(literal,JSON.stringify(reversed))).options.treemap.series[0].data;
      for(const module of a)assert.equal(module.itemStyle.color,b.find(m=>m.name===module.name).itemStyle.color);
    }
    const detached=path.join(work,'copy-'+path.basename(target));fs.copyFileSync(target,detached);
    assert.deepEqual(read(fs.readFileSync(detached,'utf8')).data,data);
    assert(!read(fs.readFileSync(detached,'utf8')).script.includes('fetch('));
  }
  // ECharts is deliberately unavailable in this cwd; CLI still provides its server-rendered table.
  const f=configs[1],cdn=path.join(work,'cdn.html');
  const notice=run([f.file,'--html',cdn],work);assert(notice.includes('CDN'));
  const html=fs.readFileSync(cdn,'utf8'),parsed=read(html);assert(html.includes('CDN fallback mode: charts need a network connection'));assert(html.includes('<script src='));
  assert(html.includes('<p id="chart-resource-mode" class="panel-note">CDN chart mode: charts require a network connection.'));
  checkTable(html,parsed.data);assert.equal(execute(parsed.script,{library:false}).elements['chart-status'].hidden,false);
  const folder=path.join(work,'目录-'+'long_'.repeat(12));fs.mkdirSync(folder);
  const longPath=path.join(folder,'很长的输入文件名.wasm');fs.copyFileSync(f.file,longPath);
  const longReport=path.join(work,'long-path.html');run([longPath,'--html',longReport]);
  const longHtml=fs.readFileSync(longReport,'utf8');assert(longHtml.includes(`<p class="file">${longPath}</p>`));assert.equal(read(longHtml).data.file,longPath);
  console.log(`HTML-report CLI regressions passed (${cases} process cases, ${fixtures} V8-validated modules; script adapters at 1440/1024/768/390, not browser layout acceptance).`);
} finally {
  assert.equal(path.dirname(work),parent);assert(path.basename(work).startsWith('moonsize-html-'));fs.rmSync(work,{recursive:true,force:true});
}
