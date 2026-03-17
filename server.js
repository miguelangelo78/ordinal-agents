const express = require('express');
const app = express();
const PORT = process.env.PORT || 8000;

// Middleware
app.use(express.json());

// Routes
app.get('/', (req, res) => {
  res.json({ message: 'Hello from Express!' });
});

app.get('/api/status', (req, res) => {
  res.json({
    status: 'running',
    timestamp: new Date().toISOString()
  });
});

app.post('/api/echo', (req, res) => {
  res.json({
    received: req.body,
    echo: `You sent: ${JSON.stringify(req.body)}`
  });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Express server running on http://0.0.0.0:${PORT}`);
});
