const router = require('express').Router();
const { requireAuth } = require('../middleware/auth');
const { getProfile, updateProfile } = require('../controllers/userController');

router.get('/:id', requireAuth, getProfile);
router.patch('/:id', requireAuth, updateProfile);

module.exports = router;
