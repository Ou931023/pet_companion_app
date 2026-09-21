const { createStore, listLimit, failure } = require('./moodDiaryStore');

function registerMoodDiaryRoutes(app, { requireResidentCaller, staffAuth, authz, store = createStore() }) {
  const privateResponse = (_req, res, next) => {
    res.set('Cache-Control', 'private, no-store');
    next();
  };
  const handle = (fn) => async (req, res) => {
    try { await fn(req, res); } catch (error) {
      const known = [400, 403, 404].includes(error.status);
      res.status(known ? error.status : 503).json({ success: false, error: known ? error.code : 'diary_unavailable' });
    }
  };
  app.get('/api/mood-diary', privateResponse, requireResidentCaller, handle(async (req, res) => {
    res.json({ success: true, entries: await store.list(req.residentCaller, listLimit(req.query.limit)) });
  }));
  app.post('/api/mood-diary', privateResponse, requireResidentCaller, handle(async (req, res) => {
    res.status(201).json({ success: true, entry: await store.create(req.residentCaller, req.body) });
  }));
  app.patch('/api/mood-diary/:id', privateResponse, requireResidentCaller, handle(async (req, res) => {
    res.json({ success: true, entry: await store.share(req.residentCaller, req.params.id, req.body) });
  }));
  app.delete('/api/mood-diary/:id', privateResponse, requireResidentCaller, handle(async (req, res) => {
    await store.remove(req.residentCaller, req.params.id);
    res.json({ success: true });
  }));
  app.get('/api/admin/residents/:residentId/mood-diary', privateResponse, staffAuth, handle(async (req, res) => {
    if (!(await authz.assertCanAccessResident(req.authContext, req.params.residentId))) throw failure(403, 'forbidden');
    res.json({ success: true, entries: await store.listShared(req.params.residentId, req.authContext, listLimit(req.query.limit)) });
  }));
}
module.exports = { registerMoodDiaryRoutes };
