const router = require('express').Router();
const { requireAuth } = require('../middleware/auth');
const { listMessages, postMessage } = require('../controllers/chatController');

router.get('/:groupId', requireAuth, listMessages);
router.post('/:groupId', requireAuth, postMessage);

module.exports = router;
