///|
/// Inline report asset; no frontend build or network dependency.
const HTML_STYLE : String =
  #|:root {
  #|  --bg:#f5f4ef; --panel:#fff; --ink:#243644; --muted:#526572;
  #|  --line:#dce3e2; --accent:#087f8c; --soft:#edf6f5; --warn:#94521b;
  #|}
  #|* { box-sizing:border-box; }
  #|html { scroll-padding-top:24px; }
  #|body { margin:0; background:var(--bg); color:var(--ink); font:15px/1.6 system-ui,-apple-system,"Segoe UI",sans-serif; }
  #|a { color:var(--accent); text-underline-offset:4px; }
  #|a:focus-visible,summary:focus-visible,button:focus-visible,[tabindex]:focus-visible { outline:3px solid #086e85; outline-offset:4px; border-radius:4px; }
  #|.skip-link { position:absolute; top:8px; left:16px; padding:8px 14px; background:white; transform:translateY(-150%); z-index:10; }
  #|.skip-link:focus { transform:none; }
  #|.shell { max-width:1416px; margin:auto; padding:28px; min-width:0; }
  #|.report-header { padding:8px 0 22px; }
  #|.brand { display:flex; align-items:center; gap:10px; font-size:17px; font-weight:750; letter-spacing:-.02em; }
  #|.brand-mark { display:grid; place-items:center; width:30px; height:30px; border-radius:9px; background:var(--accent); color:white; font-family:ui-monospace,monospace; }
  #|.eyebrow { margin:20px 0 4px; color:var(--muted); font-size:12px; font-weight:650; letter-spacing:.08em; text-transform:uppercase; }
  #|h1 { margin:0 0 8px; font-size:30px; line-height:1.2; letter-spacing:-.035em; font-weight:700; }
  #|.file { margin:0; color:var(--muted); font:13px/1.6 ui-monospace,SFMono-Regular,Consolas,monospace; overflow-wrap:anywhere; }
  #|.report-meta { margin:9px 0 0; color:var(--muted); font-size:13px; }
  #|.report-nav { display:flex; flex-wrap:wrap; gap:8px 22px; margin-top:20px; padding-top:16px; border-top:1px solid var(--line); font-size:13px; font-weight:600; }
  #|.report-nav a { text-decoration:none; padding:3px 0; }
  #|.report-nav a:hover { text-decoration:underline; }
  #|.cards { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:14px; margin-bottom:18px; }
  #|.card { min-width:0; padding:20px; border:1px solid var(--line); border-radius:12px; background:var(--panel); box-shadow:0 2px 5px #24364404; }
  #|.label { display:block; font-size:13px; font-weight:600; color:var(--muted); }
  #|.value { display:block; margin:8px 0 5px; font-size:30px; line-height:1.25; font-weight:700; letter-spacing:-.035em; font-variant-numeric:tabular-nums; overflow-wrap:anywhere; }
  #|.sub { display:block; color:var(--muted); font-size:12px; line-height:1.65; }
  #|.card.alert .value { color:var(--warn); }
  #|.measurement-error { margin:10px 0 0; font-size:12px; color:var(--warn); overflow-wrap:anywhere; white-space:pre-wrap; }
  #|.analysis-status { padding:18px 20px; background:var(--soft); border:1px solid #c8dedb; border-left:4px solid var(--accent); border-radius:10px; margin-bottom:30px; }
  #|.analysis-status h2 { font-size:14px; margin:0 0 6px; }
  #|.analysis-status p { margin:5px 0; font-size:13px; }
  #|.analysis-status.warning { background:#fff5e9; border-color:#edcda4; border-left-color:var(--warn); }
  #|.warn { white-space:pre-line; overflow-wrap:anywhere; }
  #|.scope-note { font-weight:600; }
  #|.chart-status { margin:12px 0; padding:12px 16px; border:1px solid #edcda4; border-radius:8px; background:#fff5e9; font-size:13px; }
  #|.chart-status[hidden] { display:none; }
  #|.section-heading { display:flex; flex-wrap:wrap; justify-content:space-between; align-items:baseline; gap:6px 20px; margin:26px 0 12px; }
  #|.section-heading h2 { margin:0; font-size:19px; letter-spacing:-.02em; }
  #|.section-heading p { margin:0; color:var(--muted); font-size:13px; }
  #|.composition-grid { display:grid; grid-template-columns:minmax(0,1.15fr) minmax(0,1fr); gap:18px; align-items:start; }
  #|.panel { min-width:0; padding:20px; border:1px solid var(--line); border-radius:12px; background:var(--panel); }
  #|.panel h3 { font-size:15px; margin:0 0 6px; }
  #|.panel-note { font-size:12px; color:var(--muted); line-height:1.7; margin:0 0 12px; overflow-wrap:anywhere; }
  #|.panel-tools { display:flex; flex-wrap:wrap; justify-content:space-between; align-items:center; gap:8px; margin-bottom:8px; }
  #|button { font:inherit; font-size:12px; cursor:pointer; padding:6px 10px; border:1px solid #b8cfcd; border-radius:6px; background:var(--soft); color:#15505a; }
  #|button[aria-pressed="true"] { background:#d2eae6; }
  #|button:disabled { cursor:default; opacity:.7; }
  #|.chart { width:100%; min-width:0; height:240px; }
  #|.chart.ring { height:390px; }
  #|.chart.map { height:450px; }
  #|.print-legend { display:none; }
  #|.empty { min-height:120px; display:flex; align-items:center; justify-content:center; padding:20px; text-align:center; color:var(--muted); font-size:13px; }
  #|.function-details { margin-top:18px; border-top:1px solid var(--line); padding-top:14px; }
  #|summary { cursor:pointer; font-weight:600; font-size:14px; padding:6px 0; }
  #|.table-scroll { max-width:100%; overflow-x:auto; margin-top:10px; }
  #|table { width:100%; min-width:900px; border-collapse:collapse; table-layout:fixed; font-size:12px; }
  #|caption { text-align:left; color:var(--muted); padding:0 0 12px; font-size:12px; }
  #|th,td { padding:12px 10px; text-align:left; border-bottom:1px solid var(--line); vertical-align:top; }
  #|thead th { font-weight:600; color:var(--muted); background:#f5f8f7; }
  #|tbody tr:last-child td,tbody tr:last-child th { border-bottom:0; }
  #|.number { text-align:right; font-variant-numeric:tabular-nums; font-family:ui-monospace,SFMono-Regular,Consolas,monospace; }
  #|.function-name,.module-name { display:block; overflow-wrap:anywhere; white-space:pre-wrap; user-select:text; }
  #|.function-name { font-weight:600; font-family:ui-monospace,SFMono-Regular,Consolas,monospace; }
  #|.module-name { margin-top:5px; font-size:11px; color:var(--muted); }
  #|.reachability { display:inline-block; padding:3px 6px; border-radius:5px; background:var(--soft); color:#20545b; font-size:11px; line-height:1.4; }
  #|.reachability.unreachable { background:#fff0dc; color:#854814; }
  #|.data-segments { margin-top:26px; } .data-segments .section-heading { margin-top:0; }
  #|.data-summary { display:grid; grid-template-columns:repeat(5,minmax(0,1fr)); gap:12px; margin:16px 0; }
  #|.data-summary dt { color:var(--muted); font-size:12px; } .data-summary dd { margin:4px 0; font-size:22px; font-weight:700; font-variant-numeric:tabular-nums; overflow-wrap:anywhere; }
  #|.data-table { min-width:650px; } .data-entry-details summary { font:12px/1.6 ui-monospace,monospace; overflow-wrap:anywhere; }
  #|.data-entry-details p { font-size:11px; overflow-wrap:anywhere; margin:5px 0; } #data-more[hidden] { display:none; }
  #|@media (max-width:600px) { .data-summary { grid-template-columns:repeat(2,minmax(0,1fr)); } }
  #|.methods { margin-top:26px; padding:16px 20px; background:#eeefea; border:1px solid var(--line); border-radius:10px; }
  #|.methods p { font-size:13px; color:var(--muted); overflow-wrap:anywhere; }
  #|.methods h3 { font-size:13px; margin:18px 0 4px; }
  #|footer { padding:24px 0 0; color:var(--muted); font-size:12px; }
  #|@media (max-width:1100px) { .cards { grid-template-columns:repeat(2,minmax(0,1fr)); } .value { font-size:29px; } }
  #|@media (max-width:850px) { .composition-grid { grid-template-columns:minmax(0,1fr); } .chart.ring { height:360px; } }
  #|@media (max-width:480px) { .shell { padding:16px; } h1 { font-size:26px; } .cards { grid-template-columns:minmax(0,1fr); gap:10px; } .card { padding:16px 18px; } .panel { padding:16px 12px; } .analysis-status { padding:15px; } .report-nav { gap:8px 16px; } .chart.map { height:420px; } .section-heading { margin-top:24px; } }
  #|@page { size:A4 portrait; margin:12mm; }
  #|@media print {
  #|  body { background:white; font-size:12px; print-color-adjust:exact; -webkit-print-color-adjust:exact; }
  #|  .shell { width:186mm; max-width:100%; padding:0; }
  #|  .report-header { padding:0 0 12px; } h1 { font-size:24px; }
  #|  .report-nav,.skip-link,button,.report-tooltip { display:none!important; position:static; }
  #|  .cards { grid-template-columns:repeat(2,minmax(0,1fr)); gap:10px; }
  #|  .card { padding:12px; } .value { font-size:24px; margin:4px 0; }
  #|  .analysis-status { padding:10px 12px; margin-bottom:14px; }
  #|  .card,.analysis-status,.chart { break-inside:avoid; box-shadow:none; }
  #|  .composition-grid { grid-template-columns:1fr; }
  #|  .section-heading { margin-top:16px; break-after:avoid; }
  #|  #composition,#function-ranking,#module-map { break-before:page; }
  #|  #composition .panel { break-inside:avoid; }
  #|  h2,h3,summary,caption { break-after:avoid; }
  #|  .panel { border-color:#c9d1d1; padding:12px; margin-bottom:12px; break-inside:auto; }
  #|  .table-scroll { overflow:visible; } table { min-width:0; font-size:10px; }
  #|  th,td { padding:6px 4px; overflow-wrap:anywhere; } thead { display:table-header-group; } tr { break-inside:avoid; }
  #|  .methods,.function-details { break-inside:auto; } .methods { margin-top:14px; padding:12px; }
  #|  .data-segments { break-before:page; } .data-table { min-width:0; } .data-entry-details summary { font-size:10px; }
  #|  .data-summary { grid-template-columns:repeat(5,minmax(0,1fr)); } .data-summary dd { font-size:17px; }
  #|  .methods p { font-size:12px; line-height:1.5; } .methods h3 { margin-top:12px; }
  #|  .print-legend { display:grid; grid-template-columns:1fr 1fr; gap:3px 16px; margin:8px 0 0; padding:0; list-style:none; font-size:11px; overflow-wrap:anywhere; }
  #|  footer { padding-top:12px; break-before:avoid; } a { color:inherit; }
  #|}

