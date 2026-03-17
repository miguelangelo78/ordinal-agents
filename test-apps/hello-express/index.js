const express = require('express');
const app = express();
const PORT = 8000;

app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>Hello World</title>
      <style>
        body {
          font-family: Arial, sans-serif;
          display: flex;
          justify-content: center;
          align-items: center;
          height: 100vh;
          margin: 0;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }
        .container {
          text-align: center;
          background: white;
          padding: 3rem;
          border-radius: 10px;
          box-shadow: 0 10px 40px rgba(0,0,0,0.2);
        }
        h1 {
          color: #333;
          margin: 0 0 1rem 0;
        }
        p {
          color: #666;
          font-size: 1.2rem;
        }
        .info {
          margin-top: 2rem;
          padding: 1rem;
          background: #f5f5f5;
          border-radius: 5px;
          font-size: 0.9rem;
          color: #555;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>🎉 Hello World!</h1>
        <p>Express.js is running successfully</p>
        <div class="info">
          <strong>Port:</strong> ${PORT}<br>
          <strong>Timestamp:</strong> ${new Date().toISOString()}
        </div>
      </div>
    </body>
    </html>
  `);
});

app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    port: PORT
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Express server running on http://0.0.0.0:${PORT}`);
  console.log(`✅ Health check: http://0.0.0.0:${PORT}/api/health`);
});
