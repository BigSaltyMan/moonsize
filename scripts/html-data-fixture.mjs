// One small shared fixture for HTML contract and real-browser acceptance.
const cat = (...xs) => Buffer.concat(xs.map(x=>Buffer.from(x)));
const leb = n => {const a=[];do{a.push((n&127)|(n>127?128:0));n>>>=7;}while(n);return Buffer.from(a);};
const section = (id,p) => cat([id],leb(p.length),p);
export function htmlDataFixture() {
  const entries=Array.from({length:45},(_,i)=>{
    const payload=Buffer.alloc(i%7,i);
    const init=i%3===0?[0,0x41,0x0b,0x0b]:i%3===1?[1]:[2,0,0x41,0,0x0b];
    return cat(init,leb(payload.length),payload);
  });
  return cat(Buffer.from('0061736d01000000','hex'),section(1,[1,0x60,0,0]),section(3,[1,0]),
    section(5,[1,0,1]),section(7,[1,3,114,117,110,0,0]),section(12,[45]),
    section(10,[1,2,0,0x0b]),section(11,cat([45],...entries)));
}
