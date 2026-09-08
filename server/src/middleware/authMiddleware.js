const jwt = require("jsonwebtoken");
const pool = require("../db");

const authenticateToken = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    const token = authHeader && authHeader.split(" ")[1];

    if (!token) {
      return res.status(401).json({
        success: false,
        message: "Access token required. Please login.",
      });
    }

    const decoded = jwt.verify(token, process.env.JWT_SECRET || "duochat_super_secret_key_2026");

    if (!decoded || !decoded.userId) {
      return res.status(403).json({
        success: false,
        message: "Invalid or expired token.",
      });
    }

    // Verify that the user exists in database and belongs to the authorized users
    const userRes = await pool.query("SELECT id, name, email FROM users WHERE id = $1", [decoded.userId]);

    if (userRes.rows.length === 0) {
      return res.status(403).json({
        success: false,
        message: "User not authorized or account no longer exists.",
      });
    }

    // Strict 2-User Enforcement: Only userId 1 and 2 are allowed
    const uid = Number(userRes.rows[0].id);
    if (uid !== 1 && uid !== 2) {
      console.warn(`[AUTH MIDDLEWARE] Rejected unauthorized userId: ${uid}`);
      return res.status(403).json({
        success: false,
        message: "Access denied.",
      });
    }

    req.user = userRes.rows[0];
    next();
  } catch (err) {
    console.error("JWT Authentication error:", err.message);
    return res.status(403).json({
      success: false,
      message: "Invalid or expired token.",
    });
  }
};

module.exports = { authenticateToken };
