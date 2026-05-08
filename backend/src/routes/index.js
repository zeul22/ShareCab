const router = require('express').Router();

router.use('/auth', require('./auth.routes'));
router.use('/users', require('./user.routes'));
router.use('/drivers', require('./driver.routes'));
router.use('/trips', require('./trip.routes'));
router.use('/ratings', require('./rating.routes'));

module.exports = router;
