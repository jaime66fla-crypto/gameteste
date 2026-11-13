const fs=require('node:fs'),{execFileSync}=require('node:child_process');
let count=0;
for(const dir of ['public','src'])for(const file of fs.readdirSync(dir))if(file.endsWith('.js')){execFileSync(process.execPath,['--check',dir+'/'+file],{stdio:'inherit'});count++;}
console.log(`${count} JavaScript files passed syntax checks`);
