const { randomUUID } = require('node:crypto');

const moods = new Set(['happy', 'okay', 'low', 'worried']);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function failure(status, code) {
  return Object.assign(new Error(code), { status, code });
}
function payloadKeys(value, allowed) {
  return value && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).every((key) => allowed.includes(key));
}
function validateCreate(body) {
  if (!payloadKeys(body, ['mood', 'content', 'sharedWithCaregiver'])
      || !moods.has(body.mood) || typeof body.content !== 'string'
      || (Object.hasOwn(body, 'sharedWithCaregiver') && typeof body.sharedWithCaregiver !== 'boolean')) {
    throw failure(400, 'invalid_payload');
  }
  const content = body.content.trim();
  if (!content || [...content].length > 1000 || content.includes('\0')) throw failure(400, 'invalid_payload');
  return { mood: body.mood, content, sharedWithCaregiver: body.sharedWithCaregiver ?? false };
}
function validateShare(body) {
  if (!payloadKeys(body, ['sharedWithCaregiver']) || typeof body.sharedWithCaregiver !== 'boolean') {
    throw failure(400, 'invalid_payload');
  }
  return body.sharedWithCaregiver;
}
function listLimit(value) {
  if (value === undefined) return 50;
  if (typeof value !== 'string' || !/^[1-9]\d{0,2}$/.test(value) || Number(value) > 100) {
    throw failure(400, 'invalid_payload');
  }
  return Number(value);
}
function entry(row) {
  return {
    id: row.id, mood: row.mood, content: row.content,
    createdAt: new Date(row.created_at).toISOString(),
    sharedWithCaregiver: row.shared_with_caregiver === true,
  };
}
function createStore(injectedPg) {
  const db = () => injectedPg || require('../../db/postgres');
  async function owner(caller) {
    if (!uuid.test(caller?.userId || '') || !uuid.test(caller?.elderId || '')) throw failure(403, 'forbidden');
    const result = await db().query(
      `SELECT id FROM users WHERE id = $1 AND elder_id = $2
       AND role = 'elder' AND COALESCE(status, 'active') = 'active'`,
      [caller.userId, caller.elderId],
    );
    if (!result.rows.length) throw failure(403, 'forbidden');
  }
  return {
    async list(caller, limit) {
      await owner(caller);
      const result = await db().query(
        `SELECT * FROM mood_diary_entries WHERE user_id = $1 AND elder_id = $2
         ORDER BY created_at DESC, id DESC LIMIT $3`, [caller.userId, caller.elderId, limit],
      );
      return result.rows.map(entry);
    },
    async create(caller, body) {
      const value = validateCreate(body);
      await owner(caller);
      // INSERT SELECT rechecks identity at the write, including account deletion races.
      const result = await db().query(
        `INSERT INTO mood_diary_entries (id,user_id,elder_id,mood,content,shared_with_caregiver)
         SELECT $1, id, elder_id, $4, $5, $6 FROM users
         WHERE id = $2 AND elder_id = $3 AND role = 'elder'
           AND COALESCE(status, 'active') = 'active' RETURNING *`,
        [randomUUID(), caller.userId, caller.elderId, value.mood, value.content, value.sharedWithCaregiver],
      );
      if (!result.rows.length) throw failure(403, 'forbidden');
      return entry(result.rows[0]);
    },
    async share(caller, id, body) {
      const shared = validateShare(body);
      await owner(caller);
      if (!uuid.test(id)) throw failure(404, 'not_found');
      const result = await db().query(
        `UPDATE mood_diary_entries SET shared_with_caregiver = $4
         WHERE id = $1 AND user_id = $2 AND elder_id = $3 RETURNING *`,
        [id, caller.userId, caller.elderId, shared],
      );
      if (!result.rows.length) throw failure(404, 'not_found');
      return entry(result.rows[0]);
    },
    async remove(caller, id) {
      await owner(caller);
      if (!uuid.test(id)) throw failure(404, 'not_found');
      const result = await db().query(
        'DELETE FROM mood_diary_entries WHERE id = $1 AND user_id = $2 AND elder_id = $3 RETURNING id',
        [id, caller.userId, caller.elderId],
      );
      if (!result.rows.length) throw failure(404, 'not_found');
    },
    async listShared(elderId, context, limit) {
      if (!uuid.test(elderId)) throw failure(400, 'invalid_payload');
      // Recheck the active assignment inside the same statement that reads content.
      const result = await db().query(
        `SELECT d.* FROM mood_diary_entries d
         WHERE d.elder_id = $1 AND d.shared_with_caregiver = TRUE
           AND ($3::boolean OR EXISTS (
             SELECT 1 FROM resident_caregiver_links l JOIN users u ON u.id = l.caregiver_id
             WHERE l.elder_id = d.elder_id AND l.caregiver_id = $4
               AND l.status = 'active' AND u.role = 'caregiver' AND COALESCE(u.status, 'active') = 'active'))
         ORDER BY d.created_at DESC, d.id DESC LIMIT $2`,
        [elderId, limit, context.role === 'super_admin', context.caregiverId || null],
      );
      return result.rows.map(entry);
    },
  };
}
module.exports = { createStore, validateCreate, validateShare, listLimit, failure, payloadKeys };
