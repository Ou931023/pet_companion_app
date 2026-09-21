function registerDailyCareTaskEditRoutes(app, { requireResidentCaller, staffAuth, editTask }) {
  const handle = (staff) => async (req, res) => {
    res.set('Cache-Control', 'private, no-store');
    try {
      const task = await editTask(req.params.taskId, req.body, staff
        ? { authContext: req.authContext } : { residentCaller: req.residentCaller });
      res.json({ success: true, task });
    } catch (error) {
      const known = [400, 403, 404, 409].includes(error.status);
      res.status(known ? error.status : 503).json({ success: false, error: known ? error.code : 'task_unavailable' });
    }
  };
  app.patch('/api/daily-care-tasks/:taskId', requireResidentCaller, handle(false));
  app.patch('/api/admin/daily-care-tasks/:taskId', staffAuth, handle(true));
}
module.exports = { registerDailyCareTaskEditRoutes };
