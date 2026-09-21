import {DatabaseSync} from 'node:sqlite';
import {readFileSync,readdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
export function database(path=':memory:'){
 const raw=new DatabaseSync(path);raw.exec('PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;');
 function prepared(sql,values=[]){return {bind(...args){return prepared(sql,args)},async first(){return raw.prepare(sql).get(...values)||null},async all(){return {results:raw.prepare(sql).all(...values)}},async run(){const result=raw.prepare(sql).run(...values);return {meta:{changes:Number(result.changes)}}},_run(){return raw.prepare(sql).run(...values)}}}
 return {raw,prepare:prepared,async batch(statements){raw.exec('BEGIN IMMEDIATE');try{const results=statements.map(s=>({meta:{changes:Number(s._run().changes)}}));raw.exec('COMMIT');return results}catch(e){raw.exec('ROLLBACK');throw e}},close(){raw.close()}};
}
export function migrate(db){const root=fileURLToPath(new URL('../drizzle/',import.meta.url));db.raw.exec('CREATE TABLE IF NOT EXISTS _migrations(name TEXT PRIMARY KEY)');for(const name of readdirSync(root).filter(n=>n.endsWith('.sql')).sort()){if(db.raw.prepare('SELECT name FROM _migrations WHERE name=?').get(name))continue;db.raw.exec('BEGIN IMMEDIATE');try{db.raw.exec(readFileSync(root+name,'utf8'));db.raw.prepare('INSERT INTO _migrations(name) VALUES(?)').run(name);db.raw.exec('COMMIT')}catch(e){db.raw.exec('ROLLBACK');throw e}}}
