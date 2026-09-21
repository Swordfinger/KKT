import {sqliteTable,text,integer,real,primaryKey,index,uniqueIndex} from 'drizzle-orm/sqlite-core';
export const users=sqliteTable('users',{
 id:text('id').primaryKey(), username:text('username').unique(), passwordHash:text('password_hash'),
 nickname:text('nickname').notNull().default(''),birthDate:text('birth_date'),birthTime:text('birth_time'),chart:text('chart'),
 city:text('city').notNull().default(''),bio:text('bio').notNull().default(''),interests:text('interests').notNull().default('[]'),
 gender:text('gender').notNull().default('unspecified'),seeking:text('seeking').notNull().default('any'),
 minAge:integer('min_age').notNull().default(18),maxAge:integer('max_age').notNull().default(100),
 consent:integer('consent').notNull().default(0),version:integer('version').notNull().default(0),updatedAt:integer('updated_at').notNull()
});
export const pairs=sqliteTable('recommendation_pairs',{
 id:text('id').primaryKey(),day:text('day').notNull(),a:text('a').notNull().references(()=>users.id),b:text('b').notNull().references(()=>users.id),
 aVersion:integer('a_version').notNull(),bVersion:integer('b_version').notNull(),score:real('score').notNull(),reasons:text('reasons').notNull(),
 aDismissed:integer('a_dismissed').notNull().default(0),bDismissed:integer('b_dismissed').notNull().default(0),createdAt:integer('created_at').notNull()
},t=>[uniqueIndex('pair_once').on(t.a,t.b),index('pair_day_a').on(t.day,t.a),index('pair_day_b').on(t.day,t.b)]);
export const likes=sqliteTable('likes',{
 sender:text('sender').notNull().references(()=>users.id),recipient:text('recipient').notNull().references(()=>users.id),active:integer('active').notNull().default(1),createdAt:integer('created_at').notNull()
},t=>[primaryKey({columns:[t.sender,t.recipient]}),index('likes_sender_active').on(t.sender,t.active)]);
export const sessions=sqliteTable('sessions',{tokenHash:text('token_hash').primaryKey(),userId:text('user_id').notNull().references(()=>users.id),expiresAt:integer('expires_at').notNull()},t=>[index('sessions_expiry').on(t.expiresAt)]);
export const engine=sqliteTable('engine',{id:integer('id').primaryKey(),owner:text('owner'),leaseUntil:integer('lease_until').notNull().default(0),lastRun:integer('last_run').notNull().default(0)});
