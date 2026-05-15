const router = require('express').Router();

router.use('/auth', require('./auth.routes'));
router.use('/users', require('./user.routes'));
router.use('/drivers', require('./driver.routes'));
router.use('/trips', require('./trip.routes'));
router.use('/ratings', require('./rating.routes'));
router.use('/unlocks', require('./unlock.routes'));
router.use('/chats', require('./chat.routes'));
router.use('/geo', require('./geo.routes'));

module.exports = router;