///|
/// Inline report asset; no frontend build or network dependency.
const HTML_SCRIPT : String =
  #|const DATA = __DATA__;
  #|
  #|const esc = (s) => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  #|const BYTES = (v) => {
  #|  if (v === null || v === undefined) return 'failed';
  #|  if (v >= 1048576) return (v / 1048576).toFixed(2) + ' MB';
  #|  if (v >= 1024) return (v / 1024).toFixed(1) + ' KB';
  #|  return v + ' B';
  #|};
  #|const NUM = v => v.toLocaleString('en-US');
  #|const PCT = (part,whole) => whole > 0 ? (part / whole * 100).toFixed(1) + '%' : 'n/a';
  #|const RATIO = (raw,gzip) => gzip > 0 ? (raw / gzip).toFixed(2) + 'x' : 'n/a';
  #|const INK = '#344c59', LINE = '#e5ece9', MONO = 'ui-monospace,SFMono-Regular,Consolas,monospace';
  #|const PALETTE = ['#147d8d','#576bac','#99724c','#417f68','#916385','#557f9d','#8c7c42','#697a50','#9b6663','#576c7a'];
  #|// Identity, not rank, chooses a module's color. Both charts use this mapping.
  #|function moduleColor(name) {
  #|  let hash = 2166136261;
  #|  for (let i=0;i<name.length;i++) hash = Math.imul(hash ^ name.charCodeAt(i),16777619) >>> 0;
  #|  return PALETTE[hash % PALETTE.length];
  #|}
  #|const base = {animation:false, aria:{enabled:true}, textStyle:{fontFamily:'system-ui,-apple-system,"Segoe UI",sans-serif'}};
  #|const axis = extra => Object.assign({axisLine:{show:false},axisTick:{show:false},axisLabel:{color:INK,fontSize:11},splitLine:{lineStyle:{color:LINE}}},extra);
  #|function labelWidth(id) {
  #|  const width = document.getElementById(id).clientWidth || window.innerWidth || 1000;
  #|  return Math.max(76,Math.min(230,Math.floor(width * .28)));
  #|}
  #|function barOption(rows,color,maxValue,gzipColor,id) {
  #|  maxValue = Math.max(1,maxValue,...rows.map(r => r.gzip ?? 0));
  #|  const unit = maxValue >= 1048576 ? 1048576 : maxValue >= 1024 ? 1024 : 1;
  #|  const suffix = unit === 1048576 ? ' MB' : unit === 1024 ? ' KB' : ' B';
  #|  const step = unit * Math.max(1,Math.ceil(maxValue / unit / 4));
  #|  const top = step * Math.ceil(maxValue / step);
  #|  const tick = v => unit === 1 ? String(Math.round(v)) : (v / unit).toFixed(1).replace(/\.0$/,'') + suffix;
  #|  const series = [{name:'raw',type:'bar',barMaxWidth:12,data:rows.map(r=>r.size),
  #|    itemStyle:{color,borderRadius:[0,3,3,0]},label:{show:true,position:'right',color:INK,fontSize:11,formatter:p=>BYTES(p.value)}}];
  #|  let legend;
  #|  if (gzipColor !== undefined) {
  #|    series.push({name:'independent gzip',type:'bar',barGap:'20%',barMaxWidth:12,data:rows.map(r=>r.gzip),
  #|      itemStyle:{color:gzipColor,borderRadius:[0,3,3,0]},label:{show:true,position:'right',color:INK,fontSize:11,formatter:p=>BYTES(p.value)}});
  #|    legend = {data:['raw','independent gzip'],selected:{raw:true,'independent gzip':false},
  #|      top:0,left:0,icon:'roundRect',itemWidth:10,itemHeight:8,textStyle:{color:INK,fontSize:11}};
  #|  }
  #|  return Object.assign({},base,{
  #|    grid:{left:labelWidth(id)+10,right:80,top:legend?36:12,bottom:30,containLabel:false},
  #|    tooltip:{className:'report-tooltip',trigger:'axis',confine:true,axisPointer:{type:'shadow'},extraCssText:'max-width:min(460px,80vw);white-space:normal;overflow-wrap:anywhere;',
  #|      formatter:ps=>{
  #|        const r=rows[ps[0].dataIndex];
  #|        let text='<b>'+esc(r.name)+'</b>'+(r.index===undefined?'':'<br/>function #'+r.index)+'<br/>'+(r.body?'body ':'raw ')+NUM(r.size)+' B ('+PCT(r.size,DATA.fileSize)+' of file)';
  #|        const gzipRaw = r.gzipRawSize ?? r.size;
  #|        if (r.gzip !== null && r.gzip !== undefined) text+='<br/>independent gzip '+NUM(r.gzip)+' B ('+PCT(r.gzip,gzipRaw)+' of encoded raw, '+RATIO(gzipRaw, r.gzip)+')';
  #|        else if (r.gzipError !== null && r.gzipError !== undefined) text+='<br/>independent gzip failed: '+esc(r.gzipError);
  #|        return text;
  #|      }},
  #|    xAxis:axis({type:'value',min:0,max:top,interval:step,name:unit===1?'B':'',nameTextStyle:{color:INK},
  #|      axisLabel:{color:INK,fontSize:11,hideOverlap:true,formatter:tick}}),
  #|    yAxis:axis({type:'category',inverse:true,data:rows.map(r=>r.name),
  #|      axisLabel:{color:INK,fontSize:11,fontFamily:MONO,width:labelWidth(id),overflow:'truncate',interval:0},splitLine:{show:false}}),
  #|    series,...(legend?{legend}:{})
  #|  });
  #|}
  #|function pieOption(rows) {
  #|  const total=rows.reduce((sum,r)=>sum+r.size,0);
  #|  return Object.assign({},base,{
  #|    tooltip:{className:'report-tooltip',trigger:'item',confine:true,extraCssText:'max-width:min(460px,80vw);white-space:normal;overflow-wrap:anywhere;',formatter:p=>{
  #|      const r=rows[p.dataIndex];
  #|      let text='<b>'+esc(p.name)+'</b><br/>'+NUM(p.value)+' B<br/>'+PCT(p.value,total)+' of attributed function bytes';
  #|      text+='<br/>'+PCT(p.value,DATA.codeSize)+' of complete code section';
  #|      if(r&&r.members&&r.members.length)text+='<br/>'+esc(r.members.join(', '));
  #|      return text;
  #|    }},
  #|    legend:{type:'scroll',bottom:4,left:'center',icon:'circle',itemWidth:9,itemHeight:9,
  #|      textStyle:{color:INK,fontSize:11,width:190,overflow:'truncate'},tooltip:{className:'report-tooltip',show:false}},
  #|    series:[{type:'pie',radius:['46%','72%'],center:['50%','43%'],avoidLabelOverlap:true,
  #|      itemStyle:{borderColor:'#fff',borderWidth:2},labelLine:{show:false},
  #|      label:{position:'inside',fontSize:11,color:'#fff',formatter:'{d}%'},
  #|      data:rows.map(r=>({name:r.name,value:r.size,label:{show:total>0&&r.size/total>=.07},
  #|        itemStyle:{color:r.members&&r.members.length?'#7d8990':moduleColor(r.name)}}))}]
  #|  });
  #|}
  #|function treemapOption(rows) {
  #|  return Object.assign({},base,{
  #|    tooltip:{className:'report-tooltip',confine:true,extraCssText:'max-width:min(460px,80vw);white-space:normal;overflow-wrap:anywhere;',formatter:p=>{
  #|      let text='<b>'+esc(p.name)+'</b><br/>'+NUM(p.value)+' B';
  #|      if(p.data&&p.data.index!==undefined)text+='<br/>function #'+p.data.index;
  #|      if(p.data&&p.data.gzip!==null&&p.data.gzip!==undefined)text+='<br/>independent gzip '+NUM(p.data.gzip)+' B ('+RATIO(p.value, p.data.gzip)+')';
  #|      else if (p.data && p.data.gzipError !== null && p.data.gzipError !== undefined) text+='<br/>independent gzip failed: '+esc(p.data.gzipError);
  #|      if(p.data&&p.data.dead)text+='<br/>Unreachable in the current model; investigation candidate, not guaranteed savings.';
  #|      return text;
  #|    }},
  #|    series:[{type:'treemap',roam:false,nodeClick:false,breadcrumb:{show:false},width:'100%',height:'100%',top:0,left:0,
  #|      upperLabel:{show:true,height:25,fontSize:12,color:'#fff',overflow:'truncate'},
  #|      label:{show:true,formatter:p=>(p.data.dead?'[unreachable] ':'')+p.name,fontSize:11,overflow:'truncate'},
  #|      itemStyle:{borderColor:'#fff',borderWidth:1,gapWidth:2},
  #|      levels:[{itemStyle:{borderWidth:0,gapWidth:4}},{itemStyle:{borderWidth:1,gapWidth:1}}],
  #|      data:rows.map(m=>({name:m.name,value:m.size,itemStyle:{color:moduleColor(m.name)},
  #|        children:m.children.map(c=>({name:c.name,value: c.value,index:c.index,dead:c.dead,gzip:c.gzip,gzipError:c.gzipError,
  #|          itemStyle:{color:moduleColor(m.name),borderColor:c.dead?'#814b22':'#ffffff',borderWidth:c.dead?2:1}}))}))}]
  #|  });
  #|}
  #|function emptyInto(id,message) {
  #|  const el=document.getElementById(id);el.className='empty';el.style.height='auto';el.textContent=message;
  #|}
  #|function unavailable(message) {
  #|  const status=document.getElementById('chart-status');status.hidden=false;status.textContent=message;
  #|  document.getElementById('function-details').open=true;
  #|}
  #|const charts=[];
  #|function mount(id,option) {
  #|  try {const chart=echarts.init(document.getElementById(id));chart.setOption(option);charts.push({id,chart});return chart;}
  #|  catch(error){emptyInto(id,'Chart unavailable. Read the measured cards and function details below.');
  #|    unavailable('Some charts could not be drawn. Measured cards, function details and methods remain available.');return null;}
  #|}
  #|function main() {
  #|  const sections=DATA.sections.map(s=>({name:s.name,size:s.total,payload:s.payload,gzip:s.gzip,gzipError:s.gzipError})).sort((a,b)=>b.size-a.size);
  #|  const top=DATA.functions.slice(0,20).map(f=>({name:f.name,index:f.index,body:true,size:f.bodySize,gzipRawSize: f.size,gzip:f.gzip,gzipError:f.gzipError}));
  #|  document.getElementById('sections').style.height=Math.max(170,sections.length*36+66)+'px';
  #|  document.getElementById('functions').style.height=Math.max(150,top.length*31+48)+'px';
  #|  const compare=document.getElementById('section-compare');
  #|  if(typeof echarts==='undefined') {
  #|    unavailable('Charts unavailable: ECharts did not load. All measured cards, function details and methods remain readable. CDN mode needs a network connection.');
  #|    ['sections','functions','modules','treemap'].forEach(id=>emptyInto(id,'Chart library unavailable; see measured values and function details.'));
  #|    compare.disabled=true;return;
  #|  }
  #|  let sectionChart=null;
  #|  if(sections.length)sectionChart=mount('sections',barOption(sections,'#148696',sections[0].size,'#8c72ad','sections'));
  #|  else emptyInto('sections','No sections in this module.');
  #|  if(top.length)mount('functions',barOption(top,'#168579',top[0].size,undefined,'functions'));
  #|  else emptyInto('functions','No local functions in this module.');
  #|  if(DATA.pie.length)mount('modules',pieOption(DATA.pie));else emptyInto('modules','No attributed function bytes.');
  #|  const modules=DATA.modules.filter(m=>m.size>0);
  #|  if(modules.length)mount('treemap',treemapOption(modules));else emptyInto('treemap','No local functions to map.');
  #|  compare.disabled=!sectionChart;
  #|  if(sectionChart) {
  #|    let show=false;
  #|    compare.addEventListener('click',()=>{show=!show;compare.setAttribute('aria-pressed',String(show));
  #|      sectionChart.dispatchAction({type:show?'legendSelect':'legendUnSelect',name:'independent gzip'});});
  #|    sectionChart.on('legendselectchanged',event=>{show=!!event.selected['independent gzip'];compare.setAttribute('aria-pressed',String(show));});
  #|  }
  #|}
  #|function wireReport() {
  #|  const resize=()=>charts.forEach(({id,chart})=>{
  #|    chart.resize({animation:{duration:0}});if(id==='sections'||id==='functions')chart.setOption({yAxis:{axisLabel:{width:labelWidth(id)}},grid:{left:labelWidth(id)+10}});
  #|    // Flush the synchronous, animation-free drawing before the print snapshot.
  #|    chart.getZr?.().flush();
  #|  });
  #|  window.addEventListener('resize',resize);
  #|  let printState=null,printStyles=null;
  #|  window.addEventListener('beforeprint',()=>{
  #|    if(!printState){
  #|      const disclosures=['function-details','method-details'].map(id=>document.getElementById(id));
  #|      if(DATA.dataSegments)disclosures.push(...document.querySelectorAll('#data-segments details'));
  #|      printState=disclosures.map(el=>{const open=el.open;el.open=true;return [el,open];});
  #|      const ids=['report','composition-panels','sections','functions','modules','treemap'];
  #|      printStyles=ids.map(id=>{const el=document.getElementById(id);return [el,el.style.cssText];});
  #|      // beforeprint can precede the browser's final paper layout. Establish
  #|      // the A4 content width and one-column chart layout before redrawing.
  #|      Object.assign(document.getElementById('report').style,{width:'186mm',maxWidth:'100%',padding:'0'});
  #|      document.getElementById('composition-panels').style.gridTemplateColumns='minmax(0,1fr)';
  #|      for(const [id,height] of [['sections',Math.max(170,DATA.sections.length*21+48)],['functions',Math.max(150,Math.min(20,DATA.functions.length)*22+48)],['modules',220],['treemap',300]])document.getElementById(id).style.height=height+'px';
  #|    }
  #|    charts.forEach(({chart})=>chart.dispatchAction({type:'hideTip'}));resize();
  #|    // The complete printed legend carries exact values. Tiny pie sectors
  #|    // cannot fit percentage labels at paper size without clipping them.
  #|    charts.filter(c=>c.id==='modules').forEach(({chart})=>chart.setOption({series:[{data:pieOption(DATA.pie).series[0].data.map(r=>({...r,label:{show:false}}))}]}));
  #|  });
  #|  window.addEventListener('afterprint',()=>{
  #|    if(printState){printState.forEach(([el,open])=>{el.open=open;});printStyles.forEach(([el,css])=>{el.style.cssText=css;});printState=null;printStyles=null;charts.filter(c=>c.id==='modules').forEach(({chart})=>chart.setOption({series:[{data:pieOption(DATA.pie).series[0].data}]}));}resize();
  #|  });
  #|}
  #|// Pagination is independent of ECharts and never creates hidden batches.
  #|function wireDataSegments() {
  #|  if(!DATA.dataSegments)return;
  #|  const entries=DATA.dataSegments.entries.slice().sort((a,b)=>b.payload.size-a.payload.size||a.index-b.index);
  #|  const rows=document.getElementById('data-rows'),more=document.getElementById('data-more'),status=document.getElementById('data-shown');
  #|  let shown=Math.min(20,entries.length);
  #|  const update=()=>{status.textContent='Showing '+shown+' of '+entries.length+' entries. Printing includes only the displayed subset.';more.hidden=shown>=entries.length;};
  #|  const node=(tag,text,cls)=>{const el=document.createElement(tag);if(text!==undefined)el.textContent=text;if(cls)el.className=cls;return el;};
  #|  const range=r=>'['+r.file_offset+', '+(r.file_offset+r.size)+')';
  #|  function appendDataEntry(e) {
  #|    const row=node('tr');row.setAttribute('data-segment-index',String(e.index));
  #|    const index=node('th',String(e.index),'number');index.setAttribute('scope','row');row.appendChild(index);
  #|    row.appendChild(node('td',e.mode));row.appendChild(node('td',e.memory_index===null?'n/a':String(e.memory_index),'number'));
  #|    row.appendChild(node('td',NUM(e.payload.size),'number'));row.appendChild(node('td',NUM(e.encoding.size),'number'));
  #|    const cell=node('td'),details=node('details',undefined,'data-entry-details');details.appendChild(node('summary',range(e.encoding)));
  #|    details.appendChild(node('p','Payload file range '+range(e.payload)));
  #|    details.appendChild(node('p',e.offset_expression?'Offset expression file range '+range(e.offset_expression)+'; not_evaluated (includes end).':'Offset expression not_applicable.'));
  #|    cell.appendChild(details);row.appendChild(cell);rows.appendChild(row);return row;
  #|  }
  #|  more.addEventListener('click',()=>{const end=Math.min(shown+20,entries.length);for(;shown<end;shown++)appendDataEntry(entries[shown]);update();});
  #|  update();
  #|}
  #|wireDataSegments();
  #|main();
  #|wireReport();
