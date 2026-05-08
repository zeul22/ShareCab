const router = require('express').Router();
const { requireAuth } = require('../middleware/auth');
const { rate } = require('../controllers/ratingController');

router.post('/', requireAuth, rate);

module.exports = router;
