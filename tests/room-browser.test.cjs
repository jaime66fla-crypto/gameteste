const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),vm=require('vm');
function setup(fetcher){
 assert(fs.existsSync('public/room-browser.js'),'Room browser UI must exist');
 class Element{constructor(){this.children=[];this.events={};this.disabled=false}replaceChildren(...nodes){this.children=nodes}appendChild(node){this.children.push(node)}addEventListener(type,fn){this.events[type]=fn}click(){if(!this.disabled)this.events.click?.()}setAttribute(){}}
 const c={window:{},document:{createElement:()=>new Element()},fetch:fetcher,setTimeout,clearTimeout,AbortController};vm.createContext(c);vm.runInContext(fs.readFileSync('public/room-browser.js','utf8'),c);
 const root=new Element(),status=new Element(),button=new Element(),joins=[];
 const browser=new c.window.PublicRoomBrowser({root,status,refreshButton:button,onJoin:code=>joins.push(code)});
 return {browser,root,status,button,joins};
}
test('browser renders public rooms, joins by code, and disables full rooms',async()=>{
 const s=setup(async()=>({ok:true,json:async()=>({rooms:[{code:'FLR-ABCDE',players:2,capacity:8},{code:'FLR-FGHIJ',players:8,capacity:8}]})}));
 await s.browser.open();assert.equal(s.root.children.length,2);assert.equal(s.root.children[0].children[0].textContent,'FLR-ABCDE · 2/8');s.root.children[0].children[1].click();assert.deepEqual(s.joins,['FLR-ABCDE']);assert(s.root.children[1].children[1].disabled);
 s.browser.close();assert(s.root.children[0].children[1].disabled,'Hidden browser must not allow stale entry');
});
test('browser handles empty/error states and ignores stale responses after leaving menu',async()=>{
 let resolve,mode='empty';const s=setup(async()=>{if(mode==='error')throw Error('offline');if(mode==='slow')return new Promise(r=>resolve=r);return {ok:true,json:async()=>({rooms:[]})}});
 await s.browser.open();assert.match(s.status.textContent,/Nenhuma sala pública/);mode='error';await s.browser.refresh();assert.match(s.status.textContent,/Não foi possível/);assert(!s.button.disabled);
 mode='slow';const wait=s.browser.refresh();s.browser.close();resolve({ok:true,json:async()=>({rooms:[{code:'FLR-ABCDE',players:1,capacity:8}]})});await wait;assert.equal(s.root.children.length,0);
});
test('browser loads subsequent pages without discarding existing rooms',async()=>{
 const urls=[],s=setup(async url=>{urls.push(url);return {ok:true,json:async()=>url.includes('cursor=')?{rooms:[{code:'FLR-FGHIJ',players:1,capacity:8}],cursor:null}:{rooms:[{code:'FLR-ABCDE',players:2,capacity:8}],cursor:'room:flr-abcde'}}});
 await s.browser.open();await s.browser.refresh(true);assert.equal(s.root.children.length,2);assert.match(urls[1],/cursor=room%3Aflr-abcde/);assert.match(s.status.textContent,/2 sala/);
});
