CREATE TABLE `engine` (
	`id` integer PRIMARY KEY NOT NULL,
	`owner` text,
	`lease_until` integer DEFAULT 0 NOT NULL,
	`last_run` integer DEFAULT 0 NOT NULL
);
--> statement-breakpoint
CREATE TABLE `likes` (
	`sender` text NOT NULL,
	`recipient` text NOT NULL,
	`active` integer DEFAULT 1 NOT NULL,
	`created_at` integer NOT NULL,
	PRIMARY KEY(`sender`, `recipient`),
	FOREIGN KEY (`sender`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`recipient`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `likes_sender_active` ON `likes` (`sender`,`active`);--> statement-breakpoint
CREATE TABLE `recommendation_pairs` (
	`id` text PRIMARY KEY NOT NULL,
	`day` text NOT NULL,
	`a` text NOT NULL,
	`b` text NOT NULL,
	`a_version` integer NOT NULL,
	`b_version` integer NOT NULL,
	`score` real NOT NULL,
	`reasons` text NOT NULL,
	`a_dismissed` integer DEFAULT 0 NOT NULL,
	`b_dismissed` integer DEFAULT 0 NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`a`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`b`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `pair_once` ON `recommendation_pairs` (`a`,`b`);--> statement-breakpoint
CREATE INDEX `pair_day_a` ON `recommendation_pairs` (`day`,`a`);--> statement-breakpoint
CREATE INDEX `pair_day_b` ON `recommendation_pairs` (`day`,`b`);--> statement-breakpoint
CREATE TABLE `sessions` (
	`token_hash` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`expires_at` integer NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `sessions_expiry` ON `sessions` (`expires_at`);--> statement-breakpoint
CREATE TABLE `users` (
	`id` text PRIMARY KEY NOT NULL,
	`username` text,
	`password_hash` text,
	`nickname` text DEFAULT '' NOT NULL,
	`birth_date` text,
	`birth_time` text,
	`chart` text,
	`city` text DEFAULT '' NOT NULL,
	`bio` text DEFAULT '' NOT NULL,
	`interests` text DEFAULT '[]' NOT NULL,
	`gender` text DEFAULT 'unspecified' NOT NULL,
	`seeking` text DEFAULT 'any' NOT NULL,
	`min_age` integer DEFAULT 18 NOT NULL,
	`max_age` integer DEFAULT 100 NOT NULL,
	`consent` integer DEFAULT 0 NOT NULL,
	`version` integer DEFAULT 0 NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `users_username_unique` ON `users` (`username`);
--> statement-breakpoint
CREATE TRIGGER recommendation_guard BEFORE INSERT ON recommendation_pairs BEGIN
 SELECT CASE WHEN NEW.a >= NEW.b THEN RAISE(ABORT,'INVALID_PAIR') END;
 SELECT CASE WHEN NEW.day != date(NEW.created_at,'unixepoch','+8 hours') THEN RAISE(ABORT,'INVALID_DAY') END;
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.a AND consent=1 AND chart IS NOT NULL AND version=NEW.a_version AND birth_date<=date(NEW.created_at,'unixepoch','+8 hours','-18 years')) OR NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.b AND consent=1 AND chart IS NOT NULL AND version=NEW.b_version AND birth_date<=date(NEW.created_at,'unixepoch','+8 hours','-18 years')) THEN RAISE(ABORT,'PROFILE_CHANGED') END;
 SELECT CASE WHEN (SELECT count(*) FROM recommendation_pairs WHERE day=NEW.day AND (a=NEW.a OR b=NEW.a))>=20 OR (SELECT count(*) FROM recommendation_pairs WHERE day=NEW.day AND (a=NEW.b OR b=NEW.b))>=20 THEN RAISE(ABORT,'DAILY_RECOMMENDATION_LIMIT') END;
END;
--> statement-breakpoint
CREATE TRIGGER recommendation_immutable BEFORE UPDATE ON recommendation_pairs WHEN NEW.id!=OLD.id OR NEW.day!=OLD.day OR NEW.a!=OLD.a OR NEW.b!=OLD.b OR NEW.created_at!=OLD.created_at OR NEW.score!=OLD.score OR NEW.reasons!=OLD.reasons OR NEW.a_version!=OLD.a_version OR NEW.b_version!=OLD.b_version BEGIN SELECT RAISE(ABORT,'IMMUTABLE_DELIVERY'); END;
--> statement-breakpoint
CREATE TRIGGER recommendation_no_delete BEFORE DELETE ON recommendation_pairs BEGIN SELECT RAISE(ABORT,'IMMUTABLE_DELIVERY'); END;
--> statement-breakpoint
CREATE TRIGGER like_state_guard BEFORE INSERT ON likes WHEN NEW.active NOT IN(0,1) OR NEW.sender=NEW.recipient BEGIN SELECT RAISE(ABORT,'INVALID_LIKE'); END;
--> statement-breakpoint
CREATE TRIGGER like_insert_guard BEFORE INSERT ON likes WHEN NEW.active=1 BEGIN
 SELECT CASE WHEN NEW.sender=NEW.recipient THEN RAISE(ABORT,'INVALID_LIKE') END;
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.sender AND consent=1) OR NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.recipient AND consent=1) THEN RAISE(ABORT,'PROFILE_UNAVAILABLE') END;
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM recommendation_pairs WHERE (a=NEW.sender AND b=NEW.recipient) OR (b=NEW.sender AND a=NEW.recipient)) THEN RAISE(ABORT,'NOT_RECOMMENDED') END;
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM likes WHERE sender=NEW.sender AND recipient=NEW.recipient AND active=1) AND (SELECT count(*) FROM likes WHERE sender=NEW.sender AND active=1)>=20 THEN RAISE(ABORT,'LIKE_LIMIT') END;
END;
--> statement-breakpoint
CREATE TRIGGER like_update_guard BEFORE UPDATE ON likes BEGIN
 SELECT CASE WHEN NEW.sender!=OLD.sender OR NEW.recipient!=OLD.recipient OR NEW.active NOT IN(0,1) THEN RAISE(ABORT,'INVALID_LIKE') END;
 SELECT CASE WHEN OLD.active!=1 AND NEW.active=1 AND (SELECT count(*) FROM likes WHERE sender=NEW.sender AND active=1)>=20 THEN RAISE(ABORT,'LIKE_LIMIT') END;
 SELECT CASE WHEN OLD.active!=1 AND NEW.active=1 AND NOT EXISTS(SELECT 1 FROM recommendation_pairs WHERE (a=NEW.sender AND b=NEW.recipient) OR (b=NEW.sender AND a=NEW.recipient)) THEN RAISE(ABORT,'NOT_RECOMMENDED') END;
 SELECT CASE WHEN NEW.active=1 AND (NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.sender AND consent=1) OR NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.recipient AND consent=1)) THEN RAISE(ABORT,'PROFILE_UNAVAILABLE') END;
END;
