const { HttpError } = require('./errorHandler');

function validateBody(schema) {
  return (req, _res, next) => {
    const result = schema.safeParse(req.body);
    if (!result.success) {
      return next(new HttpError(400, 'Validation failed', result.error.flatten()));
    }
    req.body = result.data;
    next();
  };
}

module.exports = { validateBody };
