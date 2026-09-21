import {build} from 'esbuild';
import {mkdir,copyFile,cp,readFile,writeFile} from 'node:fs/promises';
await mkdir('dist/server',{recursive:true});await mkdir('dist/.openai',{recursive:true});
await build({entryPoints:['server/worker.mjs'],bundle:true,format:'esm',platform:'browser',target:'es2022',outfile:'dist/server/index.js',loader:{'.html':'text','.css':'text'},plugins:[{name:'client-text',setup(b){b.onLoad({filter:/web[\\/]app\.js$/},async args=>({contents:await readFile(args.path,'utf8'),loader:'text'}))}}]});
const hosting=JSON.parse(await readFile('.openai/hosting.json','utf8'));delete hosting.static;hosting.d1='DB';
await writeFile('dist/.openai/hosting.json',JSON.stringify(hosting,null,2));await cp('drizzle','dist/.openai/drizzle',{recursive:true});console.log('Worker and database migrations built.');
