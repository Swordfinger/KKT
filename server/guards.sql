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
